// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "./library/LaunchPadValidations.sol";
import "./interface/IIgniNFT.sol";
import "./interface/IUniswapV2Router.sol";
import "./interface/IIgniLaunchPad.sol";
import "@openzeppelin/contracts/interfaces/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

abstract contract BurnableContract {
    // This doesn't have to match the real contract name. Call it what you like.
    function burn(uint256 amount) external virtual returns (bool);
}

/**
 * @notice IgniToken is a development token that we use to learn how to code solidity
 * and what BEP-20 interface requires
 */
contract IgniLaunchPad is
    Ownable,
    ReentrancyGuard,
    IIgniLaunchPad,
    LaunchPadValidations
{
    using SafeMath for uint256;
    uint256 MAX_INT = 2**256 - 1;
    address public _fundsWallet;

    event IdoAdded(
        uint256 idoId,
        Ido idoData,
        uint256 hardCapFounders,
        uint256 foundersEndTime
    );
    event IdoFill(uint256 idoId, uint256 amount, uint256 totalFilled);
    event IdoWithdraw(uint256 idoId);
    event IdoClaimed(uint256 idoId);
    event IdoCancelledStatus(uint256 idoId, bool newStatus);

    constructor() {
        _fundsWallet = msg.sender;
    }

    function setFundsWallet(address fundsWallet) public onlyGovernance {
        _fundsWallet = fundsWallet;
    }

    function emergencyWithdrawGm(uint256 amount, address payable sendTo)
        external
        onlyGovernance
    {
        sendTo.transfer(amount);
    }

    function emergencyTransferGm(
        uint256 idoId,
        uint256 amount,
        address payable sendTo
    ) external onlyGovernance {
        Ido storage currentIdo = currentIdos[idoId];
        IERC20 tokenContract = IERC20(currentIdo.tokenAddress);
        tokenContract.transferFrom(address(this), sendTo, amount);
    }

    function emergencyWithdraw(uint256 idoId)
        external
        nonReentrant
        validWithdrawIdoCancelled(idoId)
        validHasPurchase(idoId)
        validHasWithdraw(idoId)
        validHasClaim(idoId)
        validWithdrawLidAdded(idoId)
    {
        // `Ido storage currentIdo = currentIdos[idoId];
        IdoExtra storage currentIdoExtra = currentIdosExtra[idoId];

        currentIdoExtra.withdrawByWallet[msg.sender] = true;
        payable(msg.sender).transfer(currentIdoExtra.buyByWallet[msg.sender]);

        emit IdoWithdraw(idoId);
    }

    function canClaimIdo(uint256 idoId)
        public
        view
        validIdoIsNotCancelled(idoId)
        validSaleEndTimePass(idoId)
        validHasPurchase(idoId)
        validHasWithdraw(idoId)
        validHasClaim(idoId)
        validSoftCapFilled(idoId)
        validHasLiqAdded(idoId)
        returns (bool)
    {
        return true;
    }

    function claimIdo(uint256 idoId)
        external
        nonReentrant
        validIdoIsNotCancelled(idoId)
        validSaleEndTimePass(idoId)
        validHasPurchase(idoId)
        validHasWithdraw(idoId)
        validHasClaim(idoId)
        validSoftCapFilled(idoId)
        validHasLiqAdded(idoId)
    {
        Ido storage currentIdo = currentIdos[idoId];
        IdoExtra storage currentIdoExtra = currentIdosExtra[idoId];

        currentIdoExtra.claimByWallet[msg.sender] = true;
        uint256 tksAmount = currentIdoExtra
            .buyByWallet[msg.sender]
            .mul(currentIdo.tokenRatePresale)
            .div(10**18);
        IERC20 tokenContract = IERC20(currentIdo.tokenAddress);
        tokenContract.transferFrom(address(this), msg.sender, tksAmount);

        emit IdoClaimed(idoId);
    }

    // In some liquidity emergency the owner can release the difference
    function setLiqAdded(uint256 idoId, bool value) external onlyGovernance {
        IdoExtra storage currentIdoExtra = currentIdosExtra[idoId];
        currentIdoExtra.lqAdded = value;
    }

    // Calculates the tokens that need to be returned or burned from the ICO
    function _getUnsoldAmountTokens(uint256 idoId)
        public
        view
        returns (uint256)
    {
        Ido storage currentIdo = currentIdos[idoId];
        uint256 totalTks = _getAmountTokensIdos(currentIdo);
        IdoExtra storage currentIdoExtra = currentIdosExtra[idoId];
        uint256 diffUnsold = currentIdo.hardCap.sub(
            currentIdoExtra.amountFilled
        );
        uint256 percentUnfilled = diffUnsold
            .mul(10**18)
            .div(currentIdo.hardCap)
            .div(10**16);
        return percentUnfilled.mul(totalTks).div(10**2);
    }

    function burnOrClaimUnsoldDevTokens(uint256 idoId, bool useBurnCall)
        external
        nonReentrant
        validOnlyIdoOwner(idoId)
        validIdoIsNotCancelled(idoId)
        validSoftCapFilled(idoId)
        validSaleEndTimePass(idoId)
        validHasLiqAdded(idoId)
    {
        Ido storage currentIdo = currentIdos[idoId];
        IdoExtra storage currentIdoExtra = currentIdosExtra[idoId];
        require(
            currentIdoExtra.diffSentOwner == false,
            "Diff IDO already sent"
        );
        currentIdoExtra.diffSentOwner = true;
        uint256 valueToLq = currentIdoExtra
            .amountFilled
            .mul(currentIdo.percToLq * 10**16)
            .div(10**18);
        uint256 diffLiqToOwner = currentIdoExtra.amountFilled.sub(valueToLq);
        // Send the difference that was not going to liquidity to IDO's owner
        payable(currentIdo.owner).transfer(diffLiqToOwner);
        // Return or burning of non-traded values
        IERC20 tokenContract = IERC20(currentIdo.tokenAddress);
        uint256 unsoldAmount = _getUnsoldAmountTokens(idoId);

        if (unsoldAmount == 0) return;

        if (currentIdoExtra.refundNotSoldToken) {
            address destTokens = currentIdo.owner;
            tokenContract.transferFrom(address(this), destTokens, unsoldAmount);
        } else {
            if (useBurnCall) {
                BurnableContract(currentIdo.tokenAddress).burn(unsoldAmount);
            } else {
                tokenContract.transferFrom(
                    address(this),
                    0x000000000000000000000000000000000000dEaD,
                    unsoldAmount
                );
            }
        }
    }

    function addLiquidity(uint256 idoId)
        external
        nonReentrant
        validOnlyIdoOwner(idoId)
        validHasNotLiqAdded(idoId)
        validIdoIsNotCancelled(idoId)
    {
        Ido storage currentIdo = currentIdos[idoId];
        IdoExtra storage currentIdoExtra = currentIdosExtra[idoId];

        // only  successful ido
        require(
            currentIdoExtra.amountFilled >= currentIdo.hardCap ||
                (currentIdoExtra.amountFilled >= currentIdo.softCap &&
                    block.timestamp >= currentIdo.saleEndTime),
            "only successful IDO"
        );

        address routerAddress = _routerList[currentIdoExtra.routerDeploy];
        require(routerAddress != address(0), "Set the router address");

        //  // approve token transfer to cover all possible scenarios
        // _approve(address(this), address(uniswapV2Router), tokenAmount);
        IUniswapV2Router _uniswapV2Router = IUniswapV2Router(routerAddress); //BUB: 0x10 address is pancakeSwapV2 mainnet router //0x9Ac64Cc6e4415144C455BD8E4837Fea55603e5c3

        uint256 percLq = currentIdo.percToLq * 10**16;
        uint256 valueToLq = currentIdoExtra.amountFilled.mul(percLq).div(
            10**18
        );

        uint256 valueTokens = valueToLq.mul(currentIdo.tokenRateListing).div(
            10**18
        ); // calculates total tokens for liquidity

        {
            // avoid too deep error
            IERC20 tokenContract = IERC20(currentIdo.tokenAddress);
            tokenContract.approve(routerAddress, MAX_INT);
        }

        // add the liquidity
        _uniswapV2Router.addLiquidityETH{value: valueToLq}(
            currentIdo.tokenAddress,
            valueTokens,
            0, // slippage is unavoidable
            0, // slippage is unavoidable
            currentIdo.owner,
            block.timestamp
        );

        currentIdoExtra.lqAdded = true;
    }

    function addItemsToWhiteList(address[] memory addresses, uint256 idoId)
        external
        nonReentrant
        validOnlyIdoOwner(idoId)
    {
        IdoExtra storage currentIdoExtra = currentIdosExtra[idoId];
        for (uint256 i = 0; i < addresses.length; i++) {
            currentIdoExtra.whiteList.push(addresses[i]);
        }
    }

    function createIdo(Ido memory idoData)
        public
        payable
        nonReentrant
        validCreateCorrectAmount
        validCreateBalanceAmount(idoData)
        validCreateLiquidity(idoData)
    {
        _idoId++;
        idoData.owner = msg.sender;

        uint256 tksAmount = _getAmountTokensIdos(idoData);
        IERC20 tokenContract = IERC20(idoData.tokenAddress);

        tokenContract.transferFrom(msg.sender, address(this), tksAmount);
        tokenContract.approve(address(this), MAX_INT);

        require(
            tokenContract.balanceOf(address(this)) >= tksAmount,
            "disable fee for IDO contract"
        );

        currentIdos[_idoId] = idoData;
        IdoExtra storage currentIdoExtra = currentIdosExtra[_idoId];

        currentIdoExtra.foundersEndTime =
            idoData.saleStartTime +
            (_minRoundFounders * 1 minutes);

        currentIdoExtra.hardCapFounders = idoData
            .hardCap
            .mul(_percCapForFounder)
            .div(10**18);

        payable(_fundsWallet).transfer(msg.value);

        emit IdoAdded(
            _idoId,
            idoData,
            currentIdoExtra.hardCapFounders,
            currentIdoExtra.foundersEndTime
        );
    }

    function contribute(uint256 idoId)
        public
        payable
        nonReentrant
        validSaleClosed(idoId)
        validCanContrib(idoId)
        validBuyMaxAllowed(idoId)
        validBuyMinAllowed(idoId)
        validMaxHardCap(idoId)
        validMaxHardCapOnFounders(idoId)
        validIdoIsNotCancelled(idoId)
        validHasNotLiqAdded(idoId)
    {
        IdoExtra storage currentIdoExtra = currentIdosExtra[idoId];

        currentIdoExtra.buyByWallet[msg.sender] += msg.value;
        currentIdoExtra.amountFilled += msg.value;

        emit IdoFill(idoId, msg.value, currentIdoExtra.amountFilled);
    }

    function cancelIdo(uint256 idoId)
        external
        nonReentrant
        validOnlyIdoOwner(idoId)
        validHasNotLiqAdded(idoId)
        validIdoIsNotCancelled(idoId)
    {
        currentIdosExtra[idoId].isCancelled = true;

        emit IdoCancelledStatus(idoId, currentIdosExtra[idoId].isCancelled);
        /*
        Ido storage currentIdo = currentIdos[idoId];
        IERC20 tokenContract = IERC20(currentIdo.tokenAddress);
        tokenContract.transferFrom(address(this), currentIdo.owner, tokenContract.balanceOf(address(this)));
        */
    }
}
