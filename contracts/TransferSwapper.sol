// SPDX-License-Identifier: GPL-3.0-only

pragma solidity >=0.8.12;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@uniswap/lib/contracts/libraries/TransferHelper.sol";
import "./interfaces/IUniswapV2Router02.sol";
import "./interfaces/ISwapRouter.sol";
import "./interfaces/IWETH.sol";

import "./interfaces/IStargateRouter.sol";
import "./interfaces/IStargateReceiver.sol";

import "hardhat/console.sol";

contract TransferSwapper is Ownable, ReentrancyGuard, IStargateReceiver {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    event SrcChainSwap(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint16 dstChainId,
        address router,
        address crossRouter
    );

    event DstChainSwap(
        address bridgedToken,
        uint256 bridgedAmount,
        address tokenOut,
        uint256 amountOut
    );

    struct TransferDescription {
        address payable to;
        bool nativeIn;
        bool nativeOut;
        uint256 amountIn;
        address tokenIn;
        address tokenOut;
        bool srcSkipSwap;
        bool dstSkipSwap;
        address dstTokenOut;
        address router;
        address dstRouter;
        uint16 srcChainId;
        uint16 dstChainId;
    }

    struct Request {
        bytes swap;
        address dstRouter;
        bool nativeOut;
    }

    address public nativeWrap;
    uint256 public bridgeSlippage;
    uint256 public dstGasForSwapCall;
    uint256 public dstGasForNoSwapCall;

    IStargateRouter public stargateRouter;

    mapping(uint16 => uint256) public quotePoolIds; // chainId => woofi_quote_token_pool_id
    mapping(uint16 => address) public crossRouters; // dstChainId => router

    constructor(address _nativeWrap, address _stargateRouter) {
        nativeWrap = _nativeWrap;
        stargateRouter = IStargateRouter(_stargateRouter);

        bridgeSlippage = 100;

        dstGasForSwapCall = 360000;
        dstGasForNoSwapCall = 80000;

        // mainnet
        // usdc: 1, usdt: 2, busd: 5
        quotePoolIds[1] = 1; // ethereum: usdc
        quotePoolIds[2] = 2; // BSC: usdt
        quotePoolIds[6] = 1; // Avalanche: usdc
        quotePoolIds[9] = 1; // Polygon: usdc
        quotePoolIds[10] = 1; // Arbitrum: usdc
        quotePoolIds[11] = 1; // Optimism: usdc
        quotePoolIds[12] = 1; // Fantom: usdc

        // testnet
        quotePoolIds[10001] = 1; // rinkeby: usdc
        quotePoolIds[10002] = 2; // BSC Testnet ​usdt
        quotePoolIds[10009] = 1; // Mumbai: usdc
    }

    function setCrossChainRouter(uint16 _chainId, address _crossRouter)
        external
        onlyOwner
    {
        require(_crossRouter != address(0), "CrossChainRouter: !crossRouter");
        crossRouters[_chainId] = _crossRouter;
    }

    // todo まずブリッジが動くかどうか
    function transferWithSwap(
        TransferDescription calldata _transferDesc,
        bytes calldata _srcSwapDesc,
        bytes calldata _dstSwapDesc
    ) external payable nonReentrant {
        // uint256 gasValue = msg.value;
        // executeBridge(_transferDesc, _dstSwapDesc);
        uint256 sumAmtOut;
        if (_transferDesc.srcSkipSwap) {
            IERC20(_transferDesc.tokenIn).safeTransferFrom(
                msg.sender,
                address(this),
                _transferDesc.amountIn
            );
            sumAmtOut = IERC20(_transferDesc.tokenOut).balanceOf(address(this));
        } else {
            sumAmtOut = executeSwap(_transferDesc, _srcSwapDesc);
        }
        require(
            sumAmtOut <=
                IERC20(_transferDesc.tokenOut).balanceOf(address(this)),
            "!bridgeAmount"
        );
        IERC20(_transferDesc.tokenOut).safeIncreaseAllowance(
            address(stargateRouter),
            sumAmtOut
        );

        require(_transferDesc.to != address(0), "to_ZERO_ADDR"); // NOTE: double check it

        uint16 dstChainId = _transferDesc.dstChainId;
        uint16 srcChainId = _transferDesc.srcChainId;
        bytes memory dstSwapDesc = abi.encode(
            _dstSwapDesc,
            _transferDesc.dstRouter,
            _transferDesc.nativeOut
        );

        bytes memory dstCrossRouter = abi.encodePacked(
            crossRouters[dstChainId]
        );
        uint256 minBridgeAmount = sumAmtOut
            .mul(uint256(10000).sub(bridgeSlippage))
            .div(10000);
        uint256 dstGas = _transferDesc.dstSkipSwap
            ? dstGasForNoSwapCall
            : dstGasForSwapCall;
        uint256 gasValue = msg.value;

        stargateRouter.swap{value: gasValue}(
            dstChainId, // dst chain id
            quotePoolIds[srcChainId], // quote token's pool id on dst chain
            quotePoolIds[dstChainId], // quote token's pool id on src chain
            payable(msg.sender), // rebate address
            sumAmtOut, // swap amount on src chain
            minBridgeAmount, // min received amount on dst chain
            IStargateRouter.lzTxObj(dstGas, 0, "0x"), // config: dstGas, dstNativeToken, dstNativeTokenToAddress
            dstCrossRouter, // smart contract to call on dst chain
            dstSwapDesc // payload to piggyback
        );
        // emit SrcChainSwap(_transferDesc.tokenIn, _transferDesc.tokenOut, )
    }

    function executeBridge(
        TransferDescription calldata _transferDesc,
        bytes calldata _dstSwapDesc
    ) internal {
        uint256 amountIn = _transferDesc.amountIn;
        uint256 gasValue = msg.value;
        uint16 dstChainId = _transferDesc.dstChainId;
        uint16 srcChainId = _transferDesc.srcChainId;
        bytes memory dstSwapDesc = abi.encode(
            _dstSwapDesc,
            _transferDesc.dstRouter,
            _transferDesc.nativeOut
        );

        TransferHelper.safeTransferFrom(
            _transferDesc.tokenIn,
            msg.sender,
            address(this),
            amountIn
        );

        bytes memory dstCrossRouter = abi.encodePacked(
            crossRouters[dstChainId]
        );
        uint256 minBridgeAmount = amountIn
            .mul(uint256(10000).sub(bridgeSlippage))
            .div(10000);
        uint256 dstGas = _transferDesc.dstSkipSwap
            ? dstGasForNoSwapCall
            : dstGasForSwapCall;
        TransferHelper.safeApprove(
            _transferDesc.tokenIn,
            address(stargateRouter),
            amountIn
        );

        stargateRouter.swap{value: gasValue}(
            dstChainId, // dst chain id
            quotePoolIds[srcChainId], // quote token's pool id on dst chain
            quotePoolIds[dstChainId], // quote token's pool id on src chain
            payable(msg.sender), // rebate address
            amountIn, // swap amount on src chain
            minBridgeAmount, // min received amount on dst chain
            IStargateRouter.lzTxObj(dstGas, 0, "0x"), // config: dstGas, dstNativeToken, dstNativeTokenToAddress
            dstCrossRouter, // smart contract to call on dst chain
            dstSwapDesc // payload to piggyback
        );
    }

    function executeSwap(
        TransferDescription calldata _transferDesc,
        bytes calldata _srcSwapDesc
    ) internal returns (uint256 sumAmtOut) {
        if (_transferDesc.nativeIn) {
            require(_transferDesc.tokenIn == nativeWrap, "tkin no nativeWrap");
            require(msg.value >= _transferDesc.amountIn, "insfcnt amt"); // insufficient amount
            IWETH(nativeWrap).deposit{value: _transferDesc.amountIn}();
        } else {
            IERC20(_transferDesc.tokenIn).safeTransferFrom(
                msg.sender,
                address(this),
                _transferDesc.amountIn
            );
        }
        IERC20(_transferDesc.tokenIn).safeIncreaseAllowance(
            _transferDesc.router,
            _transferDesc.amountIn
        );

        uint256 beforeAmount = IERC20(_transferDesc.tokenOut).balanceOf(
            address(this)
        );
        if (
            _transferDesc.srcChainId == 9 || _transferDesc.srcChainId == 10001
        ) {
            ISwapRouter router = ISwapRouter(_transferDesc.router);
            ISwapRouter.ExactInputParams memory params = decodeCalldataUniV3(
                _srcSwapDesc
            );
            router.exactInput(params);
        } else if (
            _transferDesc.srcChainId == 2 || _transferDesc.srcChainId == 10002
        ) {
            IUniswapV2Router02 router = IUniswapV2Router02(
                _transferDesc.router
            );
            (
                uint256 amountIn,
                uint256 amountOutMin,
                address[] memory path,
                address to,
                uint256 deadline
            ) = decodeCalldataUniV2(_srcSwapDesc);
            router.swapExactTokensForTokens(
                amountIn,
                amountOutMin,
                path,
                address(this),
                deadline
            );
        } else {
            revert("unsupported chain");
        }
        uint256 afterAmount = IERC20(_transferDesc.tokenOut).balanceOf(
            address(this)
        );
        sumAmtOut += afterAmount - beforeAmount;
    }

    function quoteLayerZeroFee(
        uint16 dstChainId,
        address to,
        bool swapSkip,
        bytes calldata _dstSwapDesc,
        address dstRouter,
        bool nativeOut
    ) external view returns (uint256, uint256) {
        bytes memory toAddress = abi.encodePacked(to);

        bytes memory dstSwapDesc = abi.encode(
            _dstSwapDesc,
            dstRouter,
            nativeOut
        );

        uint256 dstGas = swapSkip ? dstGasForNoSwapCall : dstGasForSwapCall;
        return
            stargateRouter.quoteLayerZeroFee(
                dstChainId,
                1, // https://stargateprotocol.gitbook.io/stargate/developers/function-types
                toAddress,
                dstSwapDesc,
                IStargateRouter.lzTxObj(dstGas, 0, "0x")
            );
    }

    function sgReceive(
        uint16 _chainId,
        bytes memory _srcAddress,
        uint256 _nonce,
        address _token,
        uint256 amountLD,
        bytes memory _payload
    ) external override {
        require(
            msg.sender == address(stargateRouter),
            "only stargate router can call sgReceive!"
        );

        (bytes memory dstSwapDesc, address dstRouter, bool nativeOut) = abi
            .decode((_payload), (bytes, address, bool));

        if (dstRouter == address(0)) {
            IERC20(_token).safeTransferFrom(
                address(this),
                msg.sender,
                amountLD
            );
            emit DstChainSwap(_token, amountLD, _token, amountLD);
            return;
        }
        (uint256 sumAmtOut, address to) = executeDstSwap(
            dstRouter,
            dstSwapDesc,
            _chainId,
            _token,
            amountLD,
            nativeOut
        );
        emit DstChainSwap(_token, amountLD, nativeWrap, sumAmtOut);
        // if (nativeOut) {
        //     IWETH(nativeWrap).withdraw(sumAmtOut);
        //     TransferHelper.safeApprove(_token, dstRouter, amountLD);
        //     TransferHelper.safeTransferETH(to, sumAmtOut);
        //     emit DstChainSwap(_token, amountLD, nativeWrap, sumAmtOut);
        // } else {
        //     emit DstChainSwap(_token, amountLD, _token, sumAmtOut);
        // }
    }

    function executeDstSwap(
        address dstRouter,
        bytes memory dstSwapDesc,
        uint16 _chainId,
        address _token,
        uint256 amountLD,
        bool nativeOut
    ) internal returns (uint256 sumAmtOut, address toAddress) {
        TransferHelper.safeApprove(_token, dstRouter, amountLD);

        uint256 sumAmtOut;

        if (_chainId == 10002 || _chainId == 2) {
            ISwapRouter router = ISwapRouter(dstRouter);
            ISwapRouter.ExactInputParams memory params = decodeCalldataUniV3(
                dstSwapDesc
            );
            params.amountIn = amountLD;
            toAddress = params.recipient;
            if(nativeOut) {
                params.recipient = address(this);
            }
            sumAmtOut = router.exactInput(params);

            if(nativeOut) {
                IWETH(nativeWrap).withdraw(sumAmtOut);
                TransferHelper.safeTransferETH(toAddress, sumAmtOut);
            }
        } else if (_chainId == 10001 || _chainId == 9) {
            IUniswapV2Router02 router = IUniswapV2Router02(dstRouter);
            (
                uint256 amountIn,
                uint256 amountOutMin,
                address[] memory path,
                address to,
                uint256 deadline
            ) = decodeCalldataUniV2(dstSwapDesc);
            if (nativeOut) {
                uint256[] memory amounts = router.swapExactTokensForETH(
                    amountLD,
                    amountOutMin,
                    path,
                    to,
                    deadline
                );
                sumAmtOut = amounts[1];
            } else {
                uint256[] memory amounts = router.swapExactTokensForTokens(
                    amountLD,
                    amountOutMin,
                    path,
                    to,
                    deadline
                );
                sumAmtOut = amounts[1];
            }
            toAddress = to;
        }
    }

    function refundToken(address _token) external payable {
        uint256 balance = IERC20(_token).balanceOf(address(this));
        require(balance < 0, "no refundable token");
        IERC20(_token).safeIncreaseAllowance(address(this), balance);

        IERC20(_token).safeTransferFrom(address(this), msg.sender, balance);
    }

    function decodeCalldataUniV3(bytes memory _swap)
        internal
        pure
        returns (ISwapRouter.ExactInputParams memory params)
    {
        params = abi.decode((_swap), (ISwapRouter.ExactInputParams));
    }

    function decodeCalldataUniV2(bytes memory _swap)
        internal
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
            (_swap),
            (uint256, uint256, address[], address, uint256)
        );
    }

    function _encodeRequestMessage(
        TransferDescription memory _desc,
        bytes calldata _swap
    ) private pure returns (bytes memory message) {
        message = abi.encode(
            Request({
                swap: _swap,
                dstRouter: _desc.dstRouter,
                nativeOut: _desc.nativeOut
            })
        );
    }
}
