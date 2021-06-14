// SPDX-License-Identifier: None
pragma solidity 0.8.4;

import "../util/Ownable.sol";
import '../libs/ACOAssetHelper.sol';
import "../interfaces/IWETH.sol";
import "../interfaces/IUniswapV2Pair.sol";
import "../interfaces/IUniswapV2Callee.sol";
import "../interfaces/IUniswapV2Factory.sol";
import "../interfaces/IUniswapV2Router02.sol";
import "../interfaces/IACOToken.sol";

contract ACOFlashExercise is Ownable, IUniswapV2Callee {
  
    address immutable public uniswapFactory;
    address immutable public uniswapRouter;
    address immutable public weth;

    mapping(address => mapping(address => address[])) internal middleRoute; 
    
    constructor(address _uniswapRouter) {
		super.init();
		
        uniswapRouter = _uniswapRouter;
        uniswapFactory = IUniswapV2Router02(_uniswapRouter).factory();
        weth = IUniswapV2Router02(_uniswapRouter).WETH();
    }

    receive() external payable {}

    function withdrawStuckAsset(address asset, address destination) onlyOwner public {
        uint256 amount = ACOAssetHelper._getAssetBalanceOf(asset, address(this));
        if (amount > 0) {
            ACOAssetHelper._transferAsset(asset, destination, amount);
        }
    }

    function setUniswapMiddleRoute(address baseAsset, address quoteAsset, address[] memory uniswapMiddleRoute) onlyOwner public {
        _validateUniswapMiddleRoute(baseAsset, quoteAsset, uniswapMiddleRoute);
        (bool reversed, address[] storage route) = _getMiddleRoute(baseAsset, quoteAsset);
        if (route.length > 0) {
            if (reversed) {
				delete middleRoute[quoteAsset][baseAsset];
            } else {
				delete middleRoute[baseAsset][quoteAsset];
            }
        }
		address _uniswapRouter = uniswapRouter;
		address _weth = weth;
		ACOAssetHelper._callApproveERC20(_getUniswapToken(baseAsset, _weth), _uniswapRouter, ACOAssetHelper.MAX_UINT);
		ACOAssetHelper._callApproveERC20(_getUniswapToken(quoteAsset, _weth), _uniswapRouter, ACOAssetHelper.MAX_UINT);
		middleRoute[baseAsset][quoteAsset] = uniswapMiddleRoute;
    }

    function getMiddleRoute(address baseAsset, address quoteAsset) public view returns(bool, address[] memory) {
        return _getMiddleRoute(baseAsset, quoteAsset);
    }

    function hasFlashExercise(address acoToken) public view returns(bool) {
		(address pair,) = _getUniswapData(acoToken);
        return pair != address(0);
    }

    function getExerciseData(address acoToken, uint256 tokenAmount, address[] memory accounts) public view returns(uint256, uint256) {
        if (tokenAmount > 0) {
            (address pair, address[] memory path) = _getUniswapData(acoToken);
            if (pair != address(0)) {
                (address exerciseAddress, uint256 expectedAmount) = _getAcoExerciseData(acoToken, tokenAmount, accounts);
				exerciseAddress = _getUniswapToken(exerciseAddress, weth);

				(uint256 reserve0, uint256 reserve1,) = IUniswapV2Pair(pair).getReserves();
				uint256 reserveIn = 0; 
				uint256 reserveOut = 0; 
				if (exerciseAddress == IUniswapV2Pair(pair).token0() && expectedAmount < reserve0) {
					reserveIn = reserve1;
					reserveOut = reserve0;
				} else if (exerciseAddress == IUniswapV2Pair(pair).token1() && expectedAmount < reserve1) {
					reserveIn = reserve0;
					reserveOut = reserve1;
				}
				
				if (reserveIn > 0 && reserveOut > 0) {
					uint256 requiredAmount = IUniswapV2Router02(uniswapRouter).getAmountIn(expectedAmount, reserveIn, reserveOut);
					uint256 requiredCollateral;
					if (path.length > 0) {
						requiredCollateral = IUniswapV2Router02(uniswapRouter).getAmountsIn(requiredAmount, path)[0];
					} else {
						requiredCollateral = requiredAmount;
					}
					return (requiredCollateral, expectedAmount);
				}
            }
        }
        return (0, 0);
    }

    function getEstimatedReturn(address acoToken, uint256 tokenAmount) public view returns(uint256) {
        (uint256 requiredAmount,) = getExerciseData(acoToken, tokenAmount, new address[](0));
        if (requiredAmount > 0) {
            (uint256 collateralAmount,) = IACOToken(acoToken).getCollateralOnExercise(tokenAmount);
            if (requiredAmount < collateralAmount) {
                return collateralAmount - requiredAmount;
            }
        }
        return 0;
    }

    function flashExercise(address acoToken, uint256 tokenAmount, uint256 minimumCollateral, uint256 salt) public {
        _flashExercise(acoToken, tokenAmount, minimumCollateral, salt, new address[](0));
    }

    function flashExerciseAccounts(
        address acoToken, 
        uint256 tokenAmount, 
        uint256 minimumCollateral, 
        address[] memory accounts
    ) public {
        require(accounts.length > 0, "ACOFlashExercise::flashExerciseAccounts: Accounts are required");
        _flashExercise(acoToken, tokenAmount, minimumCollateral, 0, accounts);
    }

    function uniswapV2Call(
        address sender, 
        uint256 amount0Out, 
        uint256 amount1Out, 
        bytes calldata data
    ) external override {
        require(sender == address(this), "ACOFlashExercise::uniswapV2Call: Invalid sender");
        
        uint256 requiredAmount = _getFlasSwapPaymentRequired(amount0Out, amount1Out);
        (address account, address collateral, uint256 collateralAmount, uint256 remainingAmount, address[] memory path) = _exercise(requiredAmount, data);
        
		_sendAmounts(
			account, 
			collateral, 
			collateralAmount, 
			remainingAmount, 
			requiredAmount, 
			path
		);
    }

	function _sendAmounts(
		address account, 
		address collateral, 
		uint256 collateralAmount, 
		uint256 remainingAmount, 
		uint256 uniswapRequiredAmount, 
		address[] memory path
	) internal {
		if (path.length > 0) {
			uint256 toPayAmount = collateralAmount - remainingAmount;
			if (ACOAssetHelper._isEther(collateral)) {
				IWETH(weth).deposit{value: toPayAmount}();
			}
			IUniswapV2Router02(uniswapRouter).swapTokensForExactTokens(uniswapRequiredAmount, toPayAmount, path, msg.sender, block.timestamp);
		} else {
			address uniswapAsset;
			if (ACOAssetHelper._isEther(collateral)) {
				uniswapAsset = weth;
				IWETH(uniswapAsset).deposit{value: uniswapRequiredAmount}();
			} else {
				uniswapAsset = collateral;
			}
			ACOAssetHelper._callTransferERC20(uniswapAsset, msg.sender, uniswapRequiredAmount); 
		}
		ACOAssetHelper._transferAsset(collateral, account, remainingAmount);
	}

	function _validateMinimumCollateral(uint256 requiredAmount, uint256 collateralAmount, uint256 minimumCollateral) internal pure returns(uint256) {
		require(requiredAmount <= collateralAmount, "ACOFlashExercise::_validateMinimumCollateral: Insufficient collateral amount");
		uint256 remainingAmount = collateralAmount - requiredAmount;
		require(remainingAmount >= minimumCollateral, "ACOFlashExercise::_validateMinimumCollateral: Minimum amount not satisfied");
		return remainingAmount;
	}

	function _exercise(uint256 requiredAmount, bytes memory data) internal returns(
		address, 
		address, 
		uint256,
		uint256,
		address[] memory
	) {
        (address account, 
		 address acoToken, 
		 uint256 tokenAmount, 
		 uint256 salt, 
		 uint256 collateralAmount, 
		 uint256 remainingAmount,
		 address[] memory accounts, 
		 address[] memory path) = _getExerciseBaseData(requiredAmount, data);
        
        _exerciseAco(account, acoToken, tokenAmount, salt, accounts);
		
		address collateral = IACOToken(acoToken).collateral();
		return (account, collateral, collateralAmount, remainingAmount, path);
	}

	function _getExerciseBaseData(uint256 requiredAmount, bytes memory data) internal view returns(
	    address account,
	    address acoToken,
	    uint256 tokenAmount,
	    uint256 salt,
	    uint256 collateralAmount,
	    uint256 remainingAmount,
	    address[] memory accounts,
	    address[] memory path
	) {
	    uint256 minimumCollateral;
	    (account, 
		 acoToken, 
		 tokenAmount, 
		 minimumCollateral, 
		 salt, 
		 accounts, 
		 path) = abi.decode(data, (address, address, uint256, uint256, uint256, address[], address[]));
		 
	    (collateralAmount,) = IACOToken(acoToken).getCollateralOnExercise(tokenAmount);
		
        uint256 requiredCollateral;
		if (path.length > 0) {
			requiredCollateral = IUniswapV2Router02(uniswapRouter).getAmountsIn(requiredAmount, path)[0];
		} else {
            requiredCollateral = requiredAmount;
		}
        remainingAmount = _validateMinimumCollateral(requiredCollateral, collateralAmount, minimumCollateral);
	}

	function _exerciseAco(
	    address account,
	    address acoToken,
	    uint256 tokenAmount,
	    uint256 salt,
	    address[] memory accounts
    ) internal {
        (address exerciseAddress, uint256 expectedAmount) = _getAcoExerciseData(acoToken, tokenAmount, accounts);
		
		uint256 ethValue = 0;
        if (ACOAssetHelper._isEther(exerciseAddress)) {
            ethValue = expectedAmount;
            IWETH(weth).withdraw(expectedAmount);
        } else {
            ACOAssetHelper._callApproveERC20(exerciseAddress, acoToken, expectedAmount);
        }
        
        if (accounts.length == 0) {
            IACOToken(acoToken).exerciseFrom{value: ethValue}(account, tokenAmount, salt);
        } else {
            IACOToken(acoToken).exerciseAccountsFrom{value: ethValue}(account, tokenAmount, accounts);
        }
    }

	function _getFlasSwapPaymentRequired(uint256 amount0Out, uint256 amount1Out) internal view returns(uint256) {
        address token0 = IUniswapV2Pair(msg.sender).token0();
        address token1 = IUniswapV2Pair(msg.sender).token1();
        require(msg.sender == IUniswapV2Factory(uniswapFactory).getPair(token0, token1), "ACOFlashExercise::uniswapV2Call: Invalid transaction sender"); 
        require(amount0Out == 0 || amount1Out == 0, "ACOFlashExercise::uniswapV2Call: Invalid out amounts"); 
        
        (uint256 reserve0, uint256 reserve1,) = IUniswapV2Pair(msg.sender).getReserves();
		uint256 reserveIn; 
        uint256 reserveOut; 
		if (amount0Out == 0) {
			reserveIn = reserve0;
			reserveOut = reserve1;
		} else {
			reserveIn = reserve1;
			reserveOut = reserve0;
		}
        return IUniswapV2Router02(uniswapRouter).getAmountIn((amount0Out + amount1Out), reserveIn, reserveOut);
	}

	function _getAcoExerciseData(address acoToken, uint256 tokenAmount, address[] memory accounts) internal view returns(address, uint256) {
		(address exerciseAddress, uint256 expectedAmount) = IACOToken(acoToken).getBaseExerciseData(tokenAmount);
		if (accounts.length == 0) {
			expectedAmount = expectedAmount + IACOToken(acoToken).maxExercisedAccounts();
		} else {
			expectedAmount = expectedAmount + accounts.length;
		}
		return (exerciseAddress, expectedAmount);
	}

    function _flashExercise(
        address acoToken, 
        uint256 tokenAmount, 
        uint256 minimumCollateral, 
        uint256 salt,
        address[] memory accounts
    ) internal {
        (address pair, address[] memory path) = _getUniswapData(acoToken);
        require(pair != address(0), "ACOFlashExercise::_flashExercise: Invalid Uniswap pair");
        
        (address exerciseAddress, uint256 expectedAmount) = _getAcoExerciseData(acoToken, tokenAmount, accounts);

        uint256 amount0Out = 0;
        uint256 amount1Out = 0;
        if (_getUniswapToken(exerciseAddress, weth) == IUniswapV2Pair(pair).token0()) {
            amount0Out = expectedAmount;
        } else {
            amount1Out = expectedAmount;  
        }
        
        bytes memory data = abi.encode(msg.sender, acoToken, tokenAmount, minimumCollateral, salt, accounts, path);
        IUniswapV2Pair(pair).swap(amount0Out, amount1Out, address(this), data);
    }

    function _getUniswapToken(address token, address _weth) internal pure returns(address) {
        if (ACOAssetHelper._isEther(token)) {
            return _weth;
        } else {
            return token;
        }
    }

    function _getUniswapData(address acoToken) internal view returns(address, address[] memory) {
		IACOToken _aco = IACOToken(acoToken);
		address underlying = _aco.underlying();
        address strikeAsset = _aco.strikeAsset();
		address _weth = weth;
        (bool reversed, address[] storage route) = _getMiddleRoute(underlying, strikeAsset);
		if (route.length > 0) {
			bool isCall = _aco.isCall();
			address swapAsset;
			address[] memory path = new address[](route.length + 1);
			path[0] = _getUniswapToken((isCall ? underlying : strikeAsset), _weth);
			if ((isCall && reversed) || (!isCall && !reversed)) {
				swapAsset = _getUniswapToken(route[0], _weth);
				uint256 index = 1;
				for (uint256 i = route.length; i > 1; --i) {
					path[index] = _getUniswapToken(route[i - 1], _weth);
					++index;
				}
			} else {
				uint256 lastIndex = route.length - 1;
				swapAsset = _getUniswapToken(route[lastIndex], _weth);
				uint256 index = 1;
				for (uint256 i = 0; i < lastIndex; ++i) {
					path[index] = _getUniswapToken(route[i], _weth);
					++index;
				}
			}
			path[route.length] = swapAsset;
			address pair = IUniswapV2Factory(uniswapFactory).getPair(_getUniswapToken((isCall ? strikeAsset : underlying), _weth), swapAsset);
			return (pair, path);
		} else {	
			address pair = IUniswapV2Factory(uniswapFactory).getPair(_getUniswapToken(underlying, _weth), _getUniswapToken(strikeAsset, _weth));
			return (pair, new address[](0));
		}
    }

    function _getMiddleRoute(address baseAsset, address quoteAsset) internal view returns(bool, address[] storage) {
        address[] storage route = middleRoute[baseAsset][quoteAsset];
        if (route.length > 0) {
            return (false, route);
        } else {
			address[] storage route2 = middleRoute[quoteAsset][baseAsset];
			return ((route2.length > 0), route2);
		}
    }

    function _validateUniswapMiddleRoute(address asset0, address asset1, address[] memory uniswapMiddleRoute) internal pure {
        for (uint256 i = 0; i < uniswapMiddleRoute.length; ++i) {
            address asset = uniswapMiddleRoute[i];
            require(asset0 != asset && asset1 != asset, "ACOFlashExercise::_validateUniswapMiddleRoute: Invalid middle route");
            for (uint256 j = i+1; j < uniswapMiddleRoute.length; ++j) {
                require(asset != uniswapMiddleRoute[j], "ACOFlashExercise::_validateUniswapMiddleRoute: Invalid middle route");
            }
        }
    }
}