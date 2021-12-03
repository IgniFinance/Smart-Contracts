// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "./NFTManagerBase.sol";
import "../interface/IIgniNFTChangeble.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract NFTManagerMarketplace is NFTManagerBase { 
    using SafeERC20 for IERC20;
    using SafeMath for uint256; 

    uint256 feeMarket = 500; // 5% in basis points
    address payable public marketHotWallet; 

    event NFTAddedMarketplace(uint256 id, uint256 salePrice);
    event NFTSoldMarketplace(uint256 id, uint256 salePrice, address newOwner);
    event NFTExternalOwnerChanged(uint256 id, address newOwner);
    event NFTRemovedMarketplace(uint256 id);


    function setHotWallet(address payable _value) public onlyGovernance {
        marketHotWallet = _value; 
    }

    function setMarketFeeDiv(uint256 _value) public onlyGovernance {
        feeMarket = _value; // 20 for 5%
    }


    // switch between set for sale and set not for sale
    function toggleForSale(
        uint256 nftId,
        bool isForSale,
        uint256 salePrice
    ) public onlyExistsAndNftOwner(nftId) {
        if (isForSale) require(!_nftOnMarket[nftId], "already for sale");
        else require(_nftOnMarket[nftId], "not on market");

        // Removing from the market
        if (!isForSale) {
            _nftOnMarket[nftId] = false;
            if (!_nftOnStake[nftId])
                _nftToken.safeTransferFrom(address(this), msg.sender, nftId);

            emit NFTRemovedMarketplace(nftId);
        } else {
            require(salePrice > 0, "price need to be > 0");
            _nftMarketPrice[nftId] = salePrice;
            _nftOnMarket[nftId] = true;
            if (!_nftOnStake[nftId])
                _nftToken.safeTransferFrom(msg.sender, address(this), nftId);

            emit NFTAddedMarketplace(nftId, salePrice);
        }
    }


  


    function dustTransfer(uint256 amount, address payable sendTo)
        external
        onlyGovernance
    {
        sendTo.transfer(amount);
    }


     
    // buy a token by passing in the token's id
    function buyNft(uint256 nftId) public payable {
        require(_nftOnMarket[nftId], "not on market");
        require(_nftMarketPrice[nftId] > 0, "price need to be > 0");
        require(
            msg.value == _nftMarketPrice[nftId],
            "send correct amount to buy"
        );

        IIgniNFT.Nft memory nft = _nftFactory.getNft(nftId);
        // Transfers funds to the NFT owner
        uint256 amountInFee = takeFeeETH(msg.value);
        payable(nft.owner).transfer(msg.value.sub(amountInFee));
      
        // Transfers NFT of the contract to the buyer
        _nftToken.safeTransferFrom(address(this), msg.sender, nftId);

        if (_nftOnStake[nftId]) {
            updateRewardHandle(nft.owner);
            unstakeInternal(nftId, nft.owner);
        }

        IIgniNFTChangeble.NFtDataChangeble memory nftData;
        nftData.owner = msg.sender; // Change the owner in the internal management, you need to change it in erc721 as well
        _nftFactory.changeNftData(nftId, nftData);
        _nftMarketPrice[nftId] = 0;
        _nftOnMarket[nftId] = false;

        emit NFTSoldMarketplace(nftId, _nftMarketPrice[nftId], msg.sender);
    }


      function takeFeeETH(uint256 amountIn)
        private
        returns (uint256 amountInFee)
    {
        amountInFee = amountIn.mul(feeMarket).div(10000);
        marketHotWallet.transfer(amountInFee);
    }


    // In case the NFT is marketed outside our marplace, the new owner needs to pull the authorship of the NFT in order to use resources with stake and our marketplace
    function fixExternalSaleOwner(uint256 nftId)
        public
        onlyExistsAndNftOwner(nftId)
    {
        address currOwner = _nftToken.ownerOf(nftId);
        IIgniNFT.Nft memory nft = _nftFactory.getNft(nftId);
        require(nft.id > 0, "nft not exists");
        require(currOwner == msg.sender, "not nft owner");

        IIgniNFTChangeble.NFtDataChangeble memory nftData;
        nftData.owner = msg.sender; // Change the owner in the internal management, you need to change it in erc721 as well
        _nftFactory.changeNftData(nftId, nftData);
        emit NFTExternalOwnerChanged(nftId, msg.sender);
    }


}
