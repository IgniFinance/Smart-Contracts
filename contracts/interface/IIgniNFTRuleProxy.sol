// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

pragma experimental ABIEncoderV2;

import "./IIgniNFT.sol";

interface IIgniNFTRuleProxy {
    struct Cost721Asset {
        uint256 costErc721Id1;
        uint256 costErc721Id2;
        uint256 costErc721Id3;
        address costErc721Origin;
    }

    struct MintParams {
        address user;
        uint256 ruleId;
    }

    function generate(
        address user,
        uint256 ruleId,
        uint256 randomNonce
    ) external view returns (IIgniNFT.Nft memory nft);
}
