// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import {IStabilizer} from "src/IStabilizer.sol";
import {DSRStrat, IERC20, IChainlinkFeed} from "src/strats/DSRStrat.sol";

interface IMintable is IERC20 {
    function addMinter(address newMinter) external;
}

interface IPot {
    function chi() external view returns (uint);
    function drip() external;
    function pie(address) external view returns (uint slice);
}


contract StabilizerTest is Test {
    
    address public gov=0x926dF14a23BE491164dCF93f4c468A50ef659D5B;
    address public user=address(0xA);
    IStabilizer public stabilizer;
    uint minDaiPrice = 99000000;
    uint supplyCap = 1_000_000 ether;
    DSRStrat public dsrStrat;
    IMintable public dola = IMintable(0x865377367054516e17014CcdED1e7d814EDC9ce4);
    IPot public constant POT = IPot(0x197E90f9FAD81970bA7976f33CbD77088E5D7cf7);
    IERC20 public underlying;


    function setUp() public {
        //This will fail if there's no mainnet variable in foundry.toml
        string memory url = vm.rpcUrl("mainnet");
        vm.createSelectFork(url);

        stabilizer = IStabilizer(0x7eC0D931AFFBa01b77711C2cD07c76B970795CDd);
        dsrStrat = new DSRStrat(address(stabilizer), gov);
        underlying = dsrStrat.underlying();
        vm.startPrank(gov);
        stabilizer.setStrat(address(dsrStrat));
        stabilizer.setCap(supplyCap);
        dsrStrat.setMinDaiPrice(minDaiPrice);
        dola.addMinter(address(stabilizer));
        vm.stopPrank();
    }

    function test_buy_noFee() public {
        uint amount = 1 ether;
        deal(address(underlying), user, amount);
        vm.prank(gov);
        stabilizer.setBuyFee(0);
        uint supplyBefore = stabilizer.supply();
        
        vm.startPrank(user);
        underlying.approve(address(stabilizer), amount);
        stabilizer.buy(amount);
        vm.stopPrank();

        assertEq(underlying.balanceOf(user), 0, "underlying balance of user > 0");
        assertEq(dola.balanceOf(user), amount, "dola balance of user != amount");
        assertEq(stabilizer.supply(), supplyBefore + amount, "supply did not increase by amount");
    }

    function test_buy_withFee() public {
        uint amount = 1 ether;
        uint fee = 1000;
        uint amountWithFee = amount + amount * fee / 10000;
        vm.prank(gov);
        stabilizer.setBuyFee(fee);
        deal(address(underlying), user, amountWithFee);
        uint supplyBefore = stabilizer.supply();
        
        vm.startPrank(user);
        underlying.approve(address(stabilizer), amountWithFee);
        stabilizer.buy(amount);
        vm.stopPrank();

        assertEq(underlying.balanceOf(user), 0, "underlying balance of user > 0");
        assertEq(dola.balanceOf(user), amount, "dola balance of user != amount");
        assertEq(stabilizer.supply(), supplyBefore + amount, "supply did not increase by amount");

    }

    function test_buy_fail_aboveSupplyCap() public {
        uint amount = supplyCap + 1;
        deal(address(underlying), user, amount);
        vm.prank(gov);
        stabilizer.setBuyFee(0);
        
        vm.startPrank(user);
        underlying.approve(address(stabilizer), amount);
        vm.expectRevert("supply exceeded cap");
        stabilizer.buy(amount);
        vm.stopPrank();
    }

    function test_buy_fail_priceBelowMinPrice() public {
        uint amount = 1 ether;
        vm.prank(gov);
        stabilizer.setBuyFee(0);
        deal(address(underlying), user, amount);
        
        vm.startPrank(user);
        underlying.approve(address(stabilizer), amount);
        vm.mockCall(
            address(0xAed0c38402a5d19df6E4c03F4E2DceD6e29c1ee9), //DAI USD chainlink feed
            abi.encodeWithSelector(IChainlinkFeed.latestAnswer.selector),
            abi.encode(int(minDaiPrice - 1))
        );
        vm.expectRevert("dai depeg");
        stabilizer.buy(amount);
        vm.stopPrank();
    }

    function test_sell_noFee() public {
        uint amount = 1 ether;
        deal(address(underlying), user, amount);
        vm.startPrank(gov);
        stabilizer.setBuyFee(0);
        stabilizer.setSellFee(0);
        vm.stopPrank();
        uint supplyBefore = stabilizer.supply();
        
        vm.startPrank(user);
        underlying.approve(address(stabilizer), amount);
        stabilizer.buy(amount);
        dola.approve(address(stabilizer), amount);
        stabilizer.sell(amount);
        vm.stopPrank();

        assertEq(underlying.balanceOf(user), amount, "underlying balance of user != amount");
        assertEq(dola.balanceOf(user), 0, "dola balance of user != 0");
        assertEq(stabilizer.supply(), supplyBefore, "supply did not return");   
    }

    function test_sell_withFee() public {
        uint amount = 1 ether;
        uint fee = 1000;
        uint amountWithFee = amount - amount * fee / 10000;
        deal(address(underlying), user, amount);
        vm.startPrank(gov);
        stabilizer.setBuyFee(0);
        stabilizer.setSellFee(fee);
        vm.stopPrank();
        uint supplyBefore = stabilizer.supply();
        
        vm.startPrank(user);
        underlying.approve(address(stabilizer), amount);
        stabilizer.buy(amount);
        dola.approve(address(stabilizer), amount);
        stabilizer.sell(amount);
        vm.stopPrank();

        assertEq(underlying.balanceOf(user), amountWithFee, "underlying balance of user != amount");
        assertEq(dola.balanceOf(user), 0, "dola balance of user != 0");
        assertEq(stabilizer.supply(), supplyBefore, "supply did not return");   
    }


    function test_takeProfit_noTimePass() public {
        uint amount = 1 ether;
        deal(address(underlying), user, amount);
        vm.startPrank(gov);
        stabilizer.setBuyFee(0);
        stabilizer.setSellFee(0);
        vm.stopPrank();
        uint govUnderlyingBefore = underlying.balanceOf(gov);
        
        vm.startPrank(user);
        underlying.approve(address(stabilizer), amount);
        stabilizer.buy(amount);
        stabilizer.takeProfit();
        dola.approve(address(stabilizer), amount);
        stabilizer.sell(amount);
        vm.stopPrank();

        assertGt(govUnderlyingBefore + 1e8, underlying.balanceOf(gov), "underlying balance of gov increase by more than dust amount");
    }

    function test_takeProfit_timePass() public {
        uint amount = 1 ether;
        deal(address(underlying), user, amount);
        vm.startPrank(gov);
        stabilizer.setBuyFee(0);
        stabilizer.setSellFee(0);
        uint supplyBefore = stabilizer.supply();
        vm.stopPrank();
        
        vm.startPrank(user);
        underlying.approve(address(stabilizer), amount);
        dola.approve(address(stabilizer), amount);
        stabilizer.buy(amount);
        stabilizer.takeProfit();
        uint govUnderlyingBefore = underlying.balanceOf(gov);
        vm.warp(block.timestamp + 365 days);
        stabilizer.sell(amount);
        stabilizer.takeProfit();
        dola.approve(address(stabilizer), amount);
        vm.stopPrank();

        assertGt(underlying.balanceOf(gov), govUnderlyingBefore, "underlying balance of gov didn't increase");
        assertEq(underlying.balanceOf(user), amount, "underlying balance of user != amount");
        assertEq(dola.balanceOf(user), 0, "dola balance of user != 0");
        assertEq(stabilizer.supply(), supplyBefore, "supply did not return");   
    }

    //Access control

    function test_setBuyFee() external {
        vm.expectRevert("ONLY GOV");
        stabilizer.setBuyFee(1000);

        vm.expectRevert("amount too high");
        vm.prank(gov);
        stabilizer.setBuyFee(1001);

        vm.prank(gov);
        stabilizer.setBuyFee(1000);
        assertEq(stabilizer.buyFee(), 1000);
    }

    function test_setSellFee() external {
        vm.expectRevert("ONLY GOV");
        stabilizer.setSellFee(1000);

        vm.expectRevert("amount too high");
        vm.prank(gov);
        stabilizer.setSellFee(1001);

        vm.prank(gov);
        stabilizer.setSellFee(1000);
        assertEq(stabilizer.sellFee(), 1000);
    }

    function test_setCap() external {
        vm.expectRevert("ONLY OPERATOR OR GOV");
        stabilizer.setCap(1);

        vm.prank(gov);
        stabilizer.setCap(1);
        assertEq(stabilizer.supplyCap(), 1);
    }

    function test_setGovernance() external {
        vm.expectRevert("ONLY GOV");
        stabilizer.setGovernance(address(0xdead));

        vm.prank(gov);
        stabilizer.setGovernance(address(0xdead));
        assertEq(stabilizer.governance(), address(0xdead));
    }
}
