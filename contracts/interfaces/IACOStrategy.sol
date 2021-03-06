// SPDX-License-Identifier: None
pragma solidity 0.8.4;

interface IACOStrategy {
    
    struct OptionQuote {
        bool isSellingQuote;
        address underlying;
        address strikeAsset;
        bool isCallOption;
        uint256 strikePrice; 
        uint256 expiryTime;
        uint256 baseVolatility;
        uint256 collateralOrderAmount;
        uint256 collateralAvailable;
        uint256 collateralTotalDeposited;
        uint256 strikeAssetEarnedSelling;
        uint256 strikeAssetSpentBuying;
        uint256 amountPurchased;
        uint256 amountSold;
    }
    
    struct CheckExercise {
        address underlying;
        address strikeAsset;
        bool isCallOption;
        uint256 strikePrice; 
        uint256 expiryTime;
        uint256 collateralAmount;
        uint256 collateralAvailable;
        uint256 amountPurchased;
        uint256 amountSold;
    }
    
    function quote(OptionQuote calldata quoteData) external view returns(uint256 optionPrice, uint256 underlyingPrice, uint256 volatility);
    function getUnderlyingPrice(address underlying, address strikeAsset) external view returns(uint256 underlyingPrice);
    function getAcceptableUnderlyingPriceToSwapAssets(address underlying, address strikeAsset, bool isBuying) external view returns(uint256 acceptablePrice);
    function checkExercise(CheckExercise calldata exerciseData) external view returns(bool canExercise, uint256 minIntrinsicValue);
}