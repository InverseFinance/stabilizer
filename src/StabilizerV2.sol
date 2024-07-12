pragma solidity ^0.8.21;

interface IStrat {
    function invest() external; // underlying amount must be sent from vault to strat address before
    function divest(uint amount) external; // should send requested amount to vault directly, not less or more
    function calcTotalValue() external returns (uint);
    function underlying() external view returns (address);
}

interface IERC20 {
    function balanceOf(address holder) external view returns(uint);
    function transferFrom(address from, address to, uint amount) external returns(bool);
    function transfer(address to, uint amount) external returns(bool);
    function approve(address to, uint amount) external;
}

interface IMintable is IERC20{
    function mint(address to, uint amount) external;
    function addMinter(address newMinter) external;
    function burn(uint amount) external;
}

// WARNING: This contract assumes synth and reserve are equally valuable and share the same decimals (e.g. Dola and Dai)
// DO NOT USE WITH USDC OR USDT
// DO NOT USE WITH NON-STANDARD IERC20 TOKENS
contract StabilizerV2 {

    uint public constant MAX_FEE = 1000; // 10%
    uint public constant FEE_DENOMINATOR = 10000;
    uint public buyFee;
    uint public sellFee;
    uint public supplyCap;
    uint public supply;
    IMintable public synth;
    IERC20 public reserve;
    address public operator;
    IStrat public strat;
    address public governance;

    constructor(IMintable synth_, address reserve_, address gov_, uint buyFee_, uint sellFee_, uint supplyCap_) {
        require(buyFee_ <= MAX_FEE, "buyFee_ too high");
        require(sellFee_ <= MAX_FEE, "sellFee_ too high");
        require(gov_ != address(0), "gov address(0)");
        synth = synth_;
        reserve = IERC20(reserve_);
        governance = gov_;
        buyFee = buyFee_;
        sellFee = sellFee_;
        operator = msg.sender;
        supplyCap = supplyCap_;
    }

    modifier onlyOperator {
        require(msg.sender == operator || msg.sender == governance, "ONLY OPERATOR OR GOV");
        _;
    }

    modifier onlyGovernance {
        require(msg.sender == governance, "ONLY GOV");
        _;
    }

    function setOperator(address operator_) public {
        require(msg.sender == governance || msg.sender == operator, "ONLY GOV OR OPERATOR");
        require(operator_ != address(0), "NO ADDRESS ZERO");
        operator = operator_;
    }

    function setBuyFee(uint amount) public onlyGovernance {
        require(amount <= MAX_FEE, "amount too high");
        buyFee = amount;
    }

    function setSellFee(uint amount) public onlyGovernance {
        require(amount <= MAX_FEE, "amount too high");
        sellFee = amount;
    }
    
    function setCap(uint amount) public onlyOperator {
        supplyCap = amount;
    }

    function setGovernance(address gov_) public onlyGovernance {
        require(gov_ != address(0), "NO ADDRESS ZERO");
        governance = gov_;
    }

    function setStrat(IStrat newStrat) public onlyGovernance {
        require(newStrat.underlying() == address(reserve), "Invalid strat");
        if(address(strat) != address(0)) {
            uint prevTotalValue = strat.calcTotalValue();
            if(prevTotalValue > 0) {
                strat.divest(prevTotalValue);
            }
        }
        uint reserveBal = reserve.balanceOf(address(this));
        if(reserveBal > 0){
            reserve.transfer(address(newStrat), reserveBal);
            newStrat.invest();
        }
        strat = newStrat;
    }

    function removeStrat() public onlyGovernance {
        uint prevTotalValue = strat.calcTotalValue();
        strat.divest(prevTotalValue);

        strat = IStrat(address(0));
    }

    function takeProfit() public {
        uint totalReserves = getTotalReserves();
        if(totalReserves > supply) {
            uint profit = totalReserves - supply; // underflow prevented by if condition
            if(address(strat) != address(0)) {
                uint bal = reserve.balanceOf(address(this));
                if(bal < profit) {
                    strat.divest(profit - bal); // underflow prevented by if condition
                }
            }
            reserve.transfer(governance, profit);
        }
    }

    function buy(uint amount) external {
        buy(msg.sender, amount);
    }

    function buy(address to, uint amount) public {
        supply += amount;
        require(supply <= supplyCap, "supply exceeded cap");
        uint amountIn = amount;
        if(buyFee > 0){
            uint fee = amount * buyFee / FEE_DENOMINATOR;
            amountIn += fee;
        }
        if(address(strat) != address(0)) {
            reserve.transferFrom(msg.sender, address(strat), amountIn);
            strat.invest();
        } else {
            reserve.transferFrom(msg.sender, address(this), amountIn);
        }
        emit Buy(msg.sender, amount, amountIn);

        synth.mint(to, amount);
    }

    function sell(uint amount) external {
        sell(msg.sender, amount);
    }

    function sell(address to, uint amount) public {
        synth.transferFrom(msg.sender, address(this), amount);
        synth.burn(amount);

        uint afterFee = amount;
        if(sellFee > 0) {
            uint fee = amount * sellFee / FEE_DENOMINATOR;
            afterFee -= fee;
        }

        uint reserveBal = reserve.balanceOf(address(this));
        if(address(strat) != address(0) && reserveBal < afterFee) {
            strat.divest(afterFee - reserveBal); // underflow prevented by if condition
        }
        
        reserve.transfer(to, afterFee);
        supply -= amount;
        emit Sell(msg.sender, amount, afterFee);
    }

    function rescue(IERC20 token) public onlyGovernance {
        require(token != reserve, "RESERVE CANNOT BE RESCUED");
        token.transfer(governance, token.balanceOf(address(this)));
    }

    function getTotalReserves() internal returns (uint256 bal) {
        bal = reserve.balanceOf(address(this));
        if(address(strat) != address(0)) {
            bal = bal + strat.calcTotalValue();
        }
    }

    event Buy(address indexed user, uint purchased, uint spent);
    event Sell(address indexed user, uint sold, uint received);
}
