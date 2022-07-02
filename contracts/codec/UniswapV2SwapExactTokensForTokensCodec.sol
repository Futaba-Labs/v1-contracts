// SPDX-License-Identifier: GPL-3.0-only

pragma solidity >=0.8.12;

contract UniswapV2SwapExactTokensForTokensCodec {
    function decodeCalldata(bytes calldata _swap)
        external
        pure
        returns (
            uint256 amountIn,
            uint256 amountOutMin,
            address[] memory path,
            address to,
            uint256 deadline
        )
    {
        (amountIn, amountOutMin, path, to, deadline) = abi.decode(
            (_swap[4:]),
            (uint256, uint256, address[], address, uint256)
        );
    }

    function encodeCalldataWithOverride(
        bytes calldata _data,
        uint256 _amountInOverride,
        address _receiverOverride
    ) external pure returns (bytes memory swapCalldata) {
        bytes4 selector = bytes4(_data);
        (, uint256 amountOutMin, address[] memory path, , uint256 ddl) = abi
            .decode(
                (_data[4:]),
                (uint256, uint256, address[], address, uint256)
            );
        return
            abi.encodeWithSelector(
                selector,
                _amountInOverride,
                amountOutMin,
                path,
                _receiverOverride,
                ddl
            );
    }
}
