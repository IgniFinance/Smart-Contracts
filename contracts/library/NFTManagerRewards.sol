// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "./NFTManagerBase.sol";
import "./Governance.sol";
import "../interface/IPool.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/interfaces/IERC20.sol";

contract NFTManagerRewards is NFTManagerBase {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    // We will go for a contract with autocompound soon.
    function upgradeAndSendRewardsFunds(address newContract)
        external
        onlyGovernance
    {
        stakingToken.transfer(
            newContract,
            stakingToken.balanceOf(address(this))
        ); // Only the remaining undistributed value
    }

    //
    function initRewardStart(uint256 startTime) external onlyGovernance {
        _startTime = startTime;
        _lastUpdateTime = _startTime;
    }

    modifier updateReward(address account) {
        updateRewardHandle(account);
        _;
    }

    function pendingRewards(address account) public view returns (uint256) {
        return earned(account).add(_rewardLockedUp[account]);
    }

    function canHarvest(address account) public view returns (bool) {
        return block.timestamp >= _nextHarvestUntil[account];
    }

    function getStakePower(uint256 nftId) public view returns (uint256) {
        IIgniNFT.Nft memory nft = _nftFactory.getNft(nftId);
        require(nft.totalPower > 0, "the nft not nft");
        return nft.totalPower;
    }

    // stake NFT
    function stake(uint256 nftId)
        public
        nonReentrant
        updateReward(msg.sender)
        checkStart
        onlyExistsAndNftOwner(nftId)
    {
        uint256[] storage nftIds = _nftsByAccount[msg.sender];
        if (nftIds.length == 0) {
            nftIds.push(0);
            _nftMapIndex[0] = 0;
        }
        nftIds.push(nftId);
        _nftMapIndex[nftId] = nftIds.length - 1;

        uint256 totalPower = getStakePower(nftId);

        if (totalPower > 0) {
            _ownerBalances[msg.sender] = _ownerBalances[msg.sender].add(
                totalPower
            );
            _nftBalances[nftId] = totalPower;
            _totalBalance = _totalBalance.add(totalPower);
        }

        _nftOnStake[nftId] = true;
        if (!_nftOnMarket[nftId])
            _nftToken.safeTransferFrom(msg.sender, address(this), nftId);

        if (_nextHarvestUntil[msg.sender] == 0) {
            _nextHarvestUntil[msg.sender] = block.timestamp.add(
                _harvestInterval
            );
        }
        _lastStakedTime[msg.sender] = block.timestamp;
        emit StakedNFT(msg.sender, nftId);
    }

    function onERC721Received(
        address operator,
        address from,
        uint256 tokenId,
        bytes memory data
    ) public returns (bytes4) {
        emit NFTReceived(operator, from, tokenId, data);
        return
            bytes4(
                keccak256("onERC721Received(address,address,uint256,bytes)")
            );
    }

    function unstake(uint256 nftId)
        public
        nonReentrant
        updateReward(msg.sender)
        checkStart
        onlyExistsAndNftOwner(nftId)
    {
        unstakeInternal(nftId, msg.sender);

        // Will only be returned if not already on market
        if (!_nftOnMarket[nftId])
            _nftToken.safeTransferFrom(address(this), msg.sender, nftId);

        emit WithdrawnNFT(msg.sender, nftId);
    }

    function withdraw() public nonReentrant checkStart {
        uint256[] memory nftId = _nftsByAccount[msg.sender];
        for (uint8 index = 1; index < nftId.length; index++) {
            if (nftId[index] > 0) {
                unstake(nftId[index]);
            }
        }
    }

    function getPlayerIds(address account)
        public
        view
        returns (uint256[] memory nftId)
    {
        nftId = _nftsByAccount[account];
    }

    function exit() external nonReentrant {
        withdraw();
        harvest(msg.sender);
    }


    function compound() external { // we dont need nonReentrant guard here
        uint256 balance = stakingToken.balanceOf(msg.sender);
        harvest(msg.sender);
        uint256 balanceAfter = stakingToken.balanceOf(msg.sender);
        uint256 amount = balanceAfter.sub(balance);
        if(amount > 0) _stakeTokenManager.stake(amount, msg.sender); // Compound to IGNI BEP20 stake / farm
    }

    function harvest(address account)
        public
        nonReentrant
        updateReward(msg.sender)
        checkStart
    {
        uint256 reward = earned(account);
        if (canHarvest(account)) {
            if (reward > 0 || _rewardLockedUp[account] > 0) {
                _rewards[account] = 0;
                reward = reward.add(_rewardLockedUp[account]);

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

    // Use with caution!
    function setRewardEmerg(uint256 rewardRate, uint256 realrewardRate)
        external
        onlyGovernance
        updateReward(address(0))
    {
        _rewardRate = rewardRate;
        _realrewardRate = realrewardRate;
    }

    function balanceAndWeight(address account)
        public
        view
        returns (uint256 balance, uint256 weight)
    {
        balance = _ownerBalances[account];
        weight = totalSupply() > 0
            ? _ownerBalances[account].div(totalSupply())
            : 0;
    }
}
