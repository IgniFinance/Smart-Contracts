// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "./library/Governance.sol";
import "./library/NftUtil.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";

contract IgniNFT is ERC721, ERC721URIStorage, ERC721Enumerable, Governance {
    // for minters
    mapping(address => bool) public _minters;

    constructor() ERC721("Igni Finance NFT", "IGNI-N") {}

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId
    ) internal override(ERC721, ERC721Enumerable) {
        super._beforeTokenTransfer(from, to, tokenId);
    }

    function _burn(uint256 tokenId)
        internal
        override(ERC721, ERC721URIStorage)
    {
        super._burn(tokenId);
    }

    function tokenURI(uint256 tokenId)
        public
        view
        override(ERC721, ERC721URIStorage)
        returns (string memory)
    {
        return super.tokenURI(tokenId);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721, ERC721Enumerable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    function _baseURI() internal pure override returns (string memory) {
        return "https://igni.finance/investing/nft/";
    }

    /**
     * @dev Function to mint tokens.
     * @param to The address that will receive the minted token.
     * @param tokenId The token id to mint.
     * @return A boolean that indicates if the operation was successful.
     */
    function mint(address to, uint256 tokenId) external returns (bool) {
        require(_minters[msg.sender], "!minter");
        require(tokenId <= 9999, "token cap");
        _mint(to, tokenId);
        _setTokenURI(tokenId, NftUtil.uintToString(tokenId));
        return true;
    }

    /**
     * @dev Function to safely mint tokens.
     * @param to The address that will receive the minted token.
     * @param tokenId The token id to mint.
     * @return A boolean that indicates if the operation was successful.
     */
    function safeMint(address to, uint256 tokenId) public returns (bool) {
        require(_minters[msg.sender], "!minter");
        require(tokenId <= 9999, "token cap");
        _safeMint(to, tokenId);
        _setTokenURI(tokenId, NftUtil.uintToString(tokenId));
        return true;
    }

    /**
     * @dev Function to safely mint tokens.
     * @param to The address that will receive the minted token.
     * @param tokenId The token id to mint.
     * @param _data bytes data to send along with a safe transfer check.
     * @return A boolean that indicates if the operation was successful.
     */
    function safeMint(
        address to,
        uint256 tokenId,
        bytes memory _data
    ) public returns (bool) {
        require(_minters[msg.sender], "!minter");
        require(tokenId <= 9999, "token cap");
        _safeMint(to, tokenId, _data);
        _setTokenURI(tokenId, NftUtil.uintToString(tokenId));
        return true;
    }

    function addMinter(address minter) public onlyGovernance {
        _minters[minter] = true;
    }

    function removeMinter(address minter) public onlyGovernance {
        _minters[minter] = false;
    }

    /**
     * @dev Burns a specific ERC721 token.
     * @param tokenId uint256 id of the ERC721 token to be burned.
     */
    function burn(uint256 tokenId) external {
        //solhint-disable-next-line max-line-length
        require(_minters[msg.sender], "!minter");
        require(
            _isApprovedOrOwner(_msgSender(), tokenId),
            "caller is not owner nor approved"
        );
        _burn(tokenId);
    }

    /**
     * @dev Gets the list of token IDs of the requested owner.
     * @param owner address owning the tokens
     * @return uint256[] List of token IDs owned by the requested address
     */
    function tokensOfOwner(address owner)
        external
        view
        returns (uint256[] memory)
    {
        uint256 balance = balanceOf(owner);
        uint256[] memory tokens = new uint256[](balance);

        for (uint256 i = 0; i < balance; i++) {
            tokens[i] = tokenOfOwnerByIndex(owner, i);
        }

        return tokens;
    }
}
