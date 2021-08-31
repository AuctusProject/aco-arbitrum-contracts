// SPDX-License-Identifier: None
pragma solidity 0.8.4;

import "../../core/ACOProxy.sol";
import "../../libs/Address.sol";
import "../../interfaces/IACOPool2.sol";
import "../../interfaces/IACOAssetConverterHelper.sol";

contract ACOPoolFactory2 {

    struct ACOPoolBasicData {
        address underlying;
        address strikeAsset;
        bool isCall;
    }

    event SetFactoryAdmin(address indexed previousFactoryAdmin, address indexed newFactoryAdmin);
    event SetAcoPoolImplementation(address indexed previousAcoPoolImplementation, address indexed newAcoPoolImplementation);
    event SetAcoFactory(address indexed previousAcoFactory, address indexed newAcoFactory);
    event SetAssetConverterHelper(address indexed previousAssetConverterHelper, address indexed newAssetConverterHelper);
    event SetAcoPoolFee(uint256 indexed previousAcoFee, uint256 indexed newAcoFee);
    event SetAcoPoolFeeDestination(address indexed previousAcoPoolFeeDestination, address indexed newAcoPoolFeeDestination);
    event SetAcoPoolWithdrawOpenPositionPenalty(uint256 indexed previousWithdrawOpenPositionPenalty, uint256 indexed newWithdrawOpenPositionPenalty);
    event SetAcoPoolUnderlyingPriceAdjustPercentage(uint256 indexed previousUnderlyingPriceAdjustPercentage, uint256 indexed newUnderlyingPriceAdjustPercentage);
    event SetAcoPoolMaximumOpenAco(uint256 indexed previousMaximumOpenAco, uint256 indexed newMaximumOpenAco);
    event SetAcoPoolLendingPool(address indexed oldLendingPool, address indexed newLendingPool);
    event SetAcoPoolLendingPoolReferral(uint256 indexed oldLendingPoolReferral, uint256 indexed newLendingPoolReferral);
    event SetAcoPoolPermission(address indexed poolAdmin, bool indexed previousPermission, bool indexed newPermission);
    event SetStrategyPermission(address indexed strategy, bool indexed previousPermission, bool newPermission);
    event SetOperator(address indexed operator, bool indexed previousPermission, bool indexed newPermission);
    event SetAuthorizedAcoCreator(address indexed acoCreator, bool indexed previousPermission, bool indexed newPermission);
    event SetPoolProxyAdmin(address indexed previousPoolProxyAdmin, address indexed newPoolProxyAdmin);
    event SetForbiddenAcoCreator(address indexed acoCreator, bool indexed previousStatus, bool indexed newStatus);
    event SetDefaultStrategy(address indexed previousDefaultStrategy, address indexed newDefaultStrategy);
    event SetStrikeAssetPermission(address indexed strikeAsset, bool indexed previousPermission, bool indexed newPermission);
    event NewAcoPool(address indexed underlying, address indexed strikeAsset, bool indexed isCall, address acoPool, address acoPoolImplementation);

    address public factoryAdmin;
    address public acoPoolImplementation;
    address public acoFactory;
    address public assetConverterHelper;
    uint256 public acoPoolFee;
    address public acoPoolFeeDestination;
    uint256 public acoPoolWithdrawOpenPositionPenalty;
    uint256 public acoPoolUnderlyingPriceAdjustPercentage;
    uint256 public acoPoolMaximumOpenAco;
	uint16 public lendingPoolReferral;
	address public lendingPool;
    address public defaultStrategy;
    uint256 public poolCount;
    address public poolProxyAdmin;
    
    mapping(address => bool) public poolAdminPermission;
    mapping(address => bool) public operators;
    mapping(address => bool) public strategyPermitted;
    mapping(address => bool) public strikeAssets;
    mapping(address => address) public creators;

    mapping(address => ACOPoolBasicData) public acoPoolBasicData;
    
    address[] internal acoAuthorizedCreators;
    address[] internal acoForbiddenCreators;

    modifier onlyFactoryAdmin() {
        require(msg.sender == factoryAdmin, "ACOPoolFactory::onlyFactoryAdmin");
        _;
    }

    modifier onlyPoolAdmin() {
        require(poolAdminPermission[msg.sender], "ACOPoolFactory::onlyPoolAdmin");
        _;
    }

    function init(
        address _factoryAdmin, 
        address _acoPoolImplementation, 
        address _acoFactory, 
        address _assetConverterHelper,
        uint256 _acoPoolFee,
        address _acoPoolFeeDestination,
		uint256 _acoPoolWithdrawOpenPositionPenalty,
		uint256 _acoPoolUnderlyingPriceAdjustPercentage,
        uint256 _acoPoolMaximumOpenAco,
        uint16 _lendingPoolReferral,
        address _lendingPool,
        address _defaultStrategy
    ) public {
        require(factoryAdmin == address(0) && acoPoolImplementation == address(0), "ACOPoolFactory::init: Contract already initialized.");
        
        _setFactoryAdmin(_factoryAdmin);
        _setAcoPoolImplementation(_acoPoolImplementation);
        _setAcoFactory(_acoFactory);
        _setAssetConverterHelper(_assetConverterHelper);
        _setAcoPoolFee(_acoPoolFee);
        _setAcoPoolFeeDestination(_acoPoolFeeDestination);
		_setAcoPoolWithdrawOpenPositionPenalty(_acoPoolWithdrawOpenPositionPenalty);
		_setAcoPoolUnderlyingPriceAdjustPercentage(_acoPoolUnderlyingPriceAdjustPercentage);
        _setAcoPoolMaximumOpenAco(_acoPoolMaximumOpenAco);
        _setAcoPoolLendingPool(_lendingPool);
        _setAcoPoolLendingPoolReferral(_lendingPoolReferral);
        _setAcoPoolPermission(_factoryAdmin, true);
        _setOperator(_factoryAdmin, true);
        _setPoolProxyAdmin(_factoryAdmin);
        _setAcoPoolStrategyPermission(_defaultStrategy, true);
        _setPoolDefaultStrategy(_defaultStrategy);
    }

    receive() external payable virtual {
        revert();
    }
    
    function getNumberOfAcoCreatorsAuthorized() view external virtual returns(uint256) {
        return acoAuthorizedCreators.length;
    }
    
    function getAcoCreatorAuthorized(uint256 index) view external virtual returns(address) {
        return acoAuthorizedCreators[index];
    }
        
    function getNumberOfAcoCreatorsForbidden() view external virtual returns(uint256) {
        return acoForbiddenCreators.length;
    }
    
    function getAcoCreatorForbidden(uint256 index) view external virtual returns(address) {
        return acoForbiddenCreators[index];
    }

    function setFactoryAdmin(address newFactoryAdmin) onlyFactoryAdmin external virtual {
        _setFactoryAdmin(newFactoryAdmin);
    }

    function setAcoPoolImplementation(address newAcoPoolImplementation) onlyFactoryAdmin external virtual {
        _setAcoPoolImplementation(newAcoPoolImplementation);
    }

    function setAcoFactory(address newAcoFactory) onlyFactoryAdmin external virtual {
        _setAcoFactory(newAcoFactory);
    }
    
    function setAssetConverterHelper(address newAssetConverterHelper) onlyFactoryAdmin external virtual {
        _setAssetConverterHelper(newAssetConverterHelper);
    }
    
    function setAcoPoolFee(uint256 newAcoPoolFee) onlyFactoryAdmin external virtual {
        _setAcoPoolFee(newAcoPoolFee);
    }
    
    function setAcoPoolFeeDestination(address newAcoPoolFeeDestination) onlyFactoryAdmin external virtual {
        _setAcoPoolFeeDestination(newAcoPoolFeeDestination);
    }
    
    function setAcoPoolWithdrawOpenPositionPenalty(uint256 newWithdrawOpenPositionPenalty) onlyFactoryAdmin external virtual {
        _setAcoPoolWithdrawOpenPositionPenalty(newWithdrawOpenPositionPenalty);
    }
	
    function setAcoPoolUnderlyingPriceAdjustPercentage(uint256 newUnderlyingPriceAdjustPercentage) onlyFactoryAdmin external virtual {
        _setAcoPoolUnderlyingPriceAdjustPercentage(newUnderlyingPriceAdjustPercentage);
    }

    function setAcoPoolMaximumOpenAco(uint256 newMaximumOpenAco) onlyFactoryAdmin external virtual {
        _setAcoPoolMaximumOpenAco(newMaximumOpenAco);
    }
    
    function setAcoPoolLendingPool(address newLendingPool) onlyFactoryAdmin external virtual {
        _setAcoPoolLendingPool(newLendingPool);
    }   

    function setAcoPoolLendingPoolReferral(uint16 newLendingPoolReferral) onlyFactoryAdmin external virtual {
        _setAcoPoolLendingPoolReferral(newLendingPoolReferral);
    }
	
    function setAcoPoolPermission(address poolAdmin, bool newPermission) onlyFactoryAdmin external virtual {
        _setAcoPoolPermission(poolAdmin, newPermission);
    }
    
    function setAcoPoolStrategyPermission(address strategy, bool newPermission) onlyFactoryAdmin external virtual {
        _setAcoPoolStrategyPermission(strategy, newPermission);
    }
    
    function setOperator(address operator, bool newPermission) onlyFactoryAdmin external virtual {
        _setOperator(operator, newPermission);
    }
    
    function setAuthorizedAcoCreator(address acoCreator, bool newPermission) onlyFactoryAdmin external virtual {
        _setAuthorizedAcoCreator(acoCreator, newPermission);
    }
    
    function setForbiddenAcoCreator(address acoCreator, bool newStatus) onlyFactoryAdmin external virtual {
        _setForbiddenAcoCreator(acoCreator, newStatus);
    }
    
    function setPoolProxyAdmin(address newPoolProxyAdmin) onlyFactoryAdmin external virtual {
        _setPoolProxyAdmin(newPoolProxyAdmin);
    }
    
    function setPoolDefaultStrategy(address newDefaultStrategy) onlyFactoryAdmin external virtual {
        _setPoolDefaultStrategy(newDefaultStrategy);
    }

    function setStrikeAssetPermission(address strikeAsset, bool newPermission) onlyFactoryAdmin external virtual {
        _setStrikeAssetPermission(strikeAsset, newPermission);
    }

    function updatePoolsImplementation(
        address payable[] calldata pools,
        bytes calldata initData
    ) external virtual {
        require(poolProxyAdmin == msg.sender, "ACOPoolFactory::onlyPoolProxyAdmin");
        for (uint256 i = 0; i < pools.length; ++i) {
            ACOProxy(pools[i]).setImplementation(acoPoolImplementation, initData);
        }
    }

    function transferPoolProxyAdmin(address newPoolProxyAdmin, address payable[] calldata pools) external virtual {
        require(poolProxyAdmin == msg.sender, "ACOPoolFactory::onlyPoolProxyAdmin");
        for (uint256 i = 0; i < pools.length; ++i) {
            ACOProxy(pools[i]).transferProxyAdmin(newPoolProxyAdmin);
        }
    }
    
    function createAcoPool(
        address underlying, 
        address strikeAsset, 
        bool isCall,
        uint256 baseVolatility,
        address poolAdmin,
        address strategy,
        bool isPrivate,
        IACOPool2.PoolAcoPermissionConfigV2 calldata acoPermissionConfig
    ) external virtual returns(address) {
        require((operators[address(0)] || operators[msg.sender]), "ACOPoolFactory2::createAcoPool: Only authorized operators");
        return _createAcoPool(IACOPool2.InitData(
            acoFactory,
            lendingPool,
            underlying, 
            strikeAsset,
            isCall,
            baseVolatility,
            poolAdmin,
            strategy,
            isPrivate,
            ++poolCount,
            acoPermissionConfig,
            IACOPool2.PoolProtocolConfig(
                lendingPoolReferral,
                acoPoolWithdrawOpenPositionPenalty,
                acoPoolUnderlyingPriceAdjustPercentage,
                acoPoolFee,
                acoPoolMaximumOpenAco,
                acoPoolFeeDestination,
                assetConverterHelper
            )
        ));
    }

    function newAcoPool(
        address underlying, 
        address strikeAsset, 
        bool isCall,
        uint256 baseVolatility,
        address poolAdmin,
        IACOPool2.PoolAcoPermissionConfigV2 calldata acoPermissionConfig
    ) external virtual returns(address) {
        require(strikeAssets[strikeAsset], "ACOPoolFactory2::newAcoPool: Invalid strike asset");
        require(IACOAssetConverterHelper(assetConverterHelper).hasAggregator(underlying, strikeAsset), "ACOPoolFactory2::newAcoPool: Invalid pair");
        
        return _createAcoPool(IACOPool2.InitData(
            acoFactory,
            lendingPool,
            underlying, 
            strikeAsset,
            isCall,
            baseVolatility,
            poolAdmin,
            defaultStrategy,
            true,
            ++poolCount,
            acoPermissionConfig,
            IACOPool2.PoolProtocolConfig(
                lendingPoolReferral,
                acoPoolWithdrawOpenPositionPenalty,
                acoPoolUnderlyingPriceAdjustPercentage,
                acoPoolFee,
                acoPoolMaximumOpenAco,
                acoPoolFeeDestination,
                assetConverterHelper
            )
        ));
    }
    
    function withdrawStuckAssetOnAcoPool(address asset, address destination, address[] calldata acoPools) onlyPoolAdmin external virtual {
		_withdrawStuckAssetOnAcoPool(asset, destination, acoPools);
	}

    function setStrategyOnAcoPool(address strategy, address[] calldata acoPools) onlyPoolAdmin external virtual {
        _setStrategyOnAcoPool(strategy, acoPools);
    }
    
	function setValidAcoCreatorOnAcoPool(address acoCreator, bool permission, address[] calldata acoPools) onlyPoolAdmin external virtual {
		_setValidAcoCreatorOnAcoPool(acoCreator, permission, acoPools);
	}
	
	function setForbiddenAcoCreatorOnAcoPool(address acoCreator, bool status, address[] calldata acoPools) onlyPoolAdmin external virtual {
		_setForbiddenAcoCreatorOnAcoPool(acoCreator, status, acoPools);
	}
	
	function setProtocolConfigOnAcoPool(
        uint16 lendingPoolReferralCode,
        uint256 withdrawOpenPositionPenalty,
        uint256 underlyingPriceAdjustPercentage,
        uint256 fee,
        uint256 maximumOpenAco,
        address feeDestination,
        address assetConverter, 
        address[] calldata acoPools
    ) onlyPoolAdmin external virtual {
        IACOPool2.PoolProtocolConfig memory config = IACOPool2.PoolProtocolConfig(lendingPoolReferralCode, withdrawOpenPositionPenalty, underlyingPriceAdjustPercentage, fee, maximumOpenAco, feeDestination, assetConverter);
        for (uint256 i = 0; i < acoPools.length; ++i) {
            IACOPool2(acoPools[i]).setProtocolConfig(config);
        }
    }

    function startLendingPoolOnAcoPool(
        address newLendingPool,
        address[] calldata acoPools
    ) onlyPoolAdmin external virtual {
        for (uint256 i = 0; i < acoPools.length; ++i) {
            IACOPool2(acoPools[i]).startLendingPool(newLendingPool);
        }
    }

    function _setFactoryAdmin(address newFactoryAdmin) internal virtual {
        require(newFactoryAdmin != address(0), "ACOPoolFactory::_setFactoryAdmin: Invalid factory admin");
        emit SetFactoryAdmin(factoryAdmin, newFactoryAdmin);
        factoryAdmin = newFactoryAdmin;
    }

    function _setAcoPoolImplementation(address newAcoPoolImplementation) internal virtual {
        require(Address.isContract(newAcoPoolImplementation), "ACOPoolFactory::_setAcoPoolImplementation: Invalid ACO pool implementation");
        emit SetAcoPoolImplementation(acoPoolImplementation, newAcoPoolImplementation);
        acoPoolImplementation = newAcoPoolImplementation;
    }

    function _setAcoFactory(address newAcoFactory) internal virtual {
        require(Address.isContract(newAcoFactory), "ACOPoolFactory::_setAcoFactory: Invalid ACO factory");
        emit SetAcoFactory(acoFactory, newAcoFactory);
        acoFactory = newAcoFactory;
    }

    function _setAssetConverterHelper(address newAssetConverterHelper) internal virtual {
        require(Address.isContract(newAssetConverterHelper), "ACOPoolFactory::_setAssetConverterHelper: Invalid asset converter helper");
        emit SetAssetConverterHelper(assetConverterHelper, newAssetConverterHelper);
        assetConverterHelper = newAssetConverterHelper;
    }
    
    function _setAcoPoolFee(uint256 newAcoPoolFee) internal virtual {
        emit SetAcoPoolFee(acoPoolFee, newAcoPoolFee);
        acoPoolFee = newAcoPoolFee;
    }
    
    function _setAcoPoolFeeDestination(address newAcoPoolFeeDestination) internal virtual {
        require(newAcoPoolFeeDestination != address(0), "ACOFactory::_setAcoPoolFeeDestination: Invalid ACO Pool fee destination");
        emit SetAcoPoolFeeDestination(acoPoolFeeDestination, newAcoPoolFeeDestination);
        acoPoolFeeDestination = newAcoPoolFeeDestination;
    }
    
    function _setAcoPoolWithdrawOpenPositionPenalty(uint256 newWithdrawOpenPositionPenalty) internal virtual {
        emit SetAcoPoolWithdrawOpenPositionPenalty(acoPoolWithdrawOpenPositionPenalty, newWithdrawOpenPositionPenalty);
        acoPoolWithdrawOpenPositionPenalty = newWithdrawOpenPositionPenalty;
    }
    
    function _setAcoPoolUnderlyingPriceAdjustPercentage(uint256 newUnderlyingPriceAdjustPercentage) internal virtual {
        emit SetAcoPoolUnderlyingPriceAdjustPercentage(acoPoolUnderlyingPriceAdjustPercentage, newUnderlyingPriceAdjustPercentage);
        acoPoolUnderlyingPriceAdjustPercentage = newUnderlyingPriceAdjustPercentage;
    }
    
    function _setAcoPoolMaximumOpenAco(uint256 newMaximumOpenAco) internal virtual {
        emit SetAcoPoolMaximumOpenAco(acoPoolMaximumOpenAco, newMaximumOpenAco);
        acoPoolMaximumOpenAco = newMaximumOpenAco;
    }
    
    function _setAcoPoolLendingPool(address newLendingPool) internal virtual {
        emit SetAcoPoolLendingPool(lendingPool, newLendingPool);
        lendingPool = newLendingPool;
    }
    
    function _setAcoPoolLendingPoolReferral(uint16 newLendingPoolReferral) internal virtual {
        emit SetAcoPoolLendingPoolReferral(lendingPoolReferral, newLendingPoolReferral);
        lendingPoolReferral = newLendingPoolReferral;
    }
    
    function _setAcoPoolPermission(address poolAdmin, bool newPermission) internal virtual {
        emit SetAcoPoolPermission(poolAdmin, poolAdminPermission[poolAdmin], newPermission);
        poolAdminPermission[poolAdmin] = newPermission;
    }
    
    function _setAcoPoolStrategyPermission(address strategy, bool newPermission) internal virtual {
        require(Address.isContract(strategy), "ACOPoolFactory::_setAcoPoolStrategy: Invalid strategy");
        emit SetStrategyPermission(strategy, strategyPermitted[strategy], newPermission);
        strategyPermitted[strategy] = newPermission;
    }
    
    function _setOperator(address operator, bool newPermission) internal virtual {
        emit SetOperator(operator, operators[operator], newPermission);
        operators[operator] = newPermission;
    }
    
    function _setPoolProxyAdmin(address newPoolProxyAdmin) internal virtual {
        require(newPoolProxyAdmin != address(0), "ACOPoolFactory::_setPoolProxyAdmin: Invalid pool proxy admin");
        emit SetPoolProxyAdmin(poolProxyAdmin, newPoolProxyAdmin);
        poolProxyAdmin = newPoolProxyAdmin;
    }
    
    function _setPoolDefaultStrategy(address newDefaultStrategy) internal virtual {
        _validateStrategy(newDefaultStrategy);
        emit SetDefaultStrategy(defaultStrategy, newDefaultStrategy);
        defaultStrategy = newDefaultStrategy;
    }

    function _setStrikeAssetPermission(address strikeAsset, bool newPermission) internal virtual {
        emit SetStrikeAssetPermission(strikeAsset, strikeAssets[strikeAsset], newPermission);
        strikeAssets[strikeAsset] = newPermission;
    }
    
    function _setForbiddenAcoCreator(address acoCreator, bool newStatus) internal virtual {
        bool previousStatus = false;
        uint256 size = acoForbiddenCreators.length;
        for (uint256 i = size; i > 0; --i) {
            if (acoForbiddenCreators[i - 1] == acoCreator) {
                previousStatus = true;
                if (!newStatus) {
                    if (i < size) {
                        acoForbiddenCreators[i - 1] = acoForbiddenCreators[(size - 1)];
                    }
                    acoForbiddenCreators.pop();
                }
                break;
            }
        }
        if (newStatus && !previousStatus) {
            acoForbiddenCreators.push(acoCreator);
        }
        emit SetForbiddenAcoCreator(acoCreator, previousStatus, newStatus);
    }

    function _setForbiddenAcoCreatorOnAcoPool(address acoCreator, bool status, address[] memory acoPools) internal virtual {
        for (uint256 i = 0; i < acoPools.length; ++i) {
            IACOPool2(acoPools[i]).setForbiddenAcoCreator(acoCreator, status);
        }
    }
    
    function _setAuthorizedAcoCreator(address acoCreator, bool newPermission) internal virtual {
        bool previousPermission = false;
        uint256 size = acoAuthorizedCreators.length;
        for (uint256 i = size; i > 0; --i) {
            if (acoAuthorizedCreators[i - 1] == acoCreator) {
                previousPermission = true;
                if (!newPermission) {
                    if (i < size) {
                        acoAuthorizedCreators[i - 1] = acoAuthorizedCreators[(size - 1)];
                    }
                    acoAuthorizedCreators.pop();
                }
                break;
            }
        }
        if (newPermission && !previousPermission) {
            acoAuthorizedCreators.push(acoCreator);
        }
        emit SetAuthorizedAcoCreator(acoCreator, previousPermission, newPermission);
    }
    
    function _validateStrategy(address strategy) view internal virtual {
        require(strategyPermitted[strategy], "ACOPoolFactory::_validateStrategy: Invalid strategy");
    }
    
    function _setStrategyOnAcoPool(address strategy, address[] memory acoPools) internal virtual {
        _validateStrategy(strategy);
        for (uint256 i = 0; i < acoPools.length; ++i) {
            IACOPool2(acoPools[i]).setStrategy(strategy);
        }
    }
    
    function _setValidAcoCreatorOnAcoPool(address acoCreator, bool permission, address[] memory acoPools) internal virtual {
        for (uint256 i = 0; i < acoPools.length; ++i) {
            IACOPool2(acoPools[i]).setValidAcoCreator(acoCreator, permission);
        }
    }
    
    function _withdrawStuckAssetOnAcoPool(address asset, address destination, address[] memory acoPools) internal virtual {
        for (uint256 i = 0; i < acoPools.length; ++i) {
            IACOPool2(acoPools[i]).withdrawStuckToken(asset, destination);
        }
    }

    function _deployAcoPool(IACOPool2.InitData memory initData) internal virtual returns(address) {
        ACOProxy proxy = new ACOProxy(address(this), acoPoolImplementation, abi.encodeWithSelector(IACOPool2.init.selector, initData));
        return address(proxy);
    }

    function _createAcoPool(IACOPool2.InitData memory initData) internal virtual returns(address) {
        address acoPool  = _deployAcoPool(initData);
        acoPoolBasicData[acoPool] = ACOPoolBasicData(initData.underlying, initData.strikeAsset, initData.isCall);
        creators[acoPool] = msg.sender;
        for (uint256 i = 0; i < acoAuthorizedCreators.length; ++i) {
            IACOPool2(acoPool).setValidAcoCreator(acoAuthorizedCreators[i], true);
        }
        for (uint256 j = 0; j < acoForbiddenCreators.length; ++j) {
            IACOPool2(acoPool).setForbiddenAcoCreator(acoForbiddenCreators[j], true);
        }
        emit NewAcoPool(initData.underlying, initData.strikeAsset, initData.isCall, acoPool, acoPoolImplementation);
        return acoPool;
    }	
}