// SPDX-License-Identifier: None
pragma solidity 0.8.4;

import './Ownable.sol';
import '../libs/Address.sol';
import '../libs/SafeMath.sol';
import '../libs/ACOAssetHelper.sol';
import '../interfaces/IACOAssetConverterHelper.sol';
import '../interfaces/IUniswapV2Router02.sol';
import '../interfaces/AggregatorV3Interface.sol';
import '../interfaces/IWETH.sol';

contract ACOAssetConverterHelper is Ownable, IACOAssetConverterHelper {
    using Address for address;
    using SafeMath for uint256;

    uint256 public constant PERCENTAGE_PRECISION = 100000;
    
    struct PairData {
        bool initialized;
        address aggregator;
        uint256 aggregatorPrecision;
        uint256 tolerancePercentage;
        address[] uniswapMiddleRoute;
    }

    event SetAggregator(address indexed baseAsset, address indexed quoteAsset, address previousAggregator, address newAggregator);
    event SetUniswapMiddleRoute(address indexed baseAsset, address indexed quoteAsset, address[] previousUniswapMiddleRoute, address[] newUniswapMiddleRoute);
	event SetPairTolerancePercentage(address indexed baseAsset, address indexed quoteAsset, uint256 oldTolerancePercentage, uint256 newTolerancePercentage);
    IUniswapV2Router02 public immutable uniswapRouter;
    

    address public immutable WETH;


    mapping(address => mapping(address => PairData)) internal pairs; 
    mapping(address => uint256) public assetPrecision;
    
    constructor(address _uniswapRouter) {
		super.init();
		
		uniswapRouter = IUniswapV2Router02(_uniswapRouter);
		WETH = IUniswapV2Router02(_uniswapRouter).WETH();
    }
    
    receive() external payable {
        require(msg.sender != tx.origin, "ACOAssetConverterHelper:: Only contracts can send ether");
    }

    function setPairTolerancePercentage(address baseAsset, address quoteAsset, uint256 tolerancePercentage) onlyOwner public override {
        require(tolerancePercentage <= PERCENTAGE_PRECISION, "ACOAssetConverterHelper:: Invalid tolerance percentage");
        (bool reversed, PairData storage data) = _getPair(baseAsset, quoteAsset, false);
        if (data.initialized) {
			if (reversed) {
				emit SetPairTolerancePercentage(quoteAsset, baseAsset, data.tolerancePercentage, tolerancePercentage);
			} else {
				emit SetPairTolerancePercentage(baseAsset, quoteAsset, data.tolerancePercentage, tolerancePercentage);
			}
            data.tolerancePercentage = tolerancePercentage;
        } else {
			emit SetPairTolerancePercentage(baseAsset, quoteAsset, 0, tolerancePercentage);
            _createPair(baseAsset, quoteAsset, address(0), 0, tolerancePercentage, new address[](0));
        }
    }

    function setAggregator(address baseAsset, address quoteAsset, address aggregator) onlyOwner public override {
        require(aggregator.isContract(), "ACOAssetConverterHelper:: Invalid aggregator");
        uint256 aggregatorPrecision = (10 ** uint256(AggregatorV3Interface(aggregator).decimals()));
        (bool reversed, PairData storage data) = _getPair(baseAsset, quoteAsset, false);
        if (data.initialized) {
			if (reversed) {
				emit SetAggregator(quoteAsset, baseAsset, data.aggregator, aggregator);
			} else {
				emit SetAggregator(baseAsset, quoteAsset, data.aggregator, aggregator);
			}
            data.aggregator = aggregator;
            data.aggregatorPrecision = aggregatorPrecision;
        } else {
			emit SetAggregator(baseAsset, quoteAsset, address(0), aggregator);
            _createPair(baseAsset, quoteAsset, aggregator, aggregatorPrecision, 0, new address[](0));
        }
    }

    function setUniswapMiddleRoute(address baseAsset, address quoteAsset, address[] memory uniswapMiddleRoute) onlyOwner public override {
        _validateUniswapMiddleRoute(baseAsset, quoteAsset, uniswapMiddleRoute);
        (bool reversed, PairData storage data) = _getPair(baseAsset, quoteAsset, false);
        if (data.initialized) {
            if (reversed) {
                address[] memory route = new address[](uniswapMiddleRoute.length);
                uint256 index = 0;
                for (uint256 i = uniswapMiddleRoute.length; i > 0; --i) {
                    route[index] = uniswapMiddleRoute[i-1];
                    ++index;
                }
				emit SetUniswapMiddleRoute(quoteAsset, baseAsset, data.uniswapMiddleRoute, route);
                delete data.uniswapMiddleRoute;
                data.uniswapMiddleRoute = route;
            } else {
				emit SetUniswapMiddleRoute(baseAsset, quoteAsset, data.uniswapMiddleRoute, uniswapMiddleRoute);
                delete data.uniswapMiddleRoute;
                data.uniswapMiddleRoute = uniswapMiddleRoute;
            }
        } else {
			emit SetUniswapMiddleRoute(baseAsset, quoteAsset, new address[](0), uniswapMiddleRoute);
            _createPair(baseAsset, quoteAsset, address(0), 0, 0, uniswapMiddleRoute);
        }
    }

    function withdrawStuckAsset(address asset, address destination) onlyOwner public override {
        uint256 amount = ACOAssetHelper._getAssetBalanceOf(asset, address(this));
        if (amount > 0) {
            ACOAssetHelper._transferAsset(asset, destination, amount);
        }
    }

    function hasAggregator(address baseAsset, address quoteAsset) public override view returns(bool) {
        (,PairData storage data) = _getPair(baseAsset, quoteAsset, false);
        return (data.aggregator != address(0));
    }

    function getPairData(address baseAsset, address quoteAsset) public override view returns(address, uint256, uint256, uint256) {
        (,PairData storage data) = _getPair(baseAsset, quoteAsset, false);
        return (data.aggregator, data.aggregatorPrecision, data.tolerancePercentage, data.uniswapMiddleRoute.length);
    }

    function getUniswapMiddleRouteByIndex(address baseAsset, address quoteAsset, uint256 index) public override view returns(address) {
        (bool reversed, PairData memory data) = _getPair(baseAsset, quoteAsset, false);
        if (reversed) {
            if (index >= data.uniswapMiddleRoute.length) {
                return address(0);
            } else {
                return data.uniswapMiddleRoute[(data.uniswapMiddleRoute.length - index - 1)];    
            }
        } else {
            return data.uniswapMiddleRoute[index];
        }
    }

    function getPrice(address baseAsset, address quoteAsset) public override view returns(uint256) {
        (uint256 price,) = _getAggregatorPriceAndTolerance(baseAsset, quoteAsset);  
        return price;
    }

    function getPriceWithTolerance(address baseAsset, address quoteAsset, bool isMinimumPrice) public override view returns(uint256) {
        (uint256 price, uint256 tolerancePercentage) = _getAggregatorPriceAndTolerance(baseAsset, quoteAsset);
        return _getPriceWithTolerance(price, tolerancePercentage, isMinimumPrice);
    }

    function getExpectedAmountOutToSwapExactAmountIn(address assetToSold, address assetToBuy, uint256 amountToBuy) public override view returns(uint256) {
        (bool reversed, PairData storage data) = _getPair(assetToSold, assetToBuy, true);
        return _getMaxAmountToSoldToSwapExactAmountIn(assetToSold, assetToBuy, amountToBuy, data.tolerancePercentage, reversed, data);
    }

    function getExpectedAmountOutToSwapExactAmountInWithSpecificTolerance(address assetToSold, address assetToBuy, uint256 amountToBuy, uint256 tolerancePercentage) public override view returns(uint256) {
        (bool reversed, PairData storage data) = _getPair(assetToSold, assetToBuy, true);
        return _getMaxAmountToSoldToSwapExactAmountIn(assetToSold, assetToBuy, amountToBuy, tolerancePercentage, reversed, data);
    }

    function swapExactAmountOut(address assetToSold, address assetToBuy, uint256 amountToSold) public payable override returns(uint256) {
        (bool reversed, PairData storage data) = _getPair(assetToSold, assetToBuy, true);
        return _swapExactAmountOut(assetToSold, assetToBuy, amountToSold, data.tolerancePercentage, reversed, data);
    }

    function swapExactAmountOutWithSpecificTolerance(address assetToSold, address assetToBuy, uint256 amountToSold, uint256 tolerancePercentage) public payable override returns(uint256) {
        require(tolerancePercentage <= PERCENTAGE_PRECISION, "ACOAssetConverterHelper:: Invalid tolerance percentage");
        (bool reversed, PairData storage data) = _getPair(assetToSold, assetToBuy, true);
        return _swapExactAmountOut(assetToSold, assetToBuy, amountToSold, tolerancePercentage, reversed, data);
    }

    function swapExactAmountOutWithMinAmountToReceive(address assetToSold, address assetToBuy, uint256 amountToSold, uint256 minAmountToReceive) public payable override returns(uint256) {
        (bool reversed, PairData storage data) = _getPair(assetToSold, assetToBuy, false);
        _setAsset(assetToSold);
        return _swapExactAmountOutWithMinAmountToReceive(assetToSold, assetToBuy, amountToSold, minAmountToReceive, reversed, data.uniswapMiddleRoute);
    }

    function swapExactAmountIn(address assetToSold, address assetToBuy, uint256 amountToBuy) public payable override returns(uint256) {
        (bool reversed, PairData storage data) = _getPair(assetToSold, assetToBuy, true);
        return _swapExactAmountIn(assetToSold, assetToBuy, amountToBuy, data.tolerancePercentage, reversed, data);
    }

    function swapExactAmountInWithSpecificTolerance(address assetToSold, address assetToBuy, uint256 amountToBuy, uint256 tolerancePercentage) public payable override returns(uint256) {
        require(tolerancePercentage <= PERCENTAGE_PRECISION, "ACOAssetConverterHelper:: Invalid tolerance percentage");
        (bool reversed, PairData storage data) = _getPair(assetToSold, assetToBuy, true);
        return _swapExactAmountIn(assetToSold, assetToBuy, amountToBuy, tolerancePercentage, reversed, data);
    }

    function swapExactAmountInWithMaxAmountToSold(address assetToSold, address assetToBuy, uint256 amountToBuy, uint256 maxAmountToSold) public payable override returns(uint256) {
        (bool reversed, PairData storage data) = _getPair(assetToSold, assetToBuy, false);
        _setAsset(assetToSold);
        return _swapExactAmountInWithMaxAmountToSold(assetToSold, assetToBuy, amountToBuy, maxAmountToSold, reversed, data.uniswapMiddleRoute);
    }

    function _swapExactAmountIn(
        address assetToSold, 
        address assetToBuy, 
        uint256 amount, 
        uint256 tolerancePercentage,
        bool reversed,
        PairData storage data
    ) internal returns(uint256) {
        uint256 maxAmountToSold = _getMaxAmountToSoldToSwapExactAmountIn(
            assetToSold,
            assetToBuy,
            amount,
            tolerancePercentage,
            reversed,
            data
        );
        return _swapExactAmountInWithMaxAmountToSold(assetToSold, assetToBuy, amount, maxAmountToSold, reversed, data.uniswapMiddleRoute);
    }

    function _getMaxAmountToSoldToSwapExactAmountIn(
        address assetToSold, 
        address assetToBuy, 
        uint256 amount, 
        uint256 tolerancePercentage,
        bool reversed,
        PairData storage data
    ) internal view returns(uint256) {
        uint256 price = _getPriceWithTolerance(_getAggregatorPriceValue(assetToBuy, reversed, data), tolerancePercentage, true);
        return amount.mul(assetPrecision[assetToSold]).div(price);
    }

    function _swapExactAmountInWithMaxAmountToSold(
        address assetToSold, 
        address assetToBuy, 
        uint256 amountToBuy, 
        uint256 maxAmountToSold,
        bool reversed,
        address[] storage uniswapMiddleRoute
    ) internal returns(uint256) {
        uint256 previousAmount = ACOAssetHelper._getAssetBalanceOf(assetToSold, address(this));
        
        if (ACOAssetHelper._isEther(assetToSold)) {
            previousAmount = previousAmount.sub(msg.value);
            require(msg.value >= maxAmountToSold, "ACOAssetConverterHelper:: Invalid ETH amount");
        } else {
            require(msg.value == 0, "ACOAssetConverterHelper:: Ether is not expected");
            ACOAssetHelper._callTransferFromERC20(assetToSold, msg.sender, address(this), maxAmountToSold);
        }

        _swapAssetsExactAmountIn(assetToSold, assetToBuy, amountToBuy, maxAmountToSold, reversed, uniswapMiddleRoute);
        
        uint256 afterAmount = ACOAssetHelper._getAssetBalanceOf(assetToSold, address(this));
        uint256 remaining = afterAmount.sub(previousAmount);
        if (remaining > 0) {
            ACOAssetHelper._transferAsset(assetToSold, msg.sender, remaining);
        }
        ACOAssetHelper._transferAsset(assetToBuy, msg.sender, amountToBuy);
        return maxAmountToSold.sub(remaining);
    }

    function _swapExactAmountOut(
        address assetToSold, 
        address assetToBuy, 
        uint256 amount, 
        uint256 tolerancePercentage,
        bool reversed,
        PairData storage data
    ) internal returns(uint256) {
        uint256 price = _getPriceWithTolerance(_getAggregatorPriceValue(assetToBuy, reversed, data), tolerancePercentage, true);
        uint256 minAmountToReceive = price.mul(amount).div(assetPrecision[assetToSold]);
        
        return _swapExactAmountOutWithMinAmountToReceive(assetToSold, assetToBuy, amount, minAmountToReceive, reversed, data.uniswapMiddleRoute);
    }

    function _swapExactAmountOutWithMinAmountToReceive(
        address assetToSold, 
        address assetToBuy, 
        uint256 amountToSold, 
        uint256 minAmountToReceive,
        bool reversed,
        address[] storage uniswapMiddleRoute
    ) internal returns(uint256) {
        ACOAssetHelper._receiveAsset(assetToSold, amountToSold);
        
        uint256 previousAmount = ACOAssetHelper._getAssetBalanceOf(assetToBuy, address(this));
        
        _swapAssetsExactAmountOut(assetToSold, assetToBuy, amountToSold, minAmountToReceive, reversed, uniswapMiddleRoute);
        
        uint256 afterAmount = ACOAssetHelper._getAssetBalanceOf(assetToBuy, address(this));
        uint256 purchased = afterAmount.sub(previousAmount);
        ACOAssetHelper._transferAsset(assetToBuy, msg.sender, purchased);
        return purchased;
    }

    function _validateUniswapMiddleRoute(address asset0, address asset1, address[] memory uniswapMiddleRoute) internal pure {
        for (uint256 i = 0; i < uniswapMiddleRoute.length; ++i) {
            address asset = uniswapMiddleRoute[i];
            require(asset0 != asset && asset1 != asset, "ACOAssetConverterHelper:: Invalid middle route");
            for (uint256 j = i+1; j < uniswapMiddleRoute.length; ++j) {
                require(asset != uniswapMiddleRoute[j], "ACOAssetConverterHelper:: Invalid middle route");
            }
        }
    }

    function _getPriceWithTolerance(uint256 price, uint256 tolerancePercentage, bool isMinimumPrice) internal pure returns(uint256) {
        if (isMinimumPrice) {
            return price.mul(PERCENTAGE_PRECISION.sub(tolerancePercentage)).div(PERCENTAGE_PRECISION);
        } else {
            return price.mul(PERCENTAGE_PRECISION.add(tolerancePercentage)).div(PERCENTAGE_PRECISION);    
        }
    }

    function _getPair(address baseAsset, address quoteAsset, bool validateAggregatorExistence) internal view returns(bool, PairData storage) {
        PairData storage data = pairs[baseAsset][quoteAsset];
        if (data.initialized) {
			require(!validateAggregatorExistence || data.aggregator != address(0), "ACOAssetConverterHelper:: No aggregator");
            return (false, data);
        } else {
			PairData storage data2 = pairs[quoteAsset][baseAsset];
			require(!validateAggregatorExistence || data2.aggregator != address(0), "ACOAssetConverterHelper:: No aggregator");
			return (data2.initialized, data2);
		}
    }

    function _getAggregatorPriceAndTolerance(address baseAsset, address quoteAsset) internal view returns(uint256, uint256) {
        (bool reversed, PairData storage data) = _getPair(baseAsset, quoteAsset, true);
        uint256 price = _getAggregatorPriceValue(quoteAsset, reversed, data);
        return (price, data.tolerancePercentage);
    }

    function _getAggregatorPriceValue(address quoteAsset, bool reversed, PairData storage data) internal view returns(uint256) {
        (,int256 answer,,,) = AggregatorV3Interface(data.aggregator).latestRoundData();
        
        uint256 _aggregatorPrecision = data.aggregatorPrecision;
        uint256 _assetPrecision = assetPrecision[quoteAsset];
        
        if (reversed) {
            return _aggregatorPrecision.mul(_assetPrecision).div(uint256(answer));
        } else if (_aggregatorPrecision > _assetPrecision) {
            return uint256(answer).div(_aggregatorPrecision.div(_assetPrecision));
        } else {
            return uint256(answer).mul(_assetPrecision).div(_aggregatorPrecision);
        }
    }

	function _createPair(
	    address baseAsset,
	    address quoteAsset,
	    address aggregator, 
	    uint256 aggregatorPrecision,
	    uint256 tolerancePercentage, 
	    address[] memory uniswapMiddleRoute
    ) internal {
        require(baseAsset != quoteAsset, "ACOAssetConverterHelper:: Invalid assets");
        require(ACOAssetHelper._isEther(baseAsset) || baseAsset.isContract(), "ACOAssetConverterHelper:: Invalid base asset");
        require(ACOAssetHelper._isEther(quoteAsset) || quoteAsset.isContract(), "ACOAssetConverterHelper:: Invalid quote asset");
        
        _setAsset(baseAsset);
        _setAsset(quoteAsset);
        
        pairs[baseAsset][quoteAsset] = PairData(true, aggregator, aggregatorPrecision, tolerancePercentage, uniswapMiddleRoute);
    }

    function _setAsset(address asset) internal {
        if (assetPrecision[asset] == 0) {
            uint256 decimals = ACOAssetHelper._getAssetDecimals(asset);
            assetPrecision[asset] = (10 ** decimals);
            if (!ACOAssetHelper._isEther(asset)) {
                ACOAssetHelper._callApproveERC20(asset, address(uniswapRouter), 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff);
            }
        }
    }

	function _getUniswapRouterPath(address assetOut, address assetIn, bool reversed, address[] storage uniswapMiddleRoute) internal view returns(address[] memory) {
        address[] memory path = new address[](2 + uniswapMiddleRoute.length);
        address end;
        if (ACOAssetHelper._isEther(assetOut)) {
            path[0] = WETH;
            end = assetIn;
        } else if (ACOAssetHelper._isEther(assetIn)) {
            path[0] = assetOut;
            end = WETH;
        } else {
            path[0] = assetOut;
            end = assetIn;
        }
        uint256 index = 1;
        uint256 i = (uniswapMiddleRoute.length > 0 && reversed ? (uniswapMiddleRoute.length - 1) : 0);
        while (i < uniswapMiddleRoute.length && i >= 0) {
            path[index] = uniswapMiddleRoute[i];
            ++index;
            if (reversed) {
                if (i == 0) {
                    break;
                }
                --i;
            } else {
                ++i;
            }
        }
        path[index] = end;
        return path;
	}
	
    function _swapAssetsExactAmountOut(
        address assetOut, 
        address assetIn, 
        uint256 amountOut, 
        uint256 minAmountIn,
        bool reversed,
        address[] storage uniswapMiddleRoute
    ) internal {
        address[] memory path = _getUniswapRouterPath(assetOut, assetIn, reversed, uniswapMiddleRoute);
        if (ACOAssetHelper._isEther(assetOut)) {
            uniswapRouter.swapExactETHForTokens{value: amountOut}(minAmountIn, path, address(this), block.timestamp);
        } else if (ACOAssetHelper._isEther(assetIn)) {
            uniswapRouter.swapExactTokensForETH(amountOut, minAmountIn, path, address(this), block.timestamp);
        } else {
            uniswapRouter.swapExactTokensForTokens(amountOut, minAmountIn, path, address(this), block.timestamp);
        }
    }

    function _swapAssetsExactAmountIn(
        address assetOut, 
        address assetIn, 
        uint256 amountIn, 
        uint256 maxAmountOut, 
        bool reversed,
        address[] storage uniswapMiddleRoute
    ) internal {
        address[] memory path = _getUniswapRouterPath(assetOut, assetIn, reversed, uniswapMiddleRoute);
        if (ACOAssetHelper._isEther(assetOut)) {
            uniswapRouter.swapETHForExactTokens{value: maxAmountOut}(amountIn, path, address(this), block.timestamp);
        } else if (ACOAssetHelper._isEther(assetIn)) {
            uniswapRouter.swapTokensForExactETH(amountIn, maxAmountOut, path, address(this), block.timestamp);
        } else {
            uniswapRouter.swapTokensForExactTokens(amountIn, maxAmountOut, path, address(this), block.timestamp);
        }
    }
}