// SPDX-License-Identifier: None
pragma solidity 0.8.4;

import "./ERC20.sol";
import "../libs/Address.sol";
import "../libs/ACONameFormatter.sol";


contract ACOToken is ERC20 {
    using SafeMath for uint256;
    using Address for address;

    struct TokenCollateralized {
        uint256 amount;
        uint256 index;
    }

    event CollateralDeposit(address indexed account, uint256 amount);
    event CollateralWithdraw(address indexed account, address indexed recipient, uint256 amount, uint256 fee);
    event Assigned(address indexed from, address indexed to, uint256 paidAmount, uint256 tokenAmount);
    event TransferCollateralOwnership(address indexed from, address indexed to, uint256 tokenCollateralizedAmount);


    address public underlying;
    address public strikeAsset;
    address payable public feeDestination;
    bool public isCall;
    uint256 public strikePrice;
    uint256 public expiryTime;
    uint256 public totalCollateral;
    uint256 public acoFee;
    string public underlyingSymbol;
    string public strikeAssetSymbol;
    uint8 public underlyingDecimals;
    uint8 public strikeAssetDecimals;
    uint256 public maxExercisedAccounts;

    uint256 internal underlyingPrecision;
    
    mapping(address => TokenCollateralized) internal tokenData;
    
    address[] internal _collateralOwners;

    bool internal _notEntered;
    bytes4 internal _transferSelector;
    bytes4 internal _transferFromSelector;
    
    modifier notExpired() {
        require(_notExpired(), "ACOToken::Expired");
        _;
    }

    modifier nonReentrant() {
        require(_notEntered, "ACOToken::Reentry");
        _notEntered = false;
        _;
        _notEntered = true;
    }

    function init(
        address _underlying,
        address _strikeAsset,
        bool _isCall,
        uint256 _strikePrice,
        uint256 _expiryTime,
        uint256 _acoFee,
        address payable _feeDestination,
        uint256 _maxExercisedAccounts
    ) public {
        require(underlying == address(0) && strikeAsset == address(0) && strikePrice == 0, "ACOToken::init: Already initialized");
        
        require(_expiryTime > block.timestamp, "ACOToken::init: Invalid expiry");
        require(_strikePrice > 0, "ACOToken::init: Invalid strike price");
        require(_underlying != _strikeAsset, "ACOToken::init: Same assets");
        require(_acoFee <= 500, "ACOToken::init: Invalid ACO fee"); // Maximum is 0.5%
        require(_isEther(_underlying) || _underlying.isContract(), "ACOToken::init: Invalid underlying");
        require(_isEther(_strikeAsset) || _strikeAsset.isContract(), "ACOToken::init: Invalid strike asset");
        require(_maxExercisedAccounts >= 25 && _maxExercisedAccounts <= 150, "ACOToken::init: Invalid number to max exercised accounts");
        
        underlying = _underlying;
        strikeAsset = _strikeAsset;
        isCall = _isCall;
        strikePrice = _strikePrice;
        expiryTime = _expiryTime;
        acoFee = _acoFee;
        feeDestination = _feeDestination;
        maxExercisedAccounts = _maxExercisedAccounts;
        underlyingDecimals = _getAssetDecimals(_underlying);
        require(underlyingDecimals < 78, "ACOToken::init: Invalid underlying decimals");
        strikeAssetDecimals = _getAssetDecimals(_strikeAsset);
        underlyingSymbol = _getAssetSymbol(_underlying);
        strikeAssetSymbol = _getAssetSymbol(_strikeAsset);
        underlyingPrecision = 10 ** uint256(underlyingDecimals);

        _transferSelector = bytes4(keccak256(bytes("transfer(address,uint256)")));
        _transferFromSelector = bytes4(keccak256(bytes("transferFrom(address,address,uint256)")));
        _notEntered = true;
    }

    receive() external payable {
        revert();
    }

    function name() public view override returns(string memory) {
        return _name();
    }

    function symbol() public view override returns(string memory) {
        return _name();
    }

    function decimals() public view override returns(uint8) {
        return underlyingDecimals;
    }
    
    function currentCollateral(address account) public view returns(uint256) {
        return getCollateralAmount(currentCollateralizedTokens(account));
    }
    
    function unassignableCollateral(address account) public view returns(uint256) {
        return getCollateralAmount(unassignableTokens(account));
    }
    
    function assignableCollateral(address account) public view returns(uint256) {
        return getCollateralAmount(assignableTokens(account));
    }
    
    function currentCollateralizedTokens(address account) public view returns(uint256) {
        return tokenData[account].amount;
    }
    
    function unassignableTokens(address account) public view returns(uint256) {
        if (balanceOf(account) > tokenData[account].amount || !_notExpired()) {
            return tokenData[account].amount;
        } else {
            return balanceOf(account);
        }
    }
    
    function assignableTokens(address account) public view returns(uint256) {
        if (_notExpired()) {
            return _getAssignableAmount(account);
        } else {
            return 0;
        }
    }
    
    function getCollateralAmount(uint256 tokenAmount) public view returns(uint256) {
        if (isCall) {
            return tokenAmount;
        } else if (tokenAmount > 0) {
            return _getTokenStrikePriceRelation(tokenAmount);
        } else {
            return 0;
        }
    }
    
    function getTokenAmount(uint256 collateralAmount) public view returns(uint256) {
        if (isCall) {
            return collateralAmount;
        } else if (collateralAmount > 0) {
            return collateralAmount.mul(underlyingPrecision).div(strikePrice);
        } else {
            return 0;
        }
    }

    function numberOfAccountsWithCollateral() public view returns(uint256) {
        return _collateralOwners.length;
    }
    
    function getBaseExerciseData(uint256 tokenAmount) public view returns(address, uint256) {
        if (isCall) {
            return (strikeAsset, _getTokenStrikePriceRelation(tokenAmount)); 
        } else {
            return (underlying, tokenAmount);
        }
    }
    
    function getCollateralOnExercise(uint256 tokenAmount) public view returns(uint256, uint256) {
        uint256 collateralAmount = getCollateralAmount(tokenAmount);
        uint256 fee = collateralAmount.mul(acoFee).div(100000);
        collateralAmount = collateralAmount.sub(fee);
        return (collateralAmount, fee);
    }
    
    function collateral() public view returns(address) {
        if (isCall) {
            return underlying;
        } else {
            return strikeAsset;
        }
    }
    
    function mintPayable() external payable returns(uint256) {
        require(_isEther(collateral()), "ACOToken::mintPayable: Invalid call");
        return _mintToken(msg.sender, msg.value);
    }
    
    function mintToPayable(address account) external payable returns(uint256) {
        require(_isEther(collateral()), "ACOToken::mintToPayable: Invalid call");
       return _mintToken(account, msg.value);
    }
    
    function mint(uint256 collateralAmount) external returns(uint256) {
        address _collateral = collateral();
        require(!_isEther(_collateral), "ACOToken::mint: Invalid call");
        
        _transferFromERC20(_collateral, msg.sender, address(this), collateralAmount);
        return _mintToken(msg.sender, collateralAmount);
    }
    
    function mintTo(address account, uint256 collateralAmount) external returns(uint256) {
        address _collateral = collateral();
        require(!_isEther(_collateral), "ACOToken::mintTo: Invalid call");
        
        _transferFromERC20(_collateral, msg.sender, address(this), collateralAmount);
        return _mintToken(account, collateralAmount);
    }
    
    function burn(uint256 tokenAmount) external returns(uint256) {
        return _burn(msg.sender, tokenAmount);
    }
    
    function burnFrom(address account, uint256 tokenAmount) external returns(uint256) {
        return _burn(account, tokenAmount);
    }
    
    function redeem() external returns(uint256) {
        return _redeem(msg.sender);
    }
    
    function redeemFrom(address account) external returns(uint256) {
        require(tokenData[account].amount <= allowance(account, msg.sender), "ACOToken::redeemFrom: Allowance too low");
        return _redeem(account);
    }
    
    function exercise(uint256 tokenAmount, uint256 salt) external payable returns(uint256) {
        return _exercise(msg.sender, tokenAmount, salt);
    }
    
    function exerciseFrom(address account, uint256 tokenAmount, uint256 salt) external payable returns(uint256) {
        return _exercise(account, tokenAmount, salt);
    }
    
    function exerciseAccounts(uint256 tokenAmount, address[] calldata accounts) external payable returns(uint256) {
        return _exerciseFromAccounts(msg.sender, tokenAmount, accounts);
    }

    function transferCollateralOwnership(address recipient, uint256 tokenCollateralizedAmount) external {
        require(recipient != address(0), "ACOToken::transferCollateralOwnership: Invalid recipient");
        require(tokenCollateralizedAmount > 0, "ACOToken::transferCollateralOwnership: Invalid amount");

        TokenCollateralized storage senderData = tokenData[msg.sender];
        senderData.amount = senderData.amount.sub(tokenCollateralizedAmount);

        _removeCollateralDataIfNecessary(msg.sender);

        TokenCollateralized storage recipientData = tokenData[recipient];
        if (_hasCollateral(recipientData)) {
            recipientData.amount = recipientData.amount.add(tokenCollateralizedAmount);
        } else {
            tokenData[recipient] = TokenCollateralized(tokenCollateralizedAmount, _collateralOwners.length);
            _collateralOwners.push(recipient);
        }

        emit TransferCollateralOwnership(msg.sender, recipient, tokenCollateralizedAmount);
    }
    
    function exerciseAccountsFrom(address account, uint256 tokenAmount, address[] calldata accounts) external payable returns(uint256) {
        return _exerciseFromAccounts(account, tokenAmount, accounts);
    }
    
    function _redeemCollateral(address account, uint256 tokenAmount) internal returns(uint256) {
        require(_accountHasCollateral(account), "ACOToken::_redeemCollateral: No collateral available");
        require(tokenAmount > 0, "ACOToken::_redeemCollateral: Invalid token amount");
        
        TokenCollateralized storage data = tokenData[account];
        data.amount = data.amount.sub(tokenAmount);
        
        _removeCollateralDataIfNecessary(account);
        
        return _transferCollateral(account, getCollateralAmount(tokenAmount), 0);
    }
    
    function _mintToken(address account, uint256 collateralAmount) nonReentrant notExpired internal returns(uint256) {
        require(collateralAmount > 0, "ACOToken::_mintToken: Invalid collateral amount");
        
        if (!_accountHasCollateral(account)) {
            tokenData[account].index = _collateralOwners.length;
            _collateralOwners.push(account);
        }
        
        uint256 tokenAmount = getTokenAmount(collateralAmount);
        require(tokenAmount != 0, "ACOToken::_mintToken: Invalid token amount");
        tokenData[account].amount = tokenData[account].amount.add(tokenAmount);
        
        totalCollateral = totalCollateral.add(collateralAmount);
        
        emit CollateralDeposit(account, collateralAmount);
        
        super._mintAction(msg.sender, tokenAmount);
        return tokenAmount;
    }
    
    function _transferCollateral(address account, uint256 collateralAmount, uint256 fee) internal returns(uint256) {
        
        totalCollateral = totalCollateral.sub(collateralAmount.add(fee));
        
        address _collateral = collateral();
        if (_isEther(_collateral)) {
            _transferEth(msg.sender, collateralAmount);
            if (fee > 0) {
                _transferEth(feeDestination, fee);
            }
        } else {
            _transferERC20(_collateral, msg.sender, collateralAmount);
            if (fee > 0) {
                _transferERC20(_collateral, feeDestination, fee);
            }
        }
        
        emit CollateralWithdraw(account, msg.sender, collateralAmount, fee);
        return collateralAmount;
    }
    
    function _exercise(address account, uint256 tokenAmount, uint256 salt) nonReentrant internal returns(uint256) {
        _validateAndBurn(account, tokenAmount, maxExercisedAccounts);
         _exerciseOwners(account, tokenAmount, salt);
        (uint256 collateralAmount, uint256 fee) = getCollateralOnExercise(tokenAmount);
        return _transferCollateral(account, collateralAmount, fee);
    }
    
    function _exerciseFromAccounts(address account, uint256 tokenAmount, address[] memory accounts) nonReentrant internal returns(uint256) {
        _validateAndBurn(account, tokenAmount, accounts.length);
        _exerciseAccounts(account, tokenAmount, accounts);
        (uint256 collateralAmount, uint256 fee) = getCollateralOnExercise(tokenAmount);
        return _transferCollateral(account, collateralAmount, fee);
    }
    
    function _exerciseOwners(address exerciseAccount, uint256 tokenAmount, uint256 salt) internal {
        uint256 accountsExercised = 0;
        uint256 start = salt.mod(_collateralOwners.length);
        uint256 index = start;
        uint256 count = 0;
        while (tokenAmount > 0 && count < _collateralOwners.length) {
            
            uint256 remainingAmount = _exerciseAccount(_collateralOwners[index], tokenAmount, exerciseAccount);
            if (remainingAmount < tokenAmount) {
                accountsExercised++;
                require(accountsExercised < maxExercisedAccounts || remainingAmount == 0, "ACOToken::_exerciseOwners: Too many accounts to exercise");
            }
            tokenAmount = remainingAmount;
            
            ++index;
            if (index == _collateralOwners.length) {
                index = 0;
            }
            ++count;
        }
        require(tokenAmount == 0, "ACOToken::_exerciseOwners: Invalid remaining amount");
        
        uint256 indexOnModifyIteration;
        bool shouldModifyIteration = false;
        if (index == 0) {
            index = _collateralOwners.length;
        } else if (index <= start) {
            indexOnModifyIteration = index - 1;
            shouldModifyIteration = true;
            index = _collateralOwners.length;
        }
            
        for (uint256 i = 0; i < count; ++i) {
            --index;
            if (shouldModifyIteration && index < start) {
                index = indexOnModifyIteration;
                shouldModifyIteration = false;
            }
            _removeCollateralDataIfNecessary(_collateralOwners[index]);
        }
    }
    
    function _exerciseAccounts(address exerciseAccount, uint256 tokenAmount, address[] memory accounts) internal {
        for (uint256 i = 0; i < accounts.length; ++i) {
            if (tokenAmount == 0) {
                break;
            }
            tokenAmount = _exerciseAccount(accounts[i], tokenAmount, exerciseAccount);
            _removeCollateralDataIfNecessary(accounts[i]);
        }
        require(tokenAmount == 0, "ACOToken::_exerciseAccounts: Invalid remaining amount");
    }
    
    function _exerciseAccount(address account, uint256 tokenAmount, address exerciseAccount) internal returns(uint256) {
        uint256 available = _getAssignableAmount(account);
        if (available > 0) {
            
            TokenCollateralized storage data = tokenData[account];
            uint256 valueToTransfer;
            if (available < tokenAmount) {
                valueToTransfer = available;
                tokenAmount = tokenAmount.sub(available);
            } else {
                valueToTransfer = tokenAmount;
                tokenAmount = 0;
            }
            
            (address exerciseAsset, uint256 amount) = getBaseExerciseData(valueToTransfer);
            // To guarantee that the minter will be paid.
            amount = amount.add(1);
            
            data.amount = data.amount.sub(valueToTransfer); 
            
            if (_isEther(exerciseAsset)) {
                _transferEth(account, amount);
            } else {
                _transferERC20(exerciseAsset, account, amount);
            }
            emit Assigned(account, exerciseAccount, amount, valueToTransfer);
        }
        return tokenAmount;
    }
    
    function _validateAndBurn(address account, uint256 tokenAmount, uint256 maximumNumberOfAccounts) notExpired internal {
        require(tokenAmount > 0, "ACOToken::_validateAndBurn: Invalid token amount");
        
        // Whether an account has deposited collateral it only can exercise the extra amount of unassignable tokens.
        if (_accountHasCollateral(account)) {
            require(tokenAmount <= balanceOf(account).sub(tokenData[account].amount), "ACOToken::_validateAndBurn: Token amount not available"); 
        }
        
        _callBurn(account, tokenAmount);
        
        (address exerciseAsset, uint256 expectedAmount) = getBaseExerciseData(tokenAmount);
        expectedAmount = expectedAmount.add(maximumNumberOfAccounts);

        if (_isEther(exerciseAsset)) {
            require(msg.value == expectedAmount, "ACOToken::_validateAndBurn: Invalid ether amount");
        } else {
            require(msg.value == 0, "ACOToken::_validateAndBurn: No ether expected");
            _transferFromERC20(exerciseAsset, msg.sender, address(this), expectedAmount);
        }
    }
    
    function _getTokenStrikePriceRelation(uint256 tokenAmount) internal view returns(uint256) {
        return tokenAmount.mul(strikePrice).div(underlyingPrecision);
    }
    
    function _redeem(address account) nonReentrant internal returns(uint256) {
        require(!_notExpired(), "ACOToken::_redeem: Token not expired yet");
        
        uint256 collateralAmount = _redeemCollateral(account, tokenData[account].amount);
        super._burnAction(account, balanceOf(account));
        return collateralAmount;
    }
    
    function _burn(address account, uint256 tokenAmount) nonReentrant notExpired internal returns(uint256) {
        uint256 collateralAmount = _redeemCollateral(account, tokenAmount);
        _callBurn(account, tokenAmount);
        return collateralAmount;
    }
    
    function _callBurn(address account, uint256 tokenAmount) internal {
        if (account == msg.sender) {
            super._burnAction(account, tokenAmount);
        } else {
            super._burnFrom(account, tokenAmount);
        }
    }
    
    function _getAssignableAmount(address account) internal view returns(uint256) {
        if (tokenData[account].amount > balanceOf(account)) {
            return tokenData[account].amount.sub(balanceOf(account));
        } else {
            return 0;
        }
    }
    
    function _removeCollateralDataIfNecessary(address account) internal {
        TokenCollateralized storage data = tokenData[account];
        if (!_hasCollateral(data)) {
            uint256 lastIndex = _collateralOwners.length - 1;
            if (lastIndex != data.index) {
                address last = _collateralOwners[lastIndex];
                tokenData[last].index = data.index;
                _collateralOwners[data.index] = last;
            }
            _collateralOwners.pop();
            delete tokenData[account];
        }
    }
    
    function _notExpired() internal view returns(bool) {
        return block.timestamp < expiryTime;
    }
    
    function _accountHasCollateral(address account) internal view returns(bool) {
        return _hasCollateral(tokenData[account]);
    }
       
    function _hasCollateral(TokenCollateralized storage data) internal view returns(bool) {
        return data.amount > 0;
    }
    
    function _isEther(address _address) internal pure returns(bool) {
        return _address == address(0);
    } 
    
    function _name() internal view returns(string memory) {
        return string(abi.encodePacked(
            "ACO ",
            underlyingSymbol,
            "-",
            ACONameFormatter.formatNumber(strikePrice, strikeAssetDecimals),
            strikeAssetSymbol,
            "-",
            ACONameFormatter.formatType(isCall),
            "-",
            ACONameFormatter.formatTime(expiryTime)
        ));
    }
    
    function _getAssetDecimals(address asset) internal view returns(uint8) {
        if (_isEther(asset)) {
            return uint8(18);
        } else {
            (bool success, bytes memory returndata) = asset.staticcall(abi.encodeWithSignature("decimals()"));
            require(success, "ACOToken::_getAssetDecimals: Invalid asset decimals");
            return abi.decode(returndata, (uint8));
        }
    }
    
    function _getAssetSymbol(address asset) internal view returns(string memory) {
        if (_isEther(asset)) {
            return "ETH";
        } else {
            (bool success, bytes memory returndata) = asset.staticcall(abi.encodeWithSignature("symbol()"));
            require(success, "ACOToken::_getAssetSymbol: Invalid asset symbol");
            return abi.decode(returndata, (string));
        }
    }
    
    function _transferEth(address to, uint256 amount) internal {
        (bool success,) = to.call{value:amount}(new bytes(0));
        require(success, "ACOToken::_transferEth:error on send eth");
    }

    function _transferERC20(address token, address recipient, uint256 amount) internal {
        (bool success, bytes memory returndata) = token.call(abi.encodeWithSelector(_transferSelector, recipient, amount));
        require(success && (returndata.length == 0 || abi.decode(returndata, (bool))), "ACOToken::_transferERC20");
    }
    
     function _transferFromERC20(address token, address sender, address recipient, uint256 amount) internal {
        (bool success, bytes memory returndata) = token.call(abi.encodeWithSelector(_transferFromSelector, sender, recipient, amount));
        require(success && (returndata.length == 0 || abi.decode(returndata, (bool))), "ACOToken::_transferFromERC20");
    }
}
