// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import {IERC20Upgradeable} from "@openzeppelin-contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import {MathUpgradeable} from "@openzeppelin-contracts-upgradeable/math/MathUpgradeable.sol";
import {SafeMathUpgradeable} from "@openzeppelin-contracts-upgradeable/math/SafeMathUpgradeable.sol";
import {SafeERC20Upgradeable} from "@openzeppelin-contracts-upgradeable/token/ERC20/SafeERC20Upgradeable.sol";

import {BaseStrategy} from "@badger-finance/BaseStrategy.sol";

interface IVeDepositor{
    function depositTokens(uint256 _amount) external returns (bool);
}

interface ISolidSexStaking{
    function stake(uint256 amount) external;
    function earned(address account, address _rewardsToken) external view returns (uint256);
    function getReward() external;
    function exit() external;
    function withdraw(uint256 amount) external;
}


struct route {
    address from;
    address to;
    bool stable;
}
interface ISolidlyRouter{
    function swapExactTokensForTokens(
    uint amountIn,
    uint amountOutMin,
    route[] calldata routes,
    address to,
    uint deadline
) external returns (uint[] memory amounts);

    function getAmountOut(uint amountIn, address tokenIn, address tokenOut) external view returns (uint amount, bool stable);

}

interface ISexLocker{
    function lock(address _user, uint256 _amount, uint256 _weeks) external returns(bool); //Needs approval of SEX
    function initiateExitStream() external returns (bool);
    function withdrawExitStream() external returns (bool);
    function userBalance(address _users) external view returns(uint256);
    function streamableBalance(address _user) external view returns(uint256);

}

contract MyStrategy is BaseStrategy {
    using SafeMathUpgradeable for uint256;
    using SafeERC20Upgradeable for IERC20Upgradeable;

// address public want; // Inherited from BaseStrategy
    // address public lpComponent; // Token that represents ownership in a pool, not always used
    // address public reward; // Token we farm

    address constant BADGER = 0x3472A5A71965499acd81997a54BBA8D852C6E53d;
    //Spookyswap router for swaps
    address constant SPOOKYSWAP_ROUTER = 0xF491e7B69E4244ad4002BC14e878a34207E38c29;
    //Contract for converting SOLID to SOLIDsex (Also SOLIDsex token address)
    address constant VE_DEPOSITOR = 0x41adAc6C1Ff52C5e27568f27998d747F7b69795B;
    //Contract for staking SOLIDsex
    address constant STAKING_REWARDS = 0x7FcE87e203501C3a035CbBc5f0Ee72661976D6E1;
    //Router contract for solidly
    address constant SOLIDLY_ROUTER = 0xa38cd27185a464914D3046f0AB9d43356B34829D;
    //Tokenlocker contract
    address constant SEX_LOCKER = 0xDcC208496B8fcc8E99741df8c6b8856F1ba1C71F; 

    address constant SEX_TOKEN = 0xD31Fcd1f7Ba190dBc75354046F6024A9b86014d7;
    address constant SOLID = 0x888EF71766ca594DED1F0FA3AE64eD2941740A20;

    uint256 public lastLock = 0;

    uint256 public wantPooled = 0;

    /// @dev Initialize the Strategy with security settings as well as tokens
    /// @notice Proxies will set any non constant variable you declare as default value
    /// @dev add any extra changeable variable at end of initializer as shown
    function initialize(address _vault, address[1] memory _wantConfig) public initializer {
        __BaseStrategy_init(_vault);
        /// @dev Add config here
        want = _wantConfig[0]; //want Solidsex (VE_DEPOSITOR)


        //Approve conversion of SOLID to SOLIDsex
        IERC20Upgradeable(SOLID).safeApprove(
            VE_DEPOSITOR,
            type(uint256).max
        );

        //Approve staking of SOLIDsex in staking contract
        IERC20Upgradeable(VE_DEPOSITOR).safeApprove(
            STAKING_REWARDS,
            type(uint256).max
        );
        //Approve transfer of SEX token back to SOLIDsex
        IERC20Upgradeable(SEX_TOKEN).safeApprove(
            SOLIDLY_ROUTER,
            type(uint256).max
        );
        IERC20Upgradeable(SOLID).safeApprove(
            SOLIDLY_ROUTER,
            type(uint256).max
        );

        //Approve SEX locking
        IERC20Upgradeable(SEX_TOKEN).safeApprove(
            SEX_LOCKER,
            type(uint256).max
        );
        
        // If you need to set new values that are not constants, set them like so
        // stakingContract = 0x79ba8b76F61Db3e7D994f7E384ba8f7870A043b7;

        // If you need to do one-off approvals do them here like so
        // IERC20Upgradeable(reward).safeApprove(
        //     address(DX_SWAP_ROUTER),
        //     type(uint256).max
        // );
    }
    
    /// @dev Return the name of the strategy
    function getName() external pure override returns (string memory) {
        return "Solidex Vault Strategy";
    }

    /// @dev Return a list of protected tokens
    /// @notice It's very important all tokens that are meant to be in the strategy to be marked as protected
    /// @notice this provides security guarantees to the depositors they can't be sweeped away
    function getProtectedTokens() public view virtual override returns (address[] memory) {
        address[] memory protectedTokens = new address[](2);
        protectedTokens[0] = SOLID;
        protectedTokens[1] = VE_DEPOSITOR;
        protectedTokens[2] = SEX_TOKEN;
        return protectedTokens;
    }

    /// @dev Deposit `_amount` of want, investing it to earn yield
    function _deposit(uint256 _amount) internal override {
        // Convert SOLID to SOLIDsex
        //IVeDepositor(VE_DEPOSITOR).depositTokens(_amount);
        // Stake SOLIDsex
        ISolidSexStaking(STAKING_REWARDS).stake(_amount);
        wantPooled.add(_amount);
    }

    /// @dev Withdraw all funds, this is used for migrations, most of the time for emergency reasons
    function _withdrawAll() internal override {
        ISolidSexStaking(STAKING_REWARDS).exit();
        if(lastLock < (now - 604800)){ //If a week has past since the last lock
            ISexLocker(SEX_TOKEN).initiateExitStream();
            ISexLocker(SEX_TOKEN).withdrawExitStream();
        }
        wantPooled = 0;
    }

    /// @dev Withdraw `_amount` of want, so that it can be sent to the vault / depositor
    /// @notice just unlock the funds and return the amount you could unlock
    function _withdrawSome(uint256 _amount) internal override returns (uint256) {
        // Add code here to unlock / withdraw `_amount` of tokens to the withdrawer
        // If there's a loss, make sure to have the withdrawer pay the loss to avoid exploits
        // Socializing loss is always a bad idea
        if(_amount > balanceOfPool()){
            _amount = balanceOfPool();
        }
        uint256 wantBalance = IERC20Upgradeable(want).balanceOf(address(this));

        if(_amount > wantBalance){
            uint256 toWithdraw = _amount.sub(wantBalance);
            uint256 poolBalance = balanceOfPool();
            if(toWithdraw <= poolBalance){
                ISolidSexStaking(STAKING_REWARDS).withdraw(toWithdraw);
                wantPooled.sub(toWithdraw);
            }
        }
        
        return MathUpgradeable.min(_amount, IERC20Upgradeable(want).balanceOf(address(this)));
    }


    /// @dev Does this function require `tend` to be called?
    function _isTendable() internal override pure returns (bool) {
        return false;
    }

    function lockSex() internal {
        //Lock for one week
        bool lock = ISexLocker(SEX_LOCKER).lock(address(this), IERC20Upgradeable(SEX_TOKEN).balanceOf(address(this)), 1); 
        if(lock) lastLock = now;
    }

    function _harvest() internal override returns (TokenAmount[] memory harvested) {
        uint256[] memory startingBalances = new uint256[](3);
        startingBalances[0] = IERC20Upgradeable(want).balanceOf(address(this));
        startingBalances[1] = IERC20Upgradeable(SOLID).balanceOf(address(this));
        startingBalances[2] = IERC20Upgradeable(SEX_TOKEN).balanceOf(address(this));

        //Claim SEX and want (SOLID) from staked SOLIDsex
        ISolidSexStaking(STAKING_REWARDS).getReward();

        uint256[] memory afterBalances = new uint256[](3);


        //Note, the contract code is not currently public for the SEX locker. 
        //It is quite possible that it will be more efficient to call extendLock() instead of withdrawing and re-locking
        if(IERC20Upgradeable(SEX_TOKEN).balanceOf(address(this)) > 0){
            if(lastLock == 0){
                lockSex();
            }
            else if(lastLock < (now - 604800)){ //If a week has past since the last lock
                ISexLocker(SEX_LOCKER).initiateExitStream();
                ISexLocker(SEX_LOCKER).withdrawExitStream();
                lockSex();
            }
        }

        //Trade SEX_TOKEN for want
        uint256 sexBalance = IERC20Upgradeable(SEX_TOKEN).balanceOf(address(this));
        if (sexBalance > 0) {
            (, bool stable) = ISolidlyRouter(SOLIDLY_ROUTER).getAmountOut(
                sexBalance,
                address(SEX_TOKEN),
                address(want)
            );

            route[] memory routeArray = new route[](1);
            routeArray[0] = route(address(SEX_TOKEN), address(want), stable);
            ISolidlyRouter(SOLIDLY_ROUTER).swapExactTokensForTokens(
                sexBalance,
                0, 
                routeArray,
                address(this),
                now
            );
        }

        //Convert SOLID to want (SOLIDsex)
        uint256 solidBalance = IERC20Upgradeable(SOLID).balanceOf(address(this));/*
        if (solidBalance > 0) {
            (uint amount, bool stable) = ISolidlyRouter(SOLIDLY_ROUTER).getAmountOut(
                solidBalance,
                address(SOLID),
                address(want)
            );

            //Convert or trade, picking the most beneficial one
            if(amount <= solidBalance){
                //If amount is less, convert instead of trading the tokens
                IVeDepositor(VE_DEPOSITOR).depositTokens(solidBalance);
            }
            else{
                route[] memory routeArray = new route[](1);
                routeArray[0] = route(address(SOLID), address(want), stable);
                ISolidlyRouter(SOLIDLY_ROUTER).swapExactTokensForTokens(
                    solidBalance,
                    0, 
                    routeArray,
                    address(this),
                    now
                );
            }


        }*/
        if (solidBalance > 0) {
            IVeDepositor(VE_DEPOSITOR).depositTokens(solidBalance);
        }


        afterBalances[0] = IERC20Upgradeable(want).balanceOf(address(this));
        afterBalances[1] = IERC20Upgradeable(SOLID).balanceOf(address(this));
        afterBalances[2] = IERC20Upgradeable(SEX_TOKEN).balanceOf(address(this));


        uint256 wantEarned = afterBalances[0].sub(startingBalances[0]);
        _reportToVault(wantEarned);

        //Redeposit want
        if(wantEarned > 0){
            _deposit(wantEarned);
        }
        

        harvested = new TokenAmount[](3);

        harvested[0] = TokenAmount(want, wantEarned);

        uint256 solidEarned = afterBalances[1].sub(startingBalances[1]);
        harvested[1] = TokenAmount(SOLID, solidEarned);
        if(solidEarned > 0) _processExtraToken(SOLID, solidEarned);

        uint256 sexEarned = afterBalances[2].sub(startingBalances[2]);
        harvested[2] = TokenAmount(SEX_TOKEN, sexEarned);
        if(solidEarned > 0) _processExtraToken(SEX_TOKEN, sexEarned);

        
        return harvested;
    }


    // Example tend is a no-op which returns the values, could also just revert
    function _tend() internal override returns (TokenAmount[] memory tended){
        revert("no-op");
    }

    /// @dev Return the balance (in want) that the strategy has invested somewhere
    function balanceOfPool() public view override returns (uint256) {
        return wantPooled;
    }

    /// @dev Return the balance of rewards that the strategy has accrued
    /// @notice Used for offChain APY and Harvest Health monitoring
    function balanceOfRewards() external view override returns (TokenAmount[] memory rewards) {
        uint256 solidRewards = ISolidSexStaking(STAKING_REWARDS).earned(address(this), SOLID);
        uint256 sexRewards = ISolidSexStaking(STAKING_REWARDS).earned(address(this), SEX_TOKEN).add(
            //Note, contract is not public, not 100% that this calculation is correct
            ISexLocker(SEX_LOCKER).userBalance(address(this)).add(
                ISexLocker(SEX_LOCKER).streamableBalance(address(this))
            )
        );

        rewards = new TokenAmount[](3);
        rewards[0] = TokenAmount(want, 0);
        rewards[1] = TokenAmount(SOLID, solidRewards); 
        rewards[2] = TokenAmount(SEX_TOKEN, sexRewards); 

        return rewards;
    }
}
