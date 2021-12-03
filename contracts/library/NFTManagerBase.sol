// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "../library/Governance.sol";
import "../interface/IPool.sol";
import "../interface/IStakeToken.sol";
import "../interface/IIgniNFTFactory.sol";
import "../interface/IIgniNFT.sol";
import "@openzeppelin/contracts/interfaces/IERC20.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract NFTManagerBase is Governance, IPool, ReentrancyGuard {
    using SafeMath for uint256;

    IERC20 public stakingToken = IERC20(address(0x0));
    IIgniNFTFactory public _nftFactory = IIgniNFTFactory(address(0x0));
    IIgniNFT public _nftToken = IIgniNFT(address(0x0));
    IStakeToken public _stakeTokenManager = IStakeToken(address(0x0)); // Used to compound on IGNI farm

    address public _playerBook = address(0x0);

    address public _rewardPool = address(0x0);

    uint256 public constant DURATION = 7 days;
    uint256 public _startTime = 9629028800;
    uint256 public _periodFinish = 0;
    uint256 public _rewardRate = 0;
    uint256 public _realrewardRate = 0;
    uint256 public _lastUpdateTime;
    uint256 public _rewardPerTokenStored;
    uint256 public _harvestInterval = 24 hours;
    uint256 public totalLockedUpRewards;

    uint256 public _baseRate = 10000;
    uint256 public _punishTime = 3 days;

    mapping(address => uint256) public _userRewardPerTokenPaid;
    mapping(address => uint256) public _rewards;
    mapping(address => uint256) public _lastStakedTime;
    mapping(address => uint256) public _nextHarvestUntil;
    mapping(address => uint256) public _rewardLockedUp;

    uint256 public _fixRateBase = 100000;

    mapping(address => uint256) public _ownerBalances;
    mapping(uint256 => uint256) public _nftBalances;

    uint256 public _totalBalance;

    mapping(address => uint256[]) public _nftsByAccount;
    mapping(uint256 => uint256) public _nftMapIndex;

    mapping(uint256 => bool) public _nftOnStake;
    mapping(uint256 => bool) public _nftOnMarket;
    mapping(uint256 => uint256) public _nftMarketPrice;

    event RewardAdded(uint256 reward);
    event StakedNFT(address indexed user, uint256 amount);
    event WithdrawnNFT(address indexed user, uint256 amount);
    event RewardPaid(address indexed user, uint256 reward);
    event RewardLockedUp(address indexed user, uint256 reward);
    event NFTReceived(
        address operator,
        address from,
        uint256 tokenId,
        bytes data
    );

    function unstakeInternal(uint256 nftId, address owner) internal {
        uint256[] memory nftIds = _nftsByAccount[owner];
        uint256 nftIndex = _nftMapIndex[nftId];

        uint256 nftArrayLength = nftIds.length - 1;
        uint256 tailId = nftIds[nftArrayLength];

        _nftsByAccount[owner][nftIndex] = tailId;
        _nftsByAccount[owner][nftArrayLength] = 0;

        _nftsByAccount[owner].pop();
        _nftMapIndex[tailId] = nftIndex;
        _nftMapIndex[nftId] = 0;

        uint256 stakeBalance = _nftBalances[nftId];
        _ownerBalances[owner] = _ownerBalances[owner].sub(stakeBalance);
        _totalBalance = _totalBalance.sub(stakeBalance);
        _nftOnStake[nftId] = false;
        _nftBalances[nftId] = 0;
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

    function totalSupply() public view override returns (uint256) {
        return _totalBalance;
    }

    function earned(address account) public view returns (uint256) {
        return
            balanceOf(account)
                .mul(rewardPerToken().sub(_userRewardPerTokenPaid[account]))
                .div(1e18)
                .add(_rewards[account]);
    }

    function balanceOf(address account) public view override returns (uint256) {
        return _ownerBalances[account];
    }

    modifier onlyExistsAndNftOwner(uint256 nftId) {
        address currOwner = _nftToken.ownerOf(nftId);
        IIgniNFT.Nft memory nft = _nftFactory.getNft(nftId);
        require(nft.id > 0, "nft not exists");
        require(
            (currOwner == msg.sender || currOwner == address(this)) &&
                nft.owner == msg.sender,
            "not nft owner"
        );
        _;
    }
}
