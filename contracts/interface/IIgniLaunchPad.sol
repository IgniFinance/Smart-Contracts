// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

interface IIgniLaunchPad {
  
    struct Ido {
        uint256 saleStartTime; // start sale time
        uint256 saleEndTime; // end sale time
        address owner;
        uint256 softCap;
        uint256 hardCap;
        uint256 minBuy;
        uint256 maxBuy;
        uint256 tokenRatePresale; // How many tokens per BNB in presale
        uint256 tokenRateListing; // How many tokens per BNB or BUSD in listing
        uint256 percToLq; // Percentage for liquidity
        bool useWhiteList;
        uint256 whiteListTime; // Time in seconds where only wl can buy
        address tokenAddress; // Token where the IDO will be distributed
    }

    // Secure variables, you can never change them without going through the rules
    struct IdoExtra {
        address[] whiteList;
        mapping(address => uint256) buyByWallet;
        mapping(address => bool) claimByWallet;
        mapping(address => bool) withdrawByWallet;
        uint256 foundersEndTime;
        uint256 hardCapFounders;
        bool isCancelled;
        bool kyc;
        uint256 amountFilled;
        bool useBusd;
        bool refundNotSoldToken; // Default is burning, devolution needs to be set
        bool lqAdded;
        bool diffSentOwner;
        uint256 routerDeploy;
    }
}
