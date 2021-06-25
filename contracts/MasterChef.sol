// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import './libs/math/SafeMath.sol';
import './libs/token/BEP20/IBEP20.sol';
import './libs/token/BEP20/SafeBEP20.sol';
import './libs/access/Ownable.sol';

import "./EggpToken.sol";
import "./EPRewardToken.sol";

// import "@nomiclabs/buidler/console.sol";

// MasterChef is the master of Eggp. He can make Eggp and he is a fair guy.
//
// Note that it's ownable and the owner wields tremendous power. The ownership
// will be transferred to a governance smart contract once EGGP is sufficiently
// distributed and the community can show to govern itself.
//
// Have fun reading it. Hopefully it's bug-free. God bless.
contract MasterChef is Ownable {
    using SafeMath for uint256;
    using SafeBEP20 for IBEP20;

    // Info of each user.
    struct UserInfo {
        uint256 amount;     // How many LP tokens the user has provided.
        uint256 rewardDebt; // Reward debt. See explanation below.
        uint256 lastdeposit;
        //
        // We do some fancy math here. Basically, any point in time, the amount of EGGPs
        // entitled to a user but is pending to be distributed is:
        //
        //   pending reward = (user.amount * pool.accEggpPerShare) - user.rewardDebt
        //
        // Whenever a user deposits or withdraws LP tokens to a pool. Here's what happens:
        //   1. The pool's `accEggpPerShare` (and `lastRewardBlock`) gets updated.
        //   2. User receives the pending reward sent to his/her address.
        //   3. User's `amount` gets updated.
        //   4. User's `rewardDebt` gets updated.
    }

    // Info of each pool.
    struct PoolInfo {
        IBEP20 lpToken;              // Address of LP token contract.
        uint256 allocPoint;          // How many allocation points assigned to this pool. EGGPs to distribute per block.
        uint256 lastRewardBlock;     // Last block number that EGGPs distribution occurs.
        uint256 accEggpPerShare;     // Accumulated EGGPs per share, times 1e12. See below.
        uint256 earlyWithdrawTimer;  // Early withdraw countdown for the pool
        uint256 earlyWithdrawFee;    // Early withdraw fee
        uint256 eprtRewardRate;          // Reward rate for the EPRT (EggPlant Reward Token)
    }

    // The EGGP Token
    EggpToken public eggp;
    // The EPRT (Eggplant Rewards Token)
    EPRewardToken public eprt;
    // Dev address.
    address public devaddr;
    // EGGP tokens created per block.
    uint256 public eggpPerBlock;
    // Bonus muliplier for early eggp makers.
    uint256 public BONUS_MULTIPLIER = 1;
    // Harvest fees for native and non-native pools
    uint256 public harvestFee = 100;
    uint256 public harvestFeeNative = 100 ;
    // Info of each pool.
    PoolInfo[] public poolInfo;
    // Info of each user that stakes LP tokens.
    mapping (uint256 => mapping (address => UserInfo)) public userInfo;
    // Total allocation points. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint = 0;
    // The block number when EGGP mining starts.
    uint256 public startBlock;

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);

    constructor(
        EggpToken _eggp,
        EPRewardToken _eprt,
        address _devaddr,
        uint256 _eggpPerBlock,
        uint256 _startBlock
    ) public {
        eggp = _eggp;
        eprt = _eprt;
        devaddr = _devaddr;
        eggpPerBlock = _eggpPerBlock;
        startBlock = _startBlock;

        // staking pool
        poolInfo.push(PoolInfo({
            lpToken: _eggp,
            allocPoint: 1000,
            lastRewardBlock: startBlock,
            accEggpPerShare: 0,
            earlyWithdrawTimer: 0,
            earlyWithdrawFee: 0,
            eprtRewardRate: 1000
        }));

        totalAllocPoint = 1000;

    }

    function updateMultiplier(uint256 multiplierNumber) public onlyOwner {
        BONUS_MULTIPLIER = multiplierNumber;
    }

    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }
    
    //update fee
    function feeUpdate(uint256 _harvestFee,uint256 _harvestFeeNative) public onlyOwner{
        require(_harvestFee > 0 && _harvestFee <= 300, "Not within range");
        require(_harvestFeeNative > 0 && _harvestFeeNative <= 300, "Not within range");
        harvestFee = _harvestFee;
        harvestFeeNative = _harvestFeeNative;
    }

    function updateEmissionRate(uint256 _eggpPerBlock) public onlyOwner {
        require( _eggpPerBlock > 0 && _eggpPerBlock <= 20*(10**18), "Not within range" );
        massUpdatePools();
        eggpPerBlock = _eggpPerBlock;
    }

    // Add a new lp to the pool. Can only be called by the owner.
    // XXX DO NOT add the same LP token more than once. Rewards will be messed up if you do.
    // _earlyWithdrawTime is in hours.  
    // _rewardRate is the multiplier for EPRT reward rates.
    function add(uint256 _allocPoint, IBEP20 _lpToken, bool _withUpdate, uint256 _earlyWithdrawTime, uint256 _earlyWithdrawFee, uint256 _rewardRate) public onlyOwner {
        require(_earlyWithdrawFee > 0 && _earlyWithdrawFee <= 300, "early withdraw fee outside valid range");
        require(_earlyWithdrawTime > 0 && _earlyWithdrawTime <= 8760, "early withdraw timer outside valid range");  // 8760 hrs = 365 days
        require(_rewardRate > 0 && _rewardRate <= 2000, "invalid reward rate");  // Reward rate multiplier. Between 0 to 200%

        if (_withUpdate) {
            massUpdatePools();
        }
        uint256 lastRewardBlock = block.number > startBlock ? block.number : startBlock;
        totalAllocPoint = totalAllocPoint.add(_allocPoint);
        poolInfo.push(PoolInfo({
            lpToken: _lpToken,
            allocPoint: _allocPoint,
            lastRewardBlock: lastRewardBlock,
            accEggpPerShare: 0,
            earlyWithdrawTimer: _earlyWithdrawTime * 1 hours,
            earlyWithdrawFee: _earlyWithdrawFee,
            eprtRewardRate: _rewardRate
        }));
        updateStakingPool();
    }

    // Update the given pool's EGGP allocation point. Can only be called by the owner.
    function set(uint256 _pid, uint256 _allocPoint, bool _withUpdate, uint256 _earlyWithdrawTime, uint256 _earlyWithdrawFee, uint256 _rewardRate) public onlyOwner {
        require(_earlyWithdrawFee > 0 && _earlyWithdrawFee <= 300, "early withdraw fee outside valid range");
        require(_earlyWithdrawTime > 0 && _earlyWithdrawTime <= 8760, "early withdraw timer outside valid range");  // 8760 hrs = 365 days
        require(_rewardRate > 0 && _rewardRate <= 2000, "invalid reward rate");  // Reward rate multiplier. Between 0 to 200%

        if (_withUpdate) {
            massUpdatePools();
        }
        uint256 prevAllocPoint = poolInfo[_pid].allocPoint;
        poolInfo[_pid].allocPoint = _allocPoint;
        poolInfo[_pid].earlyWithdrawTimer = _earlyWithdrawTime * 1 hours;
        poolInfo[_pid].earlyWithdrawFee = _earlyWithdrawFee;
        poolInfo[_pid].eprtRewardRate = _rewardRate;

        if (prevAllocPoint != _allocPoint) {
            totalAllocPoint = totalAllocPoint.sub(prevAllocPoint).add(_allocPoint);
            updateStakingPool();
        }
    }

    // Update staking pool alloc points
    function updateStakingPool() internal {
        uint256 length = poolInfo.length;
        uint256 points = 0;
        for (uint256 pid = 1; pid < length; ++pid) {
            points = points.add(poolInfo[pid].allocPoint);
        }
        if (points != 0) {
            points = points.div(3);
            totalAllocPoint = totalAllocPoint.sub(poolInfo[0].allocPoint).add(points);
            poolInfo[0].allocPoint = points;
        }
    }

    // Return reward multiplier over the given _from to _to block.
    function getMultiplier(uint256 _from, uint256 _to) public view returns (uint256) {
        return _to.sub(_from).mul(BONUS_MULTIPLIER);
    }

    // View function to see pending EGGPs on frontend.
    function pendingEggp(uint256 _pid, address _user) external view returns (uint256) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accEggpPerShare = pool.accEggpPerShare;
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (block.number > pool.lastRewardBlock && lpSupply != 0) {
            uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
            uint256 eggpReward = multiplier.mul(eggpPerBlock).mul(pool.allocPoint).div(totalAllocPoint);
            accEggpPerShare = accEggpPerShare.add(eggpReward.mul(1e12).div(lpSupply));
        }
        return user.amount.mul(accEggpPerShare).div(1e12).sub(user.rewardDebt);
    }
    
    //view function to see time of lastdeposit
    function getlastdeposit(uint256 _pid, address _user) external view returns (uint256) {
        UserInfo memory user = userInfo[_pid][_user];
        return user.lastdeposit;
    }
    
    // Update reward variables for all pools. Be careful of gas spending!
    function massUpdatePools() public {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }

    // Update reward variables of the given pool to be up-to-date.
    function updatePool(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        if (block.number <= pool.lastRewardBlock) {
            return;
        }
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (lpSupply == 0) {
            pool.lastRewardBlock = block.number;
            return;
        }
        uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
        uint256 eggpReward = multiplier.mul(eggpPerBlock).mul(pool.allocPoint).div(totalAllocPoint);
        uint256 eggpfee;

        // Set harvest fees
        if(_pid == 0){
           // Native pool (EGGP token) 
           eggpfee=eggpReward.mul(harvestFeeNative).div(1000);
        }else{
           // Harvest fees for all other farms
           eggpfee=eggpReward.mul(harvestFee).div(1000);
        }

        eggp.mint(devaddr, eggpfee);
        //eggp.mint(address(eprt), eggpReward.sub(eggpfee));
        eggp.mint(address(eprt), eggpReward);

        pool.accEggpPerShare = pool.accEggpPerShare.add(eggpReward.mul(1e12).div(lpSupply));
        pool.lastRewardBlock = block.number;
    }

    // Deposit LP tokens to MasterChef for EGGP allocation.
    function deposit(uint256 _pid, uint256 _amount) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        updatePool(_pid);

        if (user.amount > 0) {
            uint256 pending = user.amount.mul(pool.accEggpPerShare).div(1e12).sub(user.rewardDebt);
	   
            if(pending > 0) {
                safeEggpTransfer(msg.sender, pending);
            }

        }
        if (_amount > 0) {
            pool.lpToken.safeTransferFrom(msg.sender, address(this), _amount);
            user.amount = user.amount.add(_amount);
            user.lastdeposit=now;

            // Mints a valueless token to the user as a separate reward (EPRT). The utility of the EPRT token is separate 
            // from the user providing liquidity, therefore it does not affect the value of the LP whatsoever.
            if (pool.eprtRewardRate > 0) {
               eprt.mint(msg.sender, _amount.mul(pool.eprtRewardRate).div(1000));  
            }
        }
        user.rewardDebt = user.amount.mul(pool.accEggpPerShare).div(1e12);

        emit Deposit(msg.sender, _pid, _amount);
    }

    // Withdraw LP tokens from MasterChef.
    function withdraw(uint256 _pid, uint256 _amount) public {

        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(user.amount >= _amount, "withdraw: not good");

        updatePool(_pid);
        uint256 pending = user.amount.mul(pool.accEggpPerShare).div(1e12).sub(user.rewardDebt);
        if(pending > 0) {
            safeEggpTransfer(msg.sender, pending);
        }
        if(_amount > 0) {
            user.amount = user.amount.sub(_amount);
            if(now>user.lastdeposit + pool.earlyWithdrawTimer ){
                pool.lpToken.safeTransfer(msg.sender, _amount);
            }else{
                uint256 fee=_amount.mul(pool.earlyWithdrawFee).div(1000);
                uint256 withdrawableLessFee=_amount.sub(fee);
                pool.lpToken.safeTransfer(msg.sender, withdrawableLessFee);
                pool.lpToken.safeTransfer(address(devaddr), fee);
                
             }
        }
        user.rewardDebt = user.amount.mul(pool.accEggpPerShare).div(1e12);
        emit Withdraw(msg.sender, _pid, _amount);
    }

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        pool.lpToken.safeTransfer(msg.sender, user.amount);
        emit EmergencyWithdraw(msg.sender, _pid, user.amount);
        user.amount = 0;
        user.rewardDebt = 0;
    }

    // Safe eggp transfer function, just in case if rounding error causes pool to not have enough EGGPs.
    function safeEggpTransfer(address _to, uint256 _amount) internal {
        eprt.safeEggpTransfer(_to, _amount);
    }

    // Update dev address by the previous dev.
    function dev(address _devaddr) public {
        require(msg.sender == devaddr, "dev: wut?");
        devaddr = _devaddr;
    }
}
