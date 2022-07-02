// SPDX-License-Identifier: GPL-3.0-only

pragma solidity >=0.8.12;

import "../interfaces/ISwapRouter.sol";
import "hardhat/console.sol";

contract UniswapV3ExactInputCodec {
    function decodeCalldata(bytes calldata _swap)
        external
        pure
        returns (ISwapRouter.ExactInputParams memory params)
    {
        params = abi.decode((_swap[4:]), (ISwapRouter.ExactInputParams));
    }

    function encodeCalldataWithOverride(
        bytes calldata _data,
        uint256 _amountInOverride,
        address _receiverOverride
    ) external pure returns (bytes memory swapCalldata) {
        bytes4 selector = bytes4(_data);
        ISwapRouter.ExactInputParams memory data = abi.decode(
            (_data[4:]),
            (ISwapRouter.ExactInputParams)
        );
        data.amountIn = _amountInOverride;
        data.recipient = _receiverOverride;
        return abi.encodeWithSelector(selector, data);
    }

    // basically a bytes' version of byteN[from:to] execpt it copies
    function copySubBytes(
        bytes memory data,
        uint256 from,
        uint256 to
    ) private pure returns (bytes memory ret) {
        require(to <= data.length, "index overflow");
        uint256 len = to - from;
        ret = new bytes(len);
        for (uint256 i = 0; i < len; i++) {
            ret[i] = data[i + from];
        }
    }
}
