// SPDX-License-Identifier: None
pragma solidity 0.8.4;

library ACOAssetHelper {
    uint256 internal constant MAX_UINT = 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff;

    function _isEther(address _address) internal pure returns(bool) {
        return _address == address(0);
    }

    function _callApproveERC20(address token, address spender, uint256 amount) internal {
        (bool success, bytes memory returndata) = token.call(abi.encodeWithSelector(0x095ea7b3, spender, amount));
        require(success && (returndata.length == 0 || abi.decode(returndata, (bool))), "approve");
    }

    function _callTransferERC20(address token, address recipient, uint256 amount) internal {
        (bool success, bytes memory returndata) = token.call(abi.encodeWithSelector(0xa9059cbb, recipient, amount));
        require(success && (returndata.length == 0 || abi.decode(returndata, (bool))), "transfer");
    }

     function _callTransferFromERC20(address token, address sender, address recipient, uint256 amount) internal {
        (bool success, bytes memory returndata) = token.call(abi.encodeWithSelector(0x23b872dd, sender, recipient, amount));
        require(success && (returndata.length == 0 || abi.decode(returndata, (bool))), "transferFrom");
    }

    function _getAssetSymbol(address asset) internal view returns(string memory) {
        if (_isEther(asset)) {
            return "ETH";
        } else {
            (bool success, bytes memory returndata) = asset.staticcall(abi.encodeWithSelector(0x95d89b41));
            require(success, "symbol");
            return abi.decode(returndata, (string));
        }
    }

    function _getAssetDecimals(address asset) internal view returns(uint8) {
        if (_isEther(asset)) {
            return uint8(18);
        } else {
            (bool success, bytes memory returndata) = asset.staticcall(abi.encodeWithSelector(0x313ce567));
            require(success, "decimals");
            return abi.decode(returndata, (uint8));
        }
    }

    function _getAssetName(address asset) internal view returns(string memory) {
        if (_isEther(asset)) {
            return "Ethereum";
        } else {
            (bool success, bytes memory returndata) = asset.staticcall(abi.encodeWithSelector(0x06fdde03));
            require(success, "name");
            return abi.decode(returndata, (string));
        }
    }

    function _getAssetBalanceOf(address asset, address account) internal view returns(uint256) {
        if (_isEther(asset)) {
            return account.balance;
        } else {
            (bool success, bytes memory returndata) = asset.staticcall(abi.encodeWithSelector(0x70a08231, account));
            require(success, "balanceOf");
            return abi.decode(returndata, (uint256));
        }
    }

    function _getAssetAllowance(address asset, address owner, address spender) internal view returns(uint256) {
        if (_isEther(asset)) {
            return 0;
        } else {
            (bool success, bytes memory returndata) = asset.staticcall(abi.encodeWithSelector(0xdd62ed3e, owner, spender));
            require(success, "allowance");
            return abi.decode(returndata, (uint256));
        }
    }

    function _transferAsset(address asset, address to, uint256 amount) internal {
        if (_isEther(asset)) {
            (bool success,) = to.call{value:amount}(new bytes(0));
            require(success, "send");
        } else {
            _callTransferERC20(asset, to, amount);
        }
    }

    function _receiveAsset(address asset, uint256 amount) internal {
        if (_isEther(asset)) {
            require(msg.value == amount, "Invalid ETH amount");
        } else {
            require(msg.value == 0, "No payable");
            _callTransferFromERC20(asset, msg.sender, address(this), amount);
        }
    }

    function _setAssetInfinityApprove(address asset, address owner, address spender, uint256 amount) internal {
        if (_getAssetAllowance(asset, owner, spender) < amount) {
            _callApproveERC20(asset, spender, MAX_UINT);
        }
    }
}