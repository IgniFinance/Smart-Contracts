// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

pragma experimental ABIEncoderV2;

import "../interface/IIgniNFT.sol";
import "../interface/IIgniNFTChangeble.sol";

interface IIgniNFTFactory {
    function getNft(uint256 tokenId)
        external
        view
        returns (IIgniNFT.Nft memory);

    function getNftTier(uint256 tokenId) external view returns (uint256);

    function getNftStruct(uint256 tokenId)
        external
        view
        returns (IIgniNFT.Nft memory nft);

    function isRulerProxyContract(address proxy) external view returns (bool);

    function changeNftData(
        uint256 tokenId,
        IIgniNFTChangeble.NFtDataChangeble calldata nftData
    ) external;
}
