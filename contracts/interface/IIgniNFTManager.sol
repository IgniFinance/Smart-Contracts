// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

pragma experimental ABIEncoderV2;

import "../interface/IIgniNFT.sol";
import "../interface/IIgniNFTChangeble.sol";

interface IIgniNFTManager {
    function updateRewardHandle(address account) external;
}
