// SPDX-License-Identifier: None
pragma solidity 0.8.4;

import "../core/ERC20.sol";

/**
 * @title ERC20ForTest
 * @dev The contract is only for test purpose.
 */
contract ERC20ForTest is ERC20 {
    
    string private _name;
    string private _symbol;
    uint8 private _decimals;
    
    constructor(
        string memory _erc20name, 
        string memory _erc20symbol, 
        uint8 _erc20decimals, 
        uint256 _erc20totalSupply
    ) {
        _name = _erc20name;
        _symbol = _erc20symbol;
        _decimals = _erc20decimals;
        super._mintAction(msg.sender, _erc20totalSupply);
    }
    
    function name() public view override returns(string memory) {
        return _name;    
    }
    
    function symbol() public view override returns(string memory) {
        return _symbol;    
    }
    
    function decimals() public view override returns(uint8) {
        return _decimals;
    }

    function mint(address account, uint256 amount) external {
        super._mintAction(account, amount);
    }

    function burnFrom(address account, uint256 amount) external {
        super._burnFrom(account, amount);
    }
}