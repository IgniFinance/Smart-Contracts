// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

interface IIgniNFT is IERC721 {
    struct Nft {
        uint256 id;
        uint256 tier;
        uint256 quality;
        address owner;
        uint256 createdTime;
        uint256 blockNum;
        uint256 power; // Used to determine current stake power
        uint256 bonusPowerPct;
        uint256 totalPower;
        bool isForSale;
        uint256 salePrice;
        address referral;
    }

    function mint(address to, uint256 tokenId) external returns (bool);

    function burn(uint256 tokenId) external;

    function tokensOfOwner(address owner)
        external
        view
        returns (uint256[] memory);
}
