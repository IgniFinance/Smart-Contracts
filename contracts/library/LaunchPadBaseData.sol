// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "../interface/IIgniLaunchPad.sol";
import "../interface/IIgniNFT.sol";
import "../interface/IIgniNFTFactory.sol";
import "../library/Governance.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

contract LaunchPadBaseData is IIgniLaunchPad, Governance {
    using SafeMath for uint256;

    mapping(uint256 => Ido) public currentIdos;
    mapping(uint256 => IdoExtra) public currentIdosExtra;
    mapping(uint256 => address) public _routerList;

    uint256 public _idoId = 0;
    uint256 public _minRoundFounders = 5; //  Time in minutes for round founders
    uint256 public _minPerTier = 1; // Min per tier
    uint256 public _percCapForFounder = 50 * 10**16; // Cap for founders round
    uint256 public _idoCost = 0;

    IIgniNFT public _igniNftToken;
    IIgniNFTFactory public _igniNftFactory;

    function _getBestTier(address wallet) public view returns (uint256) {
        uint256[] memory tokens = _igniNftToken.tokensOfOwner(wallet);
        uint256 tier;
        uint256 bestTier = 0;

        for (uint256 i = 0; i < tokens.length; i++) {
            tier = _igniNftFactory.getNftTier(tokens[i]);

            if (tier < bestTier || bestTier == 0) bestTier = tier;
        }
        return bestTier;
    }

    function currentIdo(uint256 idoId) internal view returns (Ido storage) {
        return currentIdos[idoId];
    }

    function currentIdoExtra(uint256 idoId)
        internal
        view
        returns (IdoExtra storage)
    {
        return currentIdosExtra[idoId];
    }

    function getWalletExtraInfo(uint256 idoId, address wallet)
        public
        view
        returns (
            uint256 buyByWallet,
            bool claimByWallet,
            bool withdrawByWallet
        )
    {
        buyByWallet = currentIdosExtra[idoId].buyByWallet[wallet];
        claimByWallet = currentIdosExtra[idoId].claimByWallet[wallet];
        withdrawByWallet = currentIdosExtra[idoId].withdrawByWallet[wallet];
    }

    /*
     * @dev set gego contract address
     */
    function setNftTokenContract(address addressTk) public onlyGovernance {
        _igniNftToken = IIgniNFT(addressTk);
    }

    function setMinRoundFounders(uint256 minRoundFounders)
        public
        onlyGovernance
    {
        _minRoundFounders = minRoundFounders;
    }

    function setPercCapForFounder(uint256 percCapForFounder)
        public
        onlyGovernance
    {
        _percCapForFounder = percCapForFounder;
    }

    function setMinPerTier(uint256 minPerTier) public onlyGovernance {
        _minPerTier = minPerTier;
    }

    function setNftFactoryContract(address addressFac) public onlyGovernance {
        _igniNftFactory = IIgniNFTFactory(addressFac);
    }

    function addRouterList(uint256 key, address routerAddress)
        public
        onlyGovernance
    {
        _routerList[key] = routerAddress;
    }

    function setIdoCost(uint256 cost) public onlyGovernance {
        _idoCost = cost;
    }

    function _getAmountTokensIdos(Ido memory idoData)
        public
        pure
        returns (uint256)
    {
        uint256 totalHardcapTkn = idoData.hardCap.mul(idoData.tokenRatePresale);
        uint256 percLq = idoData.percToLq * 10**16;
        uint256 capLiq = idoData.hardCap.mul(percLq).div(10**18);
        uint256 totalLqTkn = capLiq.mul(idoData.tokenRateListing);

        return (totalHardcapTkn + totalLqTkn).div(10**18);
    }

    function _canContribute(uint256 idoId, address wallet)
        public
        view
        returns (bool)
    {
        if (block.timestamp > currentIdos[idoId].saleEndTime) return false;

        uint256 tier = _getBestTier(wallet);

        uint256 baseMulTier = tier > 0 ? 6 - tier : 1; // Invert tier 1 to 5, 2 to 4 if has NFT

        uint256 offset = (_minRoundFounders * 1 minutes) -
            (baseMulTier * (_minPerTier * 1 minutes));
        uint256 walletFoundersStart = currentIdos[idoId].saleStartTime + offset;

        //check caps
        if (
            block.timestamp >= currentIdosExtra[idoId].foundersEndTime &&
            currentIdosExtra[idoId].amountFilled >= currentIdos[idoId].hardCap
        ) return false;

        // Ido finished / liq added / cancelled
        if (
            currentIdosExtra[idoId].lqAdded ||
            currentIdosExtra[idoId].isCancelled
        ) return false;

        // check caps
        if (
            block.timestamp < currentIdosExtra[idoId].foundersEndTime &&
            currentIdosExtra[idoId].amountFilled >=
            currentIdosExtra[idoId].hardCapFounders
        ) return false;

        // max buy by wallet
        if (
            currentIdosExtra[idoId].buyByWallet[wallet] >=
            currentIdos[idoId].maxBuy
        ) return false;

        // Members who have NFT
        if (
            tier > 0 &&
            block.timestamp >= walletFoundersStart &&
            block.timestamp <= currentIdosExtra[idoId].foundersEndTime
        ) return true;

        if (currentIdos[idoId].useWhiteList) {
            uint256 wlEnd = currentIdosExtra[idoId].foundersEndTime +
                currentIdos[idoId].whiteListTime;
            // Already released to the public after whitelist
            if (block.timestamp >= wlEnd) return true;
            // After the founders' round, and is on the whitelist
            if (
                block.timestamp >= currentIdosExtra[idoId].foundersEndTime &&
                _isOnWhiteList(idoId)
            ) return true;
        } else {
            // If whitelist is disabled, sales released after nft founders round
            if (block.timestamp >= currentIdosExtra[idoId].foundersEndTime)
                return true;
        }

        return false;
    }

    function _isOnWhiteList(uint256 idoId) public view returns (bool) {
        for (uint256 i = 0; i < currentIdosExtra[idoId].whiteList.length; i++) {
            address _addressArr = currentIdosExtra[idoId].whiteList[i];
            if (_addressArr == msg.sender) {
                return true;
            }
        }
        return false;
    }
}
