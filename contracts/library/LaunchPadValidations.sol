// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "./LaunchPadBaseData.sol";
import "@openzeppelin/contracts/interfaces/IERC20.sol";

contract LaunchPadValidations is LaunchPadBaseData { 
    using SafeMath for uint256;

    /* ##############  BEGIN VALIDATIONS USED IN IDO CREATION  ################## */
    modifier validCreateCorrectAmount() {
        require(msg.value == _idoCost, "Pay correct amount for IDO");
        _;
    }
    modifier validCreateBalanceAmount(Ido memory idoData) {
        uint256 tksAmount = _getAmountTokensIdos(idoData);
        IERC20 tokenContract = IERC20(idoData.tokenAddress);
        require(
            tokenContract.balanceOf(msg.sender) >= tksAmount,
            "You need the total tokens to start the ICO in your wallet"
        );
        _;
    }
    modifier validCreateLiquidity(Ido memory idoData) {
        require(
            idoData.percToLq >= 50,
            "The liquidity percentage must be equal or higher than 50%."
        );
        require(
            idoData.percToLq <= 100,
            "The liquidity percentage must be equal to or less than 100%."
        );
        _;
    }
    /* ############## END VALIDATIONS USED IN IDO CREATION  ################## */

    /* ############## BEGIN VALIDATIONS USED ON CONTRIBUTE ################## */
    modifier validCanContrib(uint256 idoId) {
        require(
            _canContribute(idoId, msg.sender),
            "The sale is not started yet for this IDO"
        );
        _;
    }
    modifier validSaleClosed(uint256 idoId) {
        require(
            block.timestamp <= currentIdo(idoId).saleEndTime,
            "The sale is closed for this IDO"
        );
        _;
    }
    modifier validBuyMaxAllowed(uint256 idoId) {
        require(
            currentIdoExtra(idoId).buyByWallet[msg.sender] + msg.value <=
                currentIdo(idoId).maxBuy,
            "You cannot buy more than the maximum allowed"
        ); // solhint-disable;
        _;
    }
    modifier validBuyMinAllowed(uint256 idoId) {
        require(
            msg.value >= currentIdo(idoId).minBuy,
            "You cannot buy less than the minimum allowed"
        ); // solhint-disable;
        _;
    }
    modifier validMaxHardCap(uint256 idoId) {
        if (block.timestamp >= currentIdoExtra(idoId).foundersEndTime) {
            require(
                currentIdoExtra(idoId).amountFilled + msg.value <=
                    currentIdo(idoId).hardCap,
                "Your purchase exceeds the hardCap of this IDO"
            );
        }
        _;
    }
    modifier validMaxHardCapOnFounders(uint256 idoId) {
        if (block.timestamp < currentIdoExtra(idoId).foundersEndTime) {
            require(
                currentIdoExtra(idoId).amountFilled + msg.value <=
                    currentIdoExtra(idoId).hardCapFounders,
                "Your purchase exceeds the hardCap of this IDO on founders round"
            );
        }
        _;
    }
    /* ############## END VALIDATIONS USED ON CONTRIBUTE ################## */

    /* ############## BEGIN OF SHARED VALIDATIONS BETWEEN: CLAIM, WITHDRAW ################## */
    modifier validIdoIsNotCancelled(uint256 idoId) {
        require(
            !currentIdoExtra(idoId).isCancelled,
            "This IDO has been cancelled, you cannot use this function"
        );
        _;
    }
    modifier validHasPurchase(uint256 idoId) {
        require(
            currentIdoExtra(idoId).buyByWallet[msg.sender] > 0,
            "You have no purchase on this IDO"
        );
        _;
    }
    modifier validHasWithdraw(uint256 idoId) {
        require(
            !currentIdoExtra(idoId).withdrawByWallet[msg.sender],
            "You have already withdrawn this token"
        );
        _;
    }
    modifier validHasClaim(uint256 idoId) {
        require(
            !currentIdoExtra(idoId).claimByWallet[msg.sender],
            "You have already claimed this token"
        );
        _;
    }
    modifier validSoftCapFilled(uint256 idoId) {
        require(
            currentIdoExtra(idoId).amountFilled >= currentIdo(idoId).softCap,
            "This IDO has not reached the minimum softcap value to use this function"
        );
        _;
    }
    modifier validHasLiqAdded(uint256 idoId) {
        require(
            currentIdoExtra(idoId).lqAdded,
            "This IDO need liquidity before use this function"
        );
        _;
    }
    modifier validHasNotLiqAdded(uint256 idoId) {
        require(
            !currentIdoExtra(idoId).lqAdded,
            "This IDO cant has liquidity before use this function"
        );
        _;
    }
    modifier validSaleEndTimePass(uint256 idoId) {
        require(
            block.timestamp >= currentIdo(idoId).saleEndTime,
            "You need to wait IDO endtime to use this function"
        );
        _;
    }
    modifier validWithdrawIdoCancelled(uint256 idoId) {
        require(
            (currentIdoExtra(idoId).amountFilled < currentIdo(idoId).softCap && // Only if you did not fill softcap
                block.timestamp >= currentIdo(idoId).saleEndTime) ||
                currentIdoExtra(idoId).isCancelled,
            "You need to wait presale endtime to withdraw or owner cancel"
        );
        _;
    }
    modifier validWithdrawLidAdded(uint256 idoId) {
        require(
            !currentIdoExtra(idoId).lqAdded,
            "You cannot withdraw from an ICO that has been finalized"
        );
        _;
    }

    /* ############## END OF SHARED VALIDATIONS BETWEEN: CLAIM, WITHDRAW ################## */

    /** SHARED */

    modifier validOnlyIdoOwner(uint256 idoId) {
        require(
            currentIdo(idoId).owner == msg.sender || msg.sender == _governance, // In some extreme case Igni may need to manage the IDO contract, such as cancellation of some suspect IDO
            "Only owner can use this function"
        );
        _;
    }
}
