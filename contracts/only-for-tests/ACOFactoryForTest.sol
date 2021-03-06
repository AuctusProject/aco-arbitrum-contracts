// SPDX-License-Identifier: None
pragma solidity 0.8.4;

import "../core/ACOFactory.sol";

contract ACOFactoryForTest is ACOFactory {
    
    event SetExtraData(uint256 lastValue, uint256 newValue);
    
    mapping(uint256 => uint256) public extraDataMap;
    uint256 public extraData;
    
    function _setAcoFee(uint256 newAcoFee) internal override {
        require(newAcoFee > 100, "ACOFactoryForTest::_setAcoFee: Invalid fee");
        super._setAcoFee(newAcoFee);
    }
    
    function createAcoToken(
        address underlying, 
        address strikeAsset, 
        bool isCall,
        uint256 strikePrice, 
        uint256 expiryTime,
        uint256 maxExercisedAccounts
    ) external override returns(address) {
        address acoToken = _deployAcoToken(underlying, strikeAsset, isCall, strikePrice, expiryTime, maxExercisedAccounts);
        emit NewAcoTokenData(underlying, strikeAsset, isCall, strikePrice, expiryTime, acoToken, acoTokenImplementation, msg.sender);  
		return acoToken;
    }
    
    function setExtraData(uint256 newValue) onlyFactoryAdmin external virtual {
        _setExtraData(newValue);
    }
    
    function _setExtraData(uint256 newValue) internal virtual {
        emit SetExtraData(extraDataMap[extraData], newValue);
        extraData++;
        extraDataMap[extraData] = newValue;
    }
}