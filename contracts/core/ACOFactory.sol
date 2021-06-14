// SPDX-License-Identifier: None
pragma solidity 0.8.4;

import "../libs/Address.sol";
import "../interfaces/IACOToken.sol";

contract ACOFactory {
    
    uint256 public constant MAX_EXPIRATION = 157852800;
    uint256 public constant DEFAULT_MAX_EXERCISED_ACCOUNTS = 100;
    uint256 public constant DEFAULT_MAX_SIGNIFICANT_DIGITS = 3;
    
    event SetFactoryAdmin(address indexed previousFactoryAdmin, address indexed newFactoryAdmin);
    event SetAcoTokenImplementation(address indexed previousAcoTokenImplementation, address indexed newAcoTokenImplementation);
    event SetAcoFee(uint256 indexed previousAcoFee, uint256 indexed newAcoFee);
    event SetAcoFeeDestination(address indexed previousAcoFeeDestination, address indexed newAcoFeeDestination);
    event SetOperator(address indexed operator, bool indexed previousPermission, bool indexed newPermission);
    event NewAcoTokenData(address indexed underlying, address indexed strikeAsset, bool indexed isCall, uint256 strikePrice, uint256 expiryTime, address acoToken, address acoTokenImplementation, address creator);
    event SetStrikeAssetPermission(address indexed strikeAsset, bool indexed previousPermission, bool indexed newPermission);
    event SetAssetSpecificData(address indexed asset, uint256 previousMaxSignificantDigits, uint256 previousMaxExercisedAccounts, uint256 newMaxSignificantDigits, uint256 newMaxExercisedAccounts);

    struct ACOTokenData {
        address underlying;
        address strikeAsset;
        bool isCall;
        uint256 strikePrice;
        uint256 expiryTime;
    }

    struct AssetData {
        uint256 maxSignificantDigits;
        uint256 maxExercisedAccounts;
    }
    
    uint256 public acoFee;
    address public factoryAdmin;
    address public acoTokenImplementation;
    address public acoFeeDestination;
	
    mapping(address => bool) public operators;
    mapping(address => bool) public strikeAssets;
    mapping(address => address) public creators;
    mapping(bytes32 => address) public acoHashes;
    mapping(address => ACOTokenData) public acoTokenData;
    mapping(address => AssetData) public assetsSpecificData;
    
    modifier onlyFactoryAdmin() {
        require(msg.sender == factoryAdmin, "ACOFactory::onlyFactoryAdmin");
        _;
    }

    function init(address _factoryAdmin, address _acoTokenImplementation, uint256 _acoFee, address _acoFeeDestination) public {
        require(factoryAdmin == address(0) && acoTokenImplementation == address(0), "ACOFactory::init: Contract already initialized.");
        
        _setFactoryAdmin(_factoryAdmin);
        _setAcoTokenImplementation(_acoTokenImplementation);
        _setAcoFee(_acoFee);
        _setAcoFeeDestination(_acoFeeDestination);
        _setOperator(_factoryAdmin, true);
    }

    receive() external payable virtual {
        revert();
    }
    
    function getAcoToken(
        address underlying, 
        address strikeAsset, 
        bool isCall,
        uint256 strikePrice, 
        uint256 expiryTime
    ) external virtual view returns(address) {
        bytes32 acoHash = _getAcoHash(underlying, strikeAsset, isCall, strikePrice, expiryTime);
        return acoHashes[acoHash];
    }
   
    function setFactoryAdmin(address newFactoryAdmin) onlyFactoryAdmin external virtual {
        _setFactoryAdmin(newFactoryAdmin);
    }
   
    function setAcoTokenImplementation(address newAcoTokenImplementation) onlyFactoryAdmin external virtual {
        _setAcoTokenImplementation(newAcoTokenImplementation);
    }
    
    function setAcoFee(uint256 newAcoFee) onlyFactoryAdmin external virtual {
        _setAcoFee(newAcoFee);
    }
    
    function setAcoFeeDestination(address newAcoFeeDestination) onlyFactoryAdmin external virtual {
        _setAcoFeeDestination(newAcoFeeDestination);
    }
    
    function setOperator(address operator, bool newPermission) onlyFactoryAdmin external virtual {
        _setOperator(operator, newPermission);
    }
    
    function setStrikeAssetPermission(address strikeAsset, bool newPermission) onlyFactoryAdmin external virtual {
        _setStrikeAssetPermission(strikeAsset, newPermission);
    }
    
    function setAssetSpecificData(
        address asset, 
        uint256 maxSignificantDigits,
        uint256 maxExercisedAccounts
    ) onlyFactoryAdmin external virtual {
        _setAssetSpecificData(asset, maxSignificantDigits, maxExercisedAccounts);
    }
    
    function createAcoToken(
        address underlying, 
        address strikeAsset, 
        bool isCall,
        uint256 strikePrice, 
        uint256 expiryTime,
        uint256 maxExercisedAccounts
    ) external virtual returns(address) {
        require(operators[msg.sender], "ACOFactory::createAcoToken: Only authorized operators");
        return _createAcoToken(underlying, strikeAsset, isCall, strikePrice, expiryTime, maxExercisedAccounts);
    }

    function newAcoToken(
        address underlying, 
        address strikeAsset, 
        bool isCall,
        uint256 strikePrice, 
        uint256 expiryTime
    ) external virtual returns(address) {
        require(strikeAssets[strikeAsset], "ACOFactory::newAcoToken: Invalid strike asset");
        require(_isValidTime(expiryTime), "ACOFactory::newAcoToken: Invalid expiry time");
        
        AssetData storage strikeAssetData = assetsSpecificData[strikeAsset];
        uint256 maxSignificantDigits = _getMaxSignificantDigits(strikeAssetData);
        require(_isValidStrikePrice(strikePrice, maxSignificantDigits), "ACOFactory::newAcoToken: Invalid strike price");
        
        uint256 maxExercisedAccounts = _getMaxExercisedAccounts(underlying, isCall, strikeAssetData);
        return _createAcoToken(underlying, strikeAsset, isCall, strikePrice, expiryTime, maxExercisedAccounts);
    }
    
    function _setFactoryAdmin(address newFactoryAdmin) internal virtual {
        require(newFactoryAdmin != address(0), "ACOFactory::_setFactoryAdmin: Invalid factory admin");
        emit SetFactoryAdmin(factoryAdmin, newFactoryAdmin);
        factoryAdmin = newFactoryAdmin;
    }
    
    function _setAcoTokenImplementation(address newAcoTokenImplementation) internal virtual {
        require(Address.isContract(newAcoTokenImplementation), "ACOFactory::_setAcoTokenImplementation: Invalid ACO token implementation");
        emit SetAcoTokenImplementation(acoTokenImplementation, newAcoTokenImplementation);
        acoTokenImplementation = newAcoTokenImplementation;
    }
    
    function _setAcoFee(uint256 newAcoFee) internal virtual {
        emit SetAcoFee(acoFee, newAcoFee);
        acoFee = newAcoFee;
    }
    
    function _setAcoFeeDestination(address newAcoFeeDestination) internal virtual {
        require(newAcoFeeDestination != address(0), "ACOFactory::_setAcoFeeDestination: Invalid ACO fee destination");
        emit SetAcoFeeDestination(acoFeeDestination, newAcoFeeDestination);
        acoFeeDestination = newAcoFeeDestination;
    }
    
    function _setOperator(address operator, bool newPermission) internal virtual {
        emit SetOperator(operator, operators[operator], newPermission);
        operators[operator] = newPermission;
    }

    function _setStrikeAssetPermission(address strikeAsset, bool newPermission) internal virtual {
        emit SetStrikeAssetPermission(strikeAsset, strikeAssets[strikeAsset], newPermission);
        strikeAssets[strikeAsset] = newPermission;
    }

    function _setAssetSpecificData(
        address asset, 
        uint256 maxSignificantDigits,
        uint256 maxExercisedAccounts
    ) internal virtual {
        AssetData storage previousData = assetsSpecificData[asset];
        emit SetAssetSpecificData(asset, previousData.maxSignificantDigits, previousData.maxExercisedAccounts, maxSignificantDigits, maxExercisedAccounts);
        assetsSpecificData[asset] = AssetData(maxSignificantDigits, maxExercisedAccounts);
    }
    
    function _getAcoHash(
        address underlying, 
        address strikeAsset, 
        bool isCall,
        uint256 strikePrice, 
        uint256 expiryTime
    ) internal pure virtual returns(bytes32) {
        return keccak256(abi.encodePacked(underlying, strikeAsset, isCall, strikePrice, expiryTime));
    }

    function _getMaxExercisedAccounts(
        address underlying, 
        bool isCall,
        AssetData storage strikeAssetData
    ) internal view virtual returns(uint256) {
        if (isCall) {
            AssetData storage underlyingData = assetsSpecificData[underlying];
            if (underlyingData.maxExercisedAccounts > 0) {
                return underlyingData.maxExercisedAccounts;
            }
        } else if (strikeAssetData.maxExercisedAccounts > 0) {
            return strikeAssetData.maxExercisedAccounts;
        }
        return DEFAULT_MAX_EXERCISED_ACCOUNTS;
    }

    function _getMaxSignificantDigits(AssetData storage strikeAssetData) internal view virtual returns(uint256) {
        if (strikeAssetData.maxSignificantDigits > 0) {
            return strikeAssetData.maxSignificantDigits;
        }
        return DEFAULT_MAX_SIGNIFICANT_DIGITS;
    }

    function _isValidTime(uint256 expiryTime) internal pure virtual returns(bool) {
        return ((expiryTime % 60) == 0 && ((expiryTime % 3600) / 60) == 0 && ((expiryTime % 86400) / 3600) == 8);
    }

    function _isValidStrikePrice(uint256 strikePrice, uint256 maxSignificantDigits) internal pure virtual returns(bool) {
        uint256 i = strikePrice;
        uint256 len;
        while (i != 0) {
            len++;
            i /= 10;
        }
        if (len <= maxSignificantDigits) {
            return true;
        }
        uint256 diff = len - maxSignificantDigits;
        if (diff < 78) {
            uint256 nonSignificant = 10 ** diff;
            return ((strikePrice / nonSignificant) * nonSignificant) == strikePrice;
        }
        return false;
    }

    function _createAcoToken(
        address underlying, 
        address strikeAsset, 
        bool isCall,
        uint256 strikePrice, 
        uint256 expiryTime,
        uint256 maxExercisedAccounts
    ) internal virtual returns(address) {
        require(expiryTime <= (block.timestamp + MAX_EXPIRATION), "ACOFactory::_createAcoToken: Invalid expiry time");
        
        bytes32 acoHash = _getAcoHash(underlying, strikeAsset, isCall, strikePrice, expiryTime);
        require(acoHashes[acoHash] == address(0), "ACOFactory::_createAcoToken: ACO already exists");
        
        address acoToken = _deployAcoToken(underlying, strikeAsset, isCall, strikePrice, expiryTime, maxExercisedAccounts);
        acoTokenData[acoToken] = ACOTokenData(underlying, strikeAsset, isCall, strikePrice, expiryTime);
        creators[acoToken] = msg.sender;
        acoHashes[acoHash] = acoToken;
        emit NewAcoTokenData(underlying, strikeAsset, isCall, strikePrice, expiryTime, acoToken, acoTokenImplementation, msg.sender);
        return acoToken;
    }
    
    function _deployAcoToken(
        address underlying, 
        address strikeAsset, 
        bool isCall,
        uint256 strikePrice, 
        uint256 expiryTime,
        uint256 maxExercisedAccounts
    ) internal virtual returns(address) {
        bytes20 implentationBytes = bytes20(acoTokenImplementation);
        address proxy;
        assembly {
            let clone := mload(0x40)
            mstore(clone, 0x3d602d80600a3d3981f3363d3d373d3d3d363d73000000000000000000000000)
            mstore(add(clone, 0x14), implentationBytes)
            mstore(add(clone, 0x28), 0x5af43d82803e903d91602b57fd5bf30000000000000000000000000000000000)
            proxy := create(0, clone, 0x37)
        }
        IACOToken(proxy).init(underlying, strikeAsset, isCall, strikePrice, expiryTime, acoFee, payable(acoFeeDestination), maxExercisedAccounts);
        return proxy;
    }
}