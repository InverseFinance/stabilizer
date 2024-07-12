pragma solidity ^0.8.21;


interface IStrat {
    function invest() external; // underlying amount must be sent from vault to strat address before
    function divest(uint amount) external; // should send requested amount to vault directly, not less or more
    function calcTotalValue() external returns (uint);
    function underlying() external view returns (address);
}

// WARNING: This contract assumes synth and reserve are equally valuable and share the same decimals (e.g. Dola and Dai)
// DO NOT USE WITH USDC OR USDT
// DO NOT USE WITH NON-STANDARD ERC20 TOKENS
interface IStabilizer {

    //Variables
    function MAX_FEE() external returns(uint);
    function FEE_DENOMINATOR() external returns(uint);
    function buyFee() external returns(uint);
    function sellFee() external returns(uint);
    function supplyCap() external returns(uint);
    function supply() external returns(uint);
    function synth() external returns(address);
    function reserve() external returns(address);
    function operator() external returns(address);
    function strat() external returns(IStrat);
    function governace() external returns(address);

    //Functions

    function setBuyFee(uint amount) external;

    function setSellFee(uint amount) external;
    
    function setCap(uint amount) external;

    function setGovernance(address gov_) external;

    function setStrat(address newStrat) external;

    function removeStrat() external;

    function takeProfit() external;

    function buy(uint amount) external;

    function sell(uint amount) external;

    function rescue(address token) external;
}
