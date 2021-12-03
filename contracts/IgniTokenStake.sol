// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "./library/Governance.sol";
import "./interface/IPool.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/interfaces/IERC20.sol";

contract IgniTokenStake is Governance, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    IERC20 public stakingToken;

    uint256 public constant DURATION = 7 days;
    uint256 public _startTime = 9999999999;
    uint256 public _periodFinish = 0;
    uint256 public _rewardRate = 0;
    uint256 public _realrewardRate = 0;
    uint256 public _lastUpdateTime;
    uint256 public _rewardPerTokenStored;
    uint256 public _harvestInterval = 24 hours;
    uint256 public totalLockedUpRewards;

    uint256 public _baseRate = 10000;

    mapping(address => uint256) public _userRewardPerTokenPaid;
    mapping(address => uint256) public _rewards;
    mapping(address => uint256) public _lastStakedTime;
    mapping(address => uint256) public _nextHarvestUntil;
    mapping(address => uint256) public _rewardLockedUp;

    uint256 public _totalSupply;

    mapping(address => uint256) public _balances;
    uint256 public _totalRewardBalance; // Current reward global balance

    event RewardAdded(uint256 reward);
    event TokenStaked(address indexed user, uint256 amount);
    event WithdrawnIgni(address indexed user, uint256 amount);
    event RewardPaid(address indexed user, uint256 reward);
    event RewardLockedUp(address indexed user, uint256 reward);

    constructor(address _stakingToken) {
        stakingToken = IERC20(_stakingToken);
    }

    // We will go for a contract with autocompound soon.
    function upgradeAndSendRewardsFunds(
        address newRewardContract,
        uint256 amountToTransfer
    ) external onlyGovernance {
        require(
            _totalRewardBalance.sub(amountToTransfer) > 0,
            "we can transfer only reward amount"
        );
        _totalRewardBalance = _totalRewardBalance.sub(amountToTransfer);
        stakingToken.transfer(newRewardContract, amountToTransfer); // Only the remaining undistributed value
    }

    // call one time only!
    function initRewardStart(uint256 totalRewardBalance, uint256 startTime)
        external
        onlyGovernance
    {
        _totalRewardBalance = totalRewardBalance;
        _startTime = startTime;
        _lastUpdateTime = _startTime;
        _periodFinish = startTime.add(DURATION); // fix first cycle, allow unit test
    }

    function updateRewardHandle(address account) public {
        _rewardPerTokenStored = rewardPerToken();
        _lastUpdateTime = lastTimeRewardApplicable();
        if (account != address(0)) {
            _rewards[account] = earned(account);
            _userRewardPerTokenPaid[account] = _rewardPerTokenStored;
        }
    }

    function rewardPerToken() public view returns (uint256) {
        if (totalSupply() == 0) {
            return _rewardPerTokenStored;
        }
        return
            _rewardPerTokenStored.add(
                lastTimeRewardApplicable()
                    .sub(_lastUpdateTime)
                    .mul(_rewardRate)
                    .mul(1e18)
                    .div(totalSupply())
            );
    }

    function lastTimeRewardApplicable() public view returns (uint256) {
        return Math.min(block.timestamp, _periodFinish);
    }

    function totalSupply() public view returns (uint256) {
        return _totalSupply;
    }

    function earned(address account) public view returns (uint256) {
        return
            balanceOf(account)
                .mul(rewardPerToken().sub(_userRewardPerTokenPaid[account]))
                .div(1e18)
                .add(_rewards[account]);
    }

    function balanceOf(address account) public view returns (uint256) {
        return _balances[account];
    }

    function balanceAndWeight(address account)
        public
        view
        returns (uint256 balance, uint256 weight)
    {
        balance = _balances[account];
        weight = totalSupply() > 0 ? totalSupply().div(_balances[account]) : 0;
    }

    modifier updateReward(address account) {
        updateRewardHandle(account);
        _;
    }

    function canHarvest(address account) public view returns (bool) {
        return block.timestamp >= _nextHarvestUntil[account];
    }

    // stake token
    function stake(uint256 _amount, address account)
        public
        nonReentrant
        updateReward(account)
        checkStart
    {
        require(_totalRewardBalance > 0, "we dont have more reward balance");

        _totalSupply = _amount + _totalSupply;
        _balances[account] += _amount;

        stakingToken.transferFrom(account, address(this), _amount);

        if (_nextHarvestUntil[account] == 0) {
            _nextHarvestUntil[account] = block.timestamp.add(
                _harvestInterval
            );
        }
        _lastStakedTime[account] = block.timestamp;

        emit TokenStaked(account, _amount);
    }

    function withdraw(uint256 _amount)
        public
        nonReentrant
        updateReward(msg.sender)
        checkStart
    {
        require(
            _balances[msg.sender] >= _amount,
            "you dont have enough balance"
        );

        _totalSupply -= _amount;
        _balances[msg.sender] -= _amount;
        stakingToken.transfer(msg.sender, _amount);
    }

    function exit() external {
        withdraw(_balances[msg.sender]);
        harvest(msg.sender);
    }

    function pendingRewards(address account) public view returns (uint256) {
        return earned(account).add(_rewardLockedUp[account]);
    }

    function compound() external { // we dont need nonReentrant guard here
        uint256 balance = stakingToken.balanceOf(msg.sender);
        harvest(msg.sender);
        uint256 balanceAfter = stakingToken.balanceOf(msg.sender);
        uint256 amount = balanceAfter.sub(balance);
        if(amount > 0) stake(amount, msg.sender);
    }

    function harvest(address account)
        public
        nonReentrant
        updateReward(account)
        checkStart
    {
        uint256 reward = earned(account);
        if (canHarvest(account)) {
            if (reward > 0 || _rewardLockedUp[account] > 0) {
                reward = reward.add(_rewardLockedUp[account]);
                require(
                    stakingToken.balanceOf(address(this)).sub(reward) >=
                        _totalSupply,
                    "ensuring original balance to all stakeholders"
                );

                _rewards[account] = 0;
                // reset lockup
                totalLockedUpRewards = totalLockedUpRewards.sub(
                    _rewardLockedUp[account]
                );
                _rewardLockedUp[account] = 0;
                _nextHarvestUntil[account] = block.timestamp.add(
                    _harvestInterval
                );

                if (reward > 0) {
                    stakingToken.safeTransfer(account, reward);
                    _totalRewardBalance = _totalRewardBalance.sub(reward);
                }

                emit RewardPaid(account, reward);
            }
        } else if (reward > 0) {
            _rewards[account] = 0;
            _rewardLockedUp[account] = _rewardLockedUp[account].add(reward);
            totalLockedUpRewards = totalLockedUpRewards.add(reward);
            emit RewardLockedUp(account, reward);
        }
    }

    modifier checkStart() {
        require(block.timestamp > _startTime, "not start");
        _;
    }

    // USe with caution!
    function setRewardEmerg(uint256 rewardRate, uint256 realrewardRate)
        external
        onlyGovernance
        updateReward(address(0))
    {
        _rewardRate = rewardRate;
        _realrewardRate = realrewardRate;
    }

    //for extra reward
    function notifyReward(uint256 reward)
        external
        onlyGovernance
        updateReward(address(0))
    {
        uint256 realReward = reward;

        if (block.timestamp >= _periodFinish) {
            _rewardRate = realReward.div(DURATION);
            _realrewardRate = realReward;
        } else {
            uint256 remaining = _periodFinish.sub(block.timestamp);
            uint256 leftover = remaining.mul(_rewardRate);
            _rewardRate = realReward.add(leftover).div(DURATION);
            _realrewardRate = realReward;
        }
        _lastUpdateTime = block.timestamp;
        _periodFinish = block.timestamp.add(DURATION);

        emit RewardAdded(realReward);
    }

    function setHarvestInterval(uint256 harvestInterval) public onlyGovernance {
        _harvestInterval = harvestInterval;
    }
}
