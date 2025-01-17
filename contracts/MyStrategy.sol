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

interface ISexLocker{
    function lock(address _user, uint256 _amount, uint256 _weeks) external returns(bool); //Needs approval of SEX
    function initiateExitStream() external returns (bool);
    function withdrawExitStream() external returns (bool);
    function userBalance(address _users) external view returns(uint256);
    function streamableBalance(address _user) external view returns(uint256);
    function claimableExitStreamBalance(address _user) external view returns(uint256);
}

interface IFeeDistributor{
    function feeTokensLength() external view returns (uint256);
    function feeTokens(uint256 i) external view returns (address);
    function claimable(address _user, address[] calldata _tokens)
        external view returns (uint256[] memory amounts);
    function claim(address _user, address[] calldata _tokens)
        external returns (uint256[] memory claimedAmounts);
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
    //Sex token that gets locked
    address constant SEX_TOKEN = 0xD31Fcd1f7Ba190dBc75354046F6024A9b86014d7;
    //SOLID token
    address constant SOLID = 0x888EF71766ca594DED1F0FA3AE64eD2941740A20;
    //Fee distributor contract
    address constant FEE_DISTRIBUTOR = 0xA5e76B97e12567bbA2e822aC68842097034C55e7;

    uint256 public lastLock;

    uint256 public wantPooled;

    /// @dev Initialize the Strategy with security settings as well as tokens
    /// @notice Proxies will set any non constant variable you declare as default value
    /// @dev add any extra changeable variable at end of initializer as shown
    function initialize(address _vault, address[1] memory _wantConfig) public initializer {
        __BaseStrategy_init(_vault);
        /// @dev Add config here
        want = _wantConfig[0]; //want Solidsex (VE_DEPOSITOR)
        lastLock = 0;
        wantPooled = 0;


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
        //Approve SEX locking
        IERC20Upgradeable(SEX_TOKEN).safeApprove(
            SEX_LOCKER,
            type(uint256).max
        );
    }
    
    /// @dev Return the name of the strategy
    function getName() external pure override returns (string memory) {
        return "Solidex Vault Strategy";
    }

    /// @dev Return a list of fee tokens earned from staking sex. While removing want, solid, and sex
    function getFeeTokens() public view returns (address[] memory){
        address[] memory feeTokens = new address[](IFeeDistributor(FEE_DISTRIBUTOR).feeTokensLength());
        uint256 toRemove = 0;
        uint256 tokenCount = IFeeDistributor(FEE_DISTRIBUTOR).feeTokensLength();

        //Remove Solid, SolidSex, and Sex from the array
        for(uint256 i = 0; i < tokenCount; i++){
            address token = IFeeDistributor(FEE_DISTRIBUTOR).feeTokens(i);
            if(token == want || token == SOLID || token == SEX_TOKEN){
                toRemove++;
            } 
            else{
                feeTokens[i - toRemove] = token;
            }
        }

        address[] memory feeTokensAdjusted = new address[](feeTokens.length - toRemove);
        for(uint256 i = 0; i < feeTokensAdjusted.length; i++){
            feeTokensAdjusted[i] = feeTokens[i];
        }
        
        return feeTokensAdjusted;
    }


    /// @dev Gets an array of address of fee tokens that are claimable
    function getClaimable() public view returns (address[] memory){
        address[] memory feeTokens = new address[](IFeeDistributor(FEE_DISTRIBUTOR).feeTokensLength());
        uint256 toRemove = 0;
        uint256 tokenCount = IFeeDistributor(FEE_DISTRIBUTOR).feeTokensLength();

        for(uint256 i = 0; i < tokenCount; i++){
            address token = IFeeDistributor(FEE_DISTRIBUTOR).feeTokens(i);
            address[] memory tokenArr = new address[](1);
            tokenArr[0] = token;
            if(IFeeDistributor(FEE_DISTRIBUTOR).claimable(address(this), tokenArr)[0] > 0){
                feeTokens[i - toRemove] = token;
            }
            else{
                toRemove++;
            }
        }

        address[] memory feeTokensAdjusted = new address[](feeTokens.length - toRemove);
        for(uint256 i = 0; i < feeTokensAdjusted.length; i++){
            feeTokensAdjusted[i] = feeTokens[i];
        }
        
        return feeTokensAdjusted;
    }

    /// @dev Return a list of protected tokens
    /// @notice It's very important all tokens that are meant to be in the strategy to be marked as protected
    /// @notice this provides security guarantees to the depositors they can't be sweeped away
    function getProtectedTokens() public view virtual override returns (address[] memory) {
        address[] memory feeTokens = getFeeTokens();

        address[] memory protectedTokens = new address[](3 + feeTokens.length);
        protectedTokens[0] = want;
        protectedTokens[1] = SOLID;
        protectedTokens[2] = SEX_TOKEN;

        for(uint256 i = 0; i < feeTokens.length; i++){
            protectedTokens[i + 3] = feeTokens[i];
        }

        return protectedTokens;
    }

    /// @dev Deposit `_amount` of want, investing it to earn yield
    function _deposit(uint256 _amount) internal override {
        // Stake SOLIDsex
        ISolidSexStaking(STAKING_REWARDS).stake(_amount);
        wantPooled = wantPooled.add(_amount);
    }

    /// @dev Withdraw all funds, this is used for migrations, most of the time for emergency reasons
    function _withdrawAll() internal override {
        ISolidSexStaking(STAKING_REWARDS).getReward();
        if(wantPooled != 0){
            ISolidSexStaking(STAKING_REWARDS).withdraw(wantPooled);
        }
        wantPooled = 0;
        // Note, funds can potentially get stuck here
        if(lastLock != 0 && ISexLocker(SEX_LOCKER).streamableBalance(address(this)) > 0){
            ISexLocker(SEX_LOCKER).initiateExitStream();
        }
        if(lastLock != 0 && ISexLocker(SEX_LOCKER).claimableExitStreamBalance(address(this)) > 0){
            ISexLocker(SEX_LOCKER).withdrawExitStream();
        }
    }

    /// @dev Withdraw `_amount` of want, so that it can be sent to the vault / depositor
    /// @notice just unlock the funds and return the amount you could unlock
    function _withdrawSome(uint256 _amount) internal override returns (uint256) {
        if(_amount > balanceOfPool()){
            _amount = balanceOfPool();
        }
        uint256 wantBalance = IERC20Upgradeable(want).balanceOf(address(this));

        if(_amount > wantBalance){
            uint256 toWithdraw = _amount.sub(wantBalance);
            uint256 poolBalance = balanceOfPool();
            if(toWithdraw <= poolBalance){
                ISolidSexStaking(STAKING_REWARDS).withdraw(toWithdraw);
                wantPooled = wantPooled.sub(toWithdraw);
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

    /// @dev Claim fees earned from locking sex token
    function claimFees() internal {
        address[] memory feeTokens = getClaimable();
        IFeeDistributor(FEE_DISTRIBUTOR).claim(address(this), feeTokens);
    }

    /// @dev Used by harvest to get current token balances of this contract
    function tokenBalances() public view returns (TokenAmount[] memory balances){
        address[] memory feeTokens = getFeeTokens();
        balances = new TokenAmount[](3 + feeTokens.length);
        balances[0] = TokenAmount(want, IERC20Upgradeable(want).balanceOf(address(this)));
        balances[1] = TokenAmount(SOLID, IERC20Upgradeable(SOLID).balanceOf(address(this)));
        balances[2] = TokenAmount(SEX_TOKEN, IERC20Upgradeable(SEX_TOKEN).balanceOf(address(this)));
        for(uint256 i = 0; i < feeTokens.length; i++){
            balances[i + 3] = TokenAmount(
                feeTokens[i],
                IERC20Upgradeable(feeTokens[i]).balanceOf(address(this))
            );
        }
        return balances;
    }

    /// @dev Calculates the differences in token amounts, used for reporting harvests to the vault
    function tokenDifferences(TokenAmount[] memory before) internal view returns (TokenAmount[] memory amountAfter) {
        amountAfter = new TokenAmount[](before.length);
        for(uint256 i = 0; i < before.length; i++){
            (, uint256 amount) = IERC20Upgradeable(before[i].token).balanceOf(address(this)).trySub(before[i].amount);
            amountAfter[i] = TokenAmount(
                before[i].token,
                amount
            );
        }
        return amountAfter;
    }

    /// @dev Used to report any extra tokens earned to the vault
    function reportExtraTokens(TokenAmount[] memory tokens) internal {
        for(uint256 i = 1; i < tokens.length; i++){
            if(tokens[i].amount > 0){
                _processExtraToken(tokens[i].token, tokens[i].amount);
            }
        }
    }

    function _harvest() internal override returns (TokenAmount[] memory harvested) {
        TokenAmount[] memory startingBalances = tokenBalances();

        //Claim SEX and want from staked SOLIDsex
        ISolidSexStaking(STAKING_REWARDS).getReward();

        if(lastLock == 0 && IERC20Upgradeable(SEX_TOKEN).balanceOf(address(this)) > 0){
            lockSex();
        }
        else if(lastLock != 0 && lastLock < (now - 604800)){ //If a week has past since the last lock
            claimFees();
            if(IERC20Upgradeable(SEX_TOKEN).balanceOf(address(this)) > 0){
                lockSex();
            }
        }

        if(lastLock != 0 && ISexLocker(SEX_LOCKER).streamableBalance(address(this)) > 0){
            ISexLocker(SEX_LOCKER).initiateExitStream();
        }

        if(lastLock != 0 && ISexLocker(SEX_LOCKER).claimableExitStreamBalance(address(this)) > 0){
            ISexLocker(SEX_LOCKER).withdrawExitStream();
        }

        //Convert solid to want
        if (IERC20Upgradeable(SOLID).balanceOf(address(this)) > 0) {
            IVeDepositor(VE_DEPOSITOR).depositTokens(IERC20Upgradeable(SOLID).balanceOf(address(this)));
        }


        harvested = tokenDifferences(startingBalances);

        _reportToVault(harvested[0].amount);

        reportExtraTokens(harvested);


        //Redeposit want
        if(IERC20Upgradeable(want).balanceOf(address(this)) > 0){
            _deposit(IERC20Upgradeable(want).balanceOf(address(this)));
        }

        
        return harvested;
    }


    /// @dev Reverts
    function _tend() internal override returns (TokenAmount[] memory tended){
        revert("no-op");
    }

    /// @dev Return the balance (in want) that the strategy has invested somewhere
    function balanceOfPool() public view override returns (uint256) {
        return wantPooled;
    }

    /// @dev Returns the fees enarned through locking sex as an array of TokenAmounts
    function feesAccured() public view returns (TokenAmount[] memory){
        address[] memory feeTokens = getFeeTokens();
        uint256[] memory amounts = IFeeDistributor(FEE_DISTRIBUTOR).claimable(address(this), feeTokens);
        TokenAmount[] memory tokensEarned = new TokenAmount[](feeTokens.length);
        for(uint256 i = 0; i < feeTokens.length; i++){
            tokensEarned[i] = TokenAmount(feeTokens[i], amounts[i]);
        }
        return tokensEarned;
    }

    /// @dev Return the balance of rewards that the strategy has accrued
    /// @notice Used for offChain APY and Harvest Health monitoring
    function balanceOfRewards() external view override returns (TokenAmount[] memory rewards) {
        uint256 solidRewards = ISolidSexStaking(STAKING_REWARDS).earned(address(this), SOLID);
        uint256 sexRewards = ISolidSexStaking(STAKING_REWARDS).earned(address(this), SEX_TOKEN).add(
            ISexLocker(SEX_LOCKER).userBalance(address(this))
        );

        TokenAmount[] memory feesEarned = feesAccured();
        rewards = new TokenAmount[](3 + feesEarned.length);
        rewards[0] = TokenAmount(want, solidRewards); //Solid always gets converted to want in a 1:1 ratio
        rewards[1] = TokenAmount(SOLID, 0); 
        rewards[2] = TokenAmount(SEX_TOKEN, sexRewards); 
        for(uint256 i = 0; i < feesEarned.length; i++){
            rewards[i + 3] = feesEarned[i];
        }

        return rewards;
    }
}
