// SPDX-License-Identifier: None
pragma solidity 0.8.4;

import '../../util/Ownable.sol';
import '../../libs/Address.sol';
import '../../libs/SafeMath.sol';
import '../../libs/ACOAssetHelper.sol';
import '../../libs/BlackScholes.sol';
import '../../interfaces/IACOPoolStrategy.sol';

contract ACOPoolStrategy is Ownable, IACOPoolStrategy {
    using Address for address;
    using SafeMath for uint256;

    event SetOrderSizeFactors(uint256 oldOrderSizeMultiplierFactor, uint256 oldOrderSizeDividerFactor, uint256 oldOrderSizeExponentialFactor, uint256 newOrderSizeMultiplierFactor, uint256 newOrderSizeDividerFactor, uint256 newOrderSizeExponentialFactor);
    event SetUnderlyingPriceAdjustPercentage(uint256 oldUnderlyinPriceAdjustPercentage, uint256 newUnderlyingPriceAdjustPercentage);
	event SetMinOptionPricePercentage(uint256 oldMinOptionPricePercentage, uint256 newMinOptionPricePercentage);
	event SetAssetPrecision(address indexed asset, uint256 oldAssetPrecision, uint256 newAssetPrecision);

    uint256 internal constant PERCENTAGE_PRECISION = 100000;

    uint256 public underlyingPriceAdjustPercentage;
	uint256 public minOptionPricePercentage;
    uint256 public orderSizeMultiplierFactor;
    uint256 public orderSizeDividerFactor;
    uint256 public orderSizeExponentialFactor;
    mapping(address => uint256) public assetPrecision;
    
    uint256 internal orderSizeExponetialDivFactor;
    
    constructor(
        uint256 _underlyingPriceAdjustPercentage,
		uint256 _minOptionPricePercentage,
        uint256 _orderSizeMultiplierFactor,
		uint256 _orderSizeDividerFactor,
        uint256 _orderSizeExponentialFactor
    ) {
		super.init();
		
        _setUnderlyingPriceAdjustPercentage(_underlyingPriceAdjustPercentage);
		_setMinOptionPricePercentage(_minOptionPricePercentage);
        _setOrderSizeFactors(_orderSizeMultiplierFactor, _orderSizeDividerFactor, _orderSizeExponentialFactor);
    }

    function setUnderlyingPriceAdjustPercentage(uint256 _underlyingPriceAdjustPercentage) onlyOwner public {
        _setUnderlyingPriceAdjustPercentage(_underlyingPriceAdjustPercentage);
    }

	function setMinOptionPricePercentage(uint256 _minOptionPricePercentage) onlyOwner public {
        _setMinOptionPricePercentage(_minOptionPricePercentage);
    }

    function setOrderSizeFactors(uint256 _orderSizeMultiplierFactor, uint256 _orderSizeDividerFactor, uint256 _orderSizeExponentialFactor) onlyOwner public {
        _setOrderSizeFactors(_orderSizeMultiplierFactor, _orderSizeDividerFactor, _orderSizeExponentialFactor);
    }

    function setAssetPrecision(address asset) onlyOwner public {
        _setAssetPrecision(asset);
    }

    function quote(OptionQuote calldata quoteData) external override view returns(uint256, uint256) {
        require(quoteData.expiryTime > block.timestamp, "ACOPoolStrategy:: Expired");
		require(assetPrecision[quoteData.strikeAsset] > 0, "ACOPoolStrategy:: Asset precision is not defined");
        uint256 volatility = _getVolatility(quoteData);
        uint256 price = _getOptionPrice(volatility, quoteData);
        require(price > 0, "ACOPoolStrategy:: Invalid price");
        return (price, volatility);
    }

    function _getVolatility(OptionQuote memory quoteData) internal view returns(uint256) {
        uint256 orderSizeAdjust = _getOrderSizeAdjust(quoteData);
        return quoteData.baseVolatility.mul(orderSizeAdjust.add(PERCENTAGE_PRECISION)).div(PERCENTAGE_PRECISION);
    }

    function _getOptionPrice(uint256 volatility, OptionQuote memory quoteData) internal view returns(uint256) {
        uint256 underlyingPriceForQuote = _getUnderlyingPriceForQuote(quoteData);
        uint256 price = BlackScholes.getOptionPrice(
            quoteData.isCallOption,
            quoteData.strikePrice, 
            underlyingPriceForQuote,
            assetPrecision[quoteData.strikeAsset],
            quoteData.expiryTime - block.timestamp, 
            volatility,
            0, 
            0,
            PERCENTAGE_PRECISION
        );
        return _getValidPriceForQuote(price, quoteData);
    }

    function _getOrderSizeAdjust(OptionQuote memory quoteData) internal view returns(uint256) {
        uint256 orderSizePercentage = quoteData.collateralOrderAmount.mul(PERCENTAGE_PRECISION).div(quoteData.collateralAvailable);
		require(orderSizePercentage <= PERCENTAGE_PRECISION, "ACOPoolStrategy:: No liquidity");
        return (orderSizePercentage ** orderSizeExponentialFactor).mul(orderSizeMultiplierFactor).div(orderSizeDividerFactor).div(orderSizeExponetialDivFactor);
    }

    function _getUnderlyingPriceForQuote(OptionQuote memory quoteData) internal view returns(uint256) {
		if (quoteData.isCallOption) {
			return quoteData.underlyingPrice.mul(PERCENTAGE_PRECISION.add(underlyingPriceAdjustPercentage)).div(PERCENTAGE_PRECISION);
		} else {
			return quoteData.underlyingPrice.mul(PERCENTAGE_PRECISION.sub(underlyingPriceAdjustPercentage)).div(PERCENTAGE_PRECISION);
		}
    }

    function _getValidPriceForQuote(uint256 price, OptionQuote memory quoteData) internal view returns(uint256) {
		uint256 basePrice = quoteData.isCallOption ? quoteData.underlyingPrice : quoteData.strikePrice;
		uint256 minPrice = basePrice.mul(minOptionPricePercentage).div(PERCENTAGE_PRECISION);
		if (minPrice > price) {
			return minPrice;
		}
		return price;
    }

    function _setAssetPrecision(address asset) internal {
		uint8 decimals = ACOAssetHelper._getAssetDecimals(asset);
		uint256 precision = (10 ** uint256(decimals));
        emit SetAssetPrecision(asset, assetPrecision[asset], precision);
        assetPrecision[asset] = precision;
    }

    function _setUnderlyingPriceAdjustPercentage(uint256 _underlyingPriceAdjustPercentage) internal {
        require(_underlyingPriceAdjustPercentage <= PERCENTAGE_PRECISION, "ACOPoolStrategy:: Invalid underlying price adjust");
        emit SetUnderlyingPriceAdjustPercentage(underlyingPriceAdjustPercentage, _underlyingPriceAdjustPercentage);
        underlyingPriceAdjustPercentage = _underlyingPriceAdjustPercentage;
    }

	function _setMinOptionPricePercentage(uint256 _minOptionPricePercentage) internal {
		require(_minOptionPricePercentage > 0 && _minOptionPricePercentage < PERCENTAGE_PRECISION, "ACOPoolStrategy:: Invalid min option price percentage");
        emit SetMinOptionPricePercentage(minOptionPricePercentage, _minOptionPricePercentage);
        minOptionPricePercentage = _minOptionPricePercentage;
	}

    function _setOrderSizeFactors(uint256 _orderSizeMultiplierFactor, uint256 _orderSizeDividerFactor, uint256 _orderSizeExponentialFactor) internal {
		require(_orderSizeDividerFactor > 0, "ACOPoolStrategy:: Invalid divider factor");
        require(_orderSizeExponentialFactor > 0 && _orderSizeExponentialFactor <= 10, "ACOPoolStrategy:: Invalid exponential factor");
        emit SetOrderSizeFactors(orderSizeMultiplierFactor, orderSizeDividerFactor, orderSizeExponentialFactor, _orderSizeMultiplierFactor, _orderSizeDividerFactor, _orderSizeExponentialFactor);
        orderSizeMultiplierFactor = _orderSizeMultiplierFactor;
        orderSizeDividerFactor = _orderSizeDividerFactor;
		orderSizeExponentialFactor = _orderSizeExponentialFactor;
        orderSizeExponetialDivFactor = (PERCENTAGE_PRECISION ** (_orderSizeExponentialFactor - 1));
    }
}