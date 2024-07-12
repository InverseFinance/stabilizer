// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
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
    address public stabilizer = address(0xdeadbeef);
    uint minDaiPrice = 99000000;
    DSRStrat public dsrStrat;
    IMintable public dola = IMintable(0x865377367054516e17014CcdED1e7d814EDC9ce4);
    IPot public constant POT = IPot(0x197E90f9FAD81970bA7976f33CbD77088E5D7cf7);
    IERC20 public underlying;


    function setUp() public {
        //This will fail if there's no mainnet variable in foundry.toml
        string memory url = vm.rpcUrl("mainnet");
        vm.createSelectFork(url);

        dsrStrat = new DSRStrat(address(stabilizer), gov);
        underlying = dsrStrat.underlying();
        vm.startPrank(gov);
        dsrStrat.setMinDaiPrice(minDaiPrice);
        vm.stopPrank();
    }

    function test_emergencyWithdraw() external {
        uint govBalBefore = underlying.balanceOf(gov);
        deal(address(underlying), address(dsrStrat), 1 ether);
        dsrStrat.invest();
        deal(address(underlying), address(dsrStrat), 1 ether);
        
        vm.expectRevert("ONLY GOV");
        dsrStrat.emergencyWithdraw();

        vm.prank(gov);
        dsrStrat.emergencyWithdraw();
        
        assertEq(underlying.balanceOf(address(dsrStrat)), 0);
        assertApproxEqAbs(underlying.balanceOf(gov), govBalBefore + 2 ether, 2);

    }

    //Access control tests
    function test_divest_failOnNonStabilizer() external {
        uint govBalBefore = underlying.balanceOf(gov);
        deal(address(underlying), address(dsrStrat), 1 ether);
        dsrStrat.invest();
        deal(address(underlying), address(dsrStrat), 1 ether);
        
        vm.expectRevert("ONLY STABILIZER");
        dsrStrat.divest(1 ether);
    }

    function test_setDaiFeed() external {
        vm.expectRevert("ONLY GOV");
        dsrStrat.setDaiFeed(address(0));
        vm.prank(gov);
        dsrStrat.setDaiFeed(address(0xdead));
        assertEq(address(0xdead), address(dsrStrat.feed()));
    }

    function test_setMinDaiPrice() external {
        vm.expectRevert("ONLY GOV");
        dsrStrat.setMinDaiPrice(1 ether);
        vm.prank(gov);
        dsrStrat.setMinDaiPrice(1 ether);
        assertEq(1 ether, dsrStrat.minDaiPrice());
    }

    function test_setChangeGov() external {
        vm.expectRevert("ONLY GOV");
        dsrStrat.setPendingGov(user);

        vm.prank(gov);
        dsrStrat.setPendingGov(user);
        assertEq(dsrStrat.pendingGov(), user);

        vm.expectRevert("ONLY PENDING GOV");
        dsrStrat.acceptGov();

        vm.prank(user);
        dsrStrat.acceptGov();
        assertEq(dsrStrat.pendingGov(), address(0));
        assertEq(dsrStrat.gov(), user);
    }
}
