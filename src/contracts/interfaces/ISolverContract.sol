//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.22;

import "../types/SolverCallTypes.sol";

interface ISolverContract {
    function atlasSolverCall(
        address sender,
        address bidRecipient,
        address bidToken,
        uint256 bidAmount,
        bytes calldata solverOpData,
        bytes calldata extraReturnData
    )
        external
        payable
        returns (bool, bytes memory);
}
