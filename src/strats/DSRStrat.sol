pragma solidity ^0.8.21;

interface IStrat {
    function invest() external; // underlying amount must be sent from stabilizer to strat address before
    function divest(uint amount) external; // should send requested amount to stabilizer directly, not less or more
    function calcTotalValue() external returns (uint);
    function underlying() external view returns (address);
}

interface IDSR {
    function daiBalance(address usr) external returns (uint wad);
    function pieOf(address usr) external view returns (uint wad);
    function join(address dst, uint wad) external;
    function exit(address dst, uint wad) external;
    function exitAll(address dst) external;
    function pot() external view returns (address);
}

interface IPot {
    function chi() external view returns (uint);
    function drip() external;
    function pie(address) external view returns (uint slice);
}

interface IERC20 {
    function balanceOf(address holder) external view returns(uint);
    function transferFrom(address from, address to, uint amount) external returns(bool);
    function transfer(address to, uint amount) external returns(bool);
    function approve(address to, uint amount) external;
}

interface IChainlinkFeed {
    function latestAnswer() external view returns(int256);
    function latestRoundData() external view returns(uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);
}

contract DSRStrat {
    address public immutable stabilizer;
    IDSR public constant DSR_MANAGER = IDSR(0x373238337Bfe1146fb49989fc222523f83081dDb);
    IPot public constant POT = IPot(0x197E90f9FAD81970bA7976f33CbD77088E5D7cf7);
    IERC20 public constant underlying = IERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);
    uint public minDaiPrice;
    address public gov;
    address public pendingGov;
    IChainlinkFeed public feed = IChainlinkFeed(0xAed0c38402a5d19df6E4c03F4E2DceD6e29c1ee9);

    modifier onlyStabilizer {
        require(msg.sender == stabilizer);
        _;
    }

    modifier onlyGov {
        require(msg.sender == gov);
        _;
    }

    modifier onlyPendingGov {
        require(msg.sender == pendingGov);
        _;
    }

    constructor(address stabilizer_, address gov_) {
        stabilizer = stabilizer_;
        gov = gov_;
        underlying.approve(address(DSR_MANAGER), type(uint).max);
    }

    function invest() external {
        if(address(feed) != address(0)){
            uint daiPrice = uint(feed.latestAnswer());
            require(daiPrice >= minDaiPrice, "dai depeg");
        }
        uint balance = underlying.balanceOf(address(this));
        if(balance > 0) {
            DSR_MANAGER.join(address(this), balance);
        }

    }

    function divest(uint amount) external onlyStabilizer {
        if(calcTotalValue() <= amount){
            //If trying to pay full balance, use exitAll to avoid dust being left over
            DSR_MANAGER.exitAll(stabilizer);
        } else {
            DSR_MANAGER.exit(stabilizer, amount);
        }
    }

    function calcTotalValue() public view returns (uint) {
        return rmul(POT.chi(), DSR_MANAGER.pieOf(address(this)));
    }

    function rmul(uint x, uint y) internal pure returns(uint){
        uint256 RAY = 10 ** 27;
        // always rounds down
        return x * y / RAY;
    }

    // Withdraw all DAI from DSR directly to treasury.
    function emergencyWithdraw() public onlyGov {
        DSR_MANAGER.exitAll(gov);
    }

    function setDaiFeed(address daiFeed) external onlyGov {
        feed = IChainlinkFeed(daiFeed);
    }

    function setMinDaiPrice(uint newMinDaiPrice) external onlyGov {
        minDaiPrice = newMinDaiPrice;
    }

    function setPendingGov(address newPendingGov) external onlyGov {
        pendingGov = newPendingGov;
    }

    function acceptGov() external onlyPendingGov {
        gov = pendingGov;
        pendingGov = address(0);
    }
}
