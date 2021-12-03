// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "./library/NFTManagerMarketplace.sol";
import "./library/NFTManagerRewards.sol";
import "./interface/IIgniNFTManager.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

contract IgniNFTManager is
    Governance,
    NFTManagerMarketplace,
    NFTManagerRewards
{
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    constructor(
        address igniNftToken,
        address nftFactory,
        address _stakingToken,
        address _stakeTokenManagerAdd
    ) {
        stakingToken = IERC20(_stakingToken); //Token BEP20 staked
        _nftToken = IIgniNFT(igniNftToken);
        _nftFactory = IIgniNFTFactory(nftFactory);
        _stakeTokenManager = IStakeToken(_stakeTokenManagerAdd);
    }

    /* Fee collection for any other token */
    function seize(IERC20 token, uint256 amount) external {
        require(token != stakingToken, "reward");
        token.transfer(_governance, amount);
    }

    /* Fee collection for any other token */
    function seizeErc721(IERC721 token, uint256 tokenId) external {
        require(token != _nftToken, "nft stake");
        token.safeTransferFrom(address(this), _governance, tokenId);
    }
}
