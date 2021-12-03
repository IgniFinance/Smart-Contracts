// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;
pragma experimental ABIEncoderV2;

import "./interface/IIgniNFT.sol";
import "./interface/IIgniNFTChangeble.sol";
import "./interface/IIgniNFTFactory.sol";
import "./interface/IIgniNFTRuleProxy.sol";
import "./library/Governance.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract IgniNFTFactory is Governance, IIgniNFTFactory, IIgniNFTChangeble {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    event NftAdded(
        uint256 indexed id,
        uint256 tier,
        uint256 quality,
        address owner,
        uint256 power,
        uint256 bonusPowerPct,
        uint256 totalPower,
        address referral
    );

    event NftBurn(uint256 indexed id);

    struct MintNftPower {
        uint256 tier;
        uint256 power;
    }

    struct MintExtraData {
        uint256 nft_id;
        uint256 tier;
        uint256 quality;
        address owner;
    }

    event NFTReceived(
        address operator,
        address from,
        uint256 tokenId,
        bytes data
    );

    mapping(uint256 => IIgniNFT.Nft) public _nftes;
    mapping(uint256 => IIgniNFTRuleProxy) public _ruleProxys;
    mapping(uint256 => MintNftPower) public _nftFounderTypes;
    mapping(address => bool) public _ruleProxyFlags;

    uint256 public _nftId = 1;

    IIgniNFT public _igniNftToken;

    uint256 public _userStartTs = 9999999999;

    struct MintCostProgress {
        uint256 maxTotalNfts; //Max  NFT id
        uint256 ajustRate;
    }

    uint256 public _maxGlobalCap = 9999; // Definitive NFT cap, we dont have functions to change this
    uint256 private _baseRate = 10000;
    uint256 public _comissionRate = 500; // 5%

    address public _fundsWallet;

    MintCostProgress[] private _progressiveCost;

    uint256 private _randomNonce;
    uint256 public _nftMintPrice;
    address _nftManagerAddress;

    constructor(address igniNftToken) {
        _igniNftToken = IIgniNFT(igniNftToken);
    }

    function setNftManagerAddress(address nftManagerAddress)
        public
        onlyGovernance
    {
        _nftManagerAddress = nftManagerAddress;
    }

    function setFundsWallet(address fundsWallet) public onlyGovernance {
        _fundsWallet = fundsWallet;
    }

    function setMintPrice(uint256 newCost) public onlyGovernance {
        _nftMintPrice = newCost;
    }

    function setComissionRate(uint256 comissionRate) public onlyGovernance {
        _comissionRate = comissionRate;
    }

    function setProgressiveCost(MintCostProgress[] memory percentages)
        public
        onlyGovernance
    {
        for (uint256 i = 0; i < percentages.length; i++) {
            _progressiveCost.push(percentages[i]);
        }
    }

    function setUserStartMint(uint256 startTs) public onlyGovernance {
        _userStartTs = startTs;
    }

    function changeNftData(uint256 tokenId, NFtDataChangeble calldata nftData)
        public
    {
        require(
            msg.sender == _nftManagerAddress,
            "only nft manager can changeData"
        );
        require(_nftes[tokenId].id > 0, "nft  not exist");

        IIgniNFT.Nft storage nft = _nftes[tokenId];
        nft.owner = nftData.owner;
    }

    function setNftFounderTypes(
        uint256 key,
        MintNftPower calldata nftTypeFounder
    ) public onlyGovernance {
        _nftFounderTypes[key] = nftTypeFounder;
    }

    /**
     * @dev add nft mint strategy address
     * can't remove
     */
    function addNftRuleProxy(uint256 nftType, address ruleProxy)
        public
        onlyGovernance
    {
        require(
            _ruleProxys[nftType] == IIgniNFTRuleProxy(address(0)),
            "must null"
        );

        _ruleProxys[nftType] = IIgniNFTRuleProxy(ruleProxy);
        _ruleProxyFlags[ruleProxy] = true;
    }

    function isRulerProxyContract(address proxy)
        external
        view
        override
        returns (bool)
    {
        return _ruleProxyFlags[proxy];
    }

    /*
     * @dev set nft contract address
     */
    function setNftContract(address nft) public onlyGovernance {
        _igniNftToken = IIgniNFT(nft);
    }

    function setCurrentNftId(uint256 id) public onlyGovernance {
        _nftId = id;
    }

    uint256 private unlocked = 1;
    modifier lock() {
        require(unlocked == 1, "NftFactoryV2: LOCKED");
        unlocked = 0;
        _;
        unlocked = 1;
    }

    function getNftTier(uint256 tokenId) external view returns (uint256) {
        IIgniNFT.Nft storage nft = _nftes[tokenId];
        require(nft.id > 0, "nft not exist");
        return nft.tier;
    }

    function getNft(uint256 tokenId)
        external
        view
        override
        returns (IIgniNFT.Nft memory)
    {
        IIgniNFT.Nft storage nft = _nftes[tokenId];
        require(nft.id > 0, "nft not exist");
        return nft;
    }

    function getNftStruct(uint256 tokenId)
        external
        view
        override
        returns (IIgniNFT.Nft memory nft)
    {
        require(_nftes[tokenId].id > 0, "nft  not exist");
        nft = _nftes[tokenId];
    }

    function marketingTransfer(uint256 amount, address payable sendTo)
        external
        onlyGovernance
    {
        sendTo.transfer(amount);
    }

    function getCurrentAjustRate() public view returns (uint256) {
        for (uint256 i = 0; i < _progressiveCost.length; ++i) {
            MintCostProgress memory ruleCost = _progressiveCost[i];
            if (_nftId <= ruleCost.maxTotalNfts) return ruleCost.ajustRate;
        }
        return 0;
    }

    function getCurrentCost() public view returns (uint256) {
        uint256 ajustRate = getCurrentAjustRate();
        require(ajustRate > 0, "set ajust rate");
        return _nftMintPrice.mul(ajustRate).div(_baseRate);
    }

    function mint(
        uint256 ruleId,
        uint256 qty,
        address referral
    ) public payable lock {
        require(qty > 0 && qty < 11, "invalid qty");
        require(_nftId + qty <= _maxGlobalCap, "lifetime cap");
        require(!msg.sender.isContract(), "call to non-contract");
        require(block.timestamp >= _userStartTs, "can't mint yet");

        require(
            _ruleProxys[0] != IIgniNFTRuleProxy(address(0)),
            "init mint proxy"
        );

        uint256 totalCost = getCurrentCost().mul(qty);

        require(msg.value == totalCost, "pay correct amount for NFT");

        uint256 comission = 0;

        if (referral != msg.sender) {
            // Pay referral
            comission = totalCost.mul(_comissionRate).div(_baseRate);
            payable(referral).transfer(comission);
        }

        payable(_fundsWallet).transfer(msg.value.sub(comission));

        for (uint256 i = 0; i < qty; i++) {
            IIgniNFT.Nft memory nft;
            IIgniNFTRuleProxy.MintParams memory params;
            params.user = msg.sender;
            params.ruleId = ruleId;
            _randomNonce++;
            IIgniNFT.Nft memory nftRand = _ruleProxys[0].generate(
                msg.sender,
                ruleId,
                _randomNonce
            );
            nft.tier = nftRand.tier;
            nft.quality = nftRand.quality;
            nft.bonusPowerPct = nftRand.bonusPowerPct;
            nft.power = _nftFounderTypes[nft.tier].power;
            nft.totalPower = nft
                .power
                .mul(nft.bonusPowerPct * 10**16)
                .div(10**18)
                .add(nft.power);

            uint256 nftId = nft.id;
            if (nftId == 0) {
                _nftId++;
                nftId = _nftId;
            }
            nft.id = nftId;
            nft.blockNum = nft.blockNum > 0 ? nft.blockNum : block.number;
            nft.createdTime = nft.createdTime > 0
                ? nft.createdTime
                : block.timestamp;
            nft.owner = nft.owner == address(0x0) ? msg.sender : nft.owner;

            if (referral != msg.sender) nft.referral = referral;

            _nftes[nftId] = nft;
            _igniNftToken.mint(msg.sender, nftId);

            emit NftAdded(
                nft.id,
                nft.tier,
                nft.quality,
                nft.owner,
                nft.power,
                nft.bonusPowerPct,
                nft.totalPower,
                referral
            );
        }
    }

    function onERC721Received(
        address operator,
        address from,
        uint256 tokenId,
        bytes memory data
    ) public returns (bytes4) {
        //only receive the _nft staff
        if (address(this) != operator) {
            //invalid from nft
            return 0;
        }
        //success
        emit NFTReceived(operator, from, tokenId, data);
        return
            bytes4(
                keccak256("onERC721Received(address,address,uint256,bytes)")
            );
    }
}
