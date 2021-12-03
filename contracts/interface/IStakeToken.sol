// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

interface IStakeToken {
    function stake(uint256 amount, address account) external;
}
