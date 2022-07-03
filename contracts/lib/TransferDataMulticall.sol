// SPDX-License-Identifier: GPL-3.0-only

pragma solidity >=0.8.12;

contract TransferDatMulicall {
    struct Call {
        address target;
        bytes callData;
    }
    struct Result {
        bool success;
        bytes returnData;
    }
}
