// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;
pragma experimental ABIEncoderV2;

import "./interface/IIgniNFTFactory.sol";
import "./interface/IIgniNFTRuleProxy.sol";
import "./library/Governance.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/interfaces/IERC20.sol";

contract IgniNFTMintProxy is Governance, IIgniNFTRuleProxy {
    using Address for address;
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    uint256 public _qualityBase = 1000;

    struct RuleData {
        uint256 tier1min;
        uint256 tier2min;
        uint256 tier3min;
        uint256 tier4min;
        uint256 tier5min;
        bool disableRule;
    }

    IIgniNFTFactory public _factory = IIgniNFTFactory(address(0));
    mapping(uint256 => RuleData) public _ruleData;

    constructor() {}

    function setQualityBase(uint256 val) public onlyGovernance {
        _qualityBase = val;
    }

    function setRuleData(RuleData calldata ruleData, uint256 key)
        public
        onlyGovernance
    {
        _ruleData[key] = ruleData;
    }

    function setFactory(address factory) public onlyGovernance {
        _factory = IIgniNFTFactory(factory);
    }

    function generate(
        address user,
        uint256 ruleId,
        uint256 randomNonce
    ) external view override returns (IIgniNFT.Nft memory igniNft) {
        require(
            _factory == IIgniNFTFactory(msg.sender),
            "invalid factory caller"
        );
        require(!_ruleData[ruleId].disableRule, "rule is disabled");

        uint256 seed = computerSeed(user, randomNonce);

        igniNft.quality = seed % _qualityBase;
        igniNft.tier = getTier(igniNft.quality, _ruleData[ruleId]);

        uint256 baseBonus = 0;
        uint256 baseMulTier = 6 - igniNft.tier; // Invert tier 1 to 5, 2 to 4
        if (baseMulTier > 1) {
            baseBonus = baseMulTier.sub(1).mul(20);
            baseBonus = baseBonus.sub(baseBonus.div(2) % seed); // Removes up to 50% of the base bonus
        }
        igniNft.bonusPowerPct = baseBonus.add(seed % 20);

        randomNonce++;
    }

    function getTier(uint256 quality, RuleData memory ruleData)
        public
        pure
        returns (uint256)
    {
        if (quality <= ruleData.tier1min) {
            return 1;
        } else if (quality <= ruleData.tier2min) {
            return 2;
        } else if (quality <= ruleData.tier3min) {
            return 3;
        } else if (quality <= ruleData.tier4min) {
            return 4;
        } else if (quality <= ruleData.tier5min) {
            return 5;
        }

        return 5;
    }

    function computerSeed(address user, uint256 randomNonce) internal view returns (uint256) {
        uint256 seed = uint256(
            keccak256(
                abi.encodePacked(
                    (block.timestamp)
                        .add(block.difficulty)
                        .add(
                            (
                                uint256(
                                    keccak256(abi.encodePacked(block.coinbase))
                                )
                            ) / (block.timestamp)
                        )
                        .add(block.gaslimit)
                        .add(
                            (uint256(keccak256(abi.encodePacked(user)))) /
                                (block.timestamp)
                        )
                        .add(block.number).add(randomNonce)
                )
            )
        );
        return seed;
    }
}
