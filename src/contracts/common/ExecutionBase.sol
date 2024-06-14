//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.22;

import { IPermit69 } from "src/contracts/interfaces/IPermit69.sol";
import { ISafetyLocks } from "src/contracts/interfaces/ISafetyLocks.sol";
import { IEscrow } from "src/contracts/interfaces/IEscrow.sol";
import { SafeTransferLib, ERC20 } from "solmate/utils/SafeTransferLib.sol";
import { ExecutionPhase } from "src/contracts/types/LockTypes.sol";
import { SAFE_USER_TRANSFER, SAFE_DAPP_TRANSFER } from "src/contracts/libraries/SafetyBits.sol";
import { AtlasErrors } from "src/contracts/types/AtlasErrors.sol";

contract Base {
    address public immutable ATLAS;
    address public immutable SOURCE;

    constructor(address _atlas) {
        ATLAS = _atlas;
        SOURCE = address(this);
    }

    // These functions only work inside of the ExecutionEnvironment (mimic)
    // via delegatecall, but can be added to DAppControl as funcs that
    // can be used during DAppControl's delegated funcs

    modifier onlyAtlasEnvironment(ExecutionPhase phase, uint8 acceptableDepths) {
        _onlyAtlasEnvironment(phase, acceptableDepths);
        _;
    }

    function _onlyAtlasEnvironment(ExecutionPhase phase, uint8 acceptableDepths) internal view {
        if (address(this) == SOURCE) {
            revert AtlasErrors.MustBeDelegatecalled();
        }
        if (msg.sender != ATLAS) {
            revert AtlasErrors.OnlyAtlas();
        }

        // This check can be spoofed by the DAppControl module authors
        // Users implicitly trust the DAppControl contract and inherit
        // the risk of any delegatecalls it makes.
        if (uint8(phase) != _phase()) {
            revert AtlasErrors.WrongPhase();
        }
        if (1 << _depth() & acceptableDepths == 0) {
            revert AtlasErrors.WrongDepth();
        }
    }

    function _forward(bytes memory data) internal pure returns (bytes memory) {
        return bytes.concat(data, _firstSet(), _secondSet());
    }

    function _firstSet() internal pure returns (bytes memory data) {
        data = abi.encodePacked(
            _addressPointer(),
            _solverSuccessful(),
            _paymentsSuccessful(),
            _callIndex(),
            _callCount(),
            _phase(),
            uint8(0),
            _solverOutcome(),
            _bidFind(),
            _simulation(),
            _depth() + 1
        );
    }

    function _secondSet() internal pure returns (bytes memory data) {
        data = abi.encodePacked(_user(), _control(), _config());
    }

    /// @notice Extracts and returns the CallConfig of the current DAppControl contract, from calldata.
    /// @return config The CallConfig of the current DAppControl contract, in uint32 form.
    function _config() internal pure returns (uint32 config) {
        assembly {
            config := shr(224, calldataload(sub(calldatasize(), 4)))
        }
    }

    /// @notice Extracts and returns the address of the current DAppControl contract, from calldata.
    /// @return control The address of the current DAppControl contract.
    function _control() internal pure returns (address control) {
        assembly {
            control := shr(96, calldataload(sub(calldatasize(), 24)))
        }
    }

    /// @notice Extracts and returns the address of the user of the current metacall tx, from calldata.
    /// @return user The address of the user of the current metacall tx.
    function _user() internal pure returns (address user) {
        assembly {
            user := shr(96, calldataload(sub(calldatasize(), 44)))
        }
    }

    /// @notice Extracts and returns the call depth within the current metacall tx, from calldata.
    /// @dev The call depth starts at 1 with the first call of each step in the metacall, from Atlas to the Execution
    /// Environment, and is incremented with each call/delegatecall within that step.
    /// @return callDepth The call depth of the current step in the current metacall tx.
    function _depth() internal pure returns (uint8 callDepth) {
        assembly {
            callDepth := shr(248, calldataload(sub(calldatasize(), 45)))
        }
    }

    /// @notice Extracts and returns the boolean indicating whether the current metacall tx is a simulation or not, from
    /// calldata.
    /// @return simulation The boolean indicating whether the current metacall tx is a simulation or not.
    function _simulation() internal pure returns (bool simulation) {
        assembly {
            simulation := shr(248, calldataload(sub(calldatasize(), 46)))
        }
    }

    /// @notice Extracts and returns the boolean indicating whether the current metacall tx uses on-chain bid-finding,
    /// or not, from calldata.
    /// @return bidFind The boolean indicating whether the current metacall tx uses on-chain bid-finding, or not.
    function _bidFind() internal pure returns (bool bidFind) {
        assembly {
            bidFind := shr(248, calldataload(sub(calldatasize(), 47)))
        }
    }

    /// @notice Extracts and returns the solver outcome bitmap in its current status during a metacall tx, from
    /// calldata.
    /// @return solverOutcome The solver outcome bitmap in its current status, in uint24 form.
    function _solverOutcome() internal pure returns (uint24 solverOutcome) {
        assembly {
            solverOutcome := shr(232, calldataload(sub(calldatasize(), 50)))
        }
    }

    /// @notice Extracts and returns the lock state bitmap of the current metacall tx, from calldata.
    /// @return phase The lock state bitmap of the current metacall tx, in uint16 form.
    function _phase() internal pure returns (uint8 phase) {
        assembly {
            phase := shr(248, calldataload(sub(calldatasize(), 51)))
        }
    }

    /// @notice Extracts and returns the call count of the current metacall tx, from calldata.
    /// @dev Call count is calculated as number of solverOps + 3. This represents 1 call for preOps, userOp, and postOps
    /// each, then 1 call for each of the solverOps.
    /// @return callCount The call count of the current metacall tx.
    function _callCount() internal pure returns (uint8 callCount) {
        assembly {
            callCount := shr(248, calldataload(sub(calldatasize(), 53)))
        }
    }

    /// @notice Extracts and returns the call index of the current metacall tx, from calldata.
    /// @dev Call index is the index of the current call within the total calls (see `_callCount()`) of a metacall tx.
    /// I.e. preOpsCall has an index of 0, userOp has an index of 1, the first solverOp has an index of 2, subsequent
    /// solverOps have indices of 3, 4, 5, etc, and postOpsCall has an index of `callCount - 1`.
    /// @return callIndex The call index of the current metacall tx.
    function _callIndex() internal pure returns (uint8 callIndex) {
        assembly {
            callIndex := shr(248, calldataload(sub(calldatasize(), 54)))
        }
    }

    /// @notice Extracts and returns the boolean indicating whether the payments were successful after the allocateValue
    /// step in the current metacall tx, from calldata.
    /// @return paymentsSuccessful The boolean indicating whether the payments were successful after the allocateValue
    /// step in the current metacall tx.
    function _paymentsSuccessful() internal pure returns (bool paymentsSuccessful) {
        assembly {
            paymentsSuccessful := shr(248, calldataload(sub(calldatasize(), 55)))
        }
    }

    /// @notice Extracts and returns the boolean indicating whether the winning solverOp was executed successfully in
    /// the current metacall tx, from calldata.
    /// @return solverSuccessful The boolean indicating whether the winning solverOp was executed successfully in the
    /// current metacall tx.
    function _solverSuccessful() internal pure returns (bool solverSuccessful) {
        assembly {
            solverSuccessful := shr(248, calldataload(sub(calldatasize(), 56)))
        }
    }

    /// @notice Extracts and returns the current value of the addressPointer of the current metacall tx, from calldata.
    /// @dev The addressPointer is either the address of the current DAppControl contract (in preOps and userOp steps),
    /// the current solverOp.solver address (during solverOps steps), or the winning solverOp.from address (during
    /// allocateValue step).
    /// @return addressPointer The current value of the addressPointer of the current metacall tx.
    function _addressPointer() internal pure returns (address addressPointer) {
        assembly {
            addressPointer := shr(96, calldataload(sub(calldatasize(), 76)))
        }
    }

    /// @notice Returns the address of the currently active Execution Environment, if any.
    /// @return activeEnvironment The address of the currently active Execution Environment.
    function _activeEnvironment() internal view returns (address activeEnvironment) {
        activeEnvironment = ISafetyLocks(ATLAS).activeEnvironment();
    }
}

// ExecutionBase is inherited by DAppControl. It inherits Base to as a common root contract shared between
// ExecutionEnvironment and DAppControl. ExecutionBase then adds utility functions which make it easier for custom
// DAppControls to interact with Atlas.
contract ExecutionBase is Base {
    constructor(address _atlas) Base(_atlas) { }

    /// @notice Deposits local funds from this Execution Environment, to the transient Atlas balance. These funds go
    /// towards the bundler, with any surplus going to the Solver.
    /// @param amt The amount of funds to deposit.
    function _contribute(uint256 amt) internal {
        if (amt > address(this).balance) revert AtlasErrors.InsufficientLocalFunds();

        IEscrow(ATLAS).contribute{ value: amt }();
    }

    /// @notice Borrows funds from the transient Atlas balance that will be repaid by the Solver or this Execution
    /// Environment via `_contribute()`
    /// @param amt The amount of funds to borrow.
    function _borrow(uint256 amt) internal {
        IEscrow(ATLAS).borrow(amt);
    }

    /// @notice Transfers ERC20 tokens from the user of the current metacall tx, via Atlas, to a specified destination.
    /// @dev This will only succeed if Atlas is in a phase included in `SAFE_USER_TRANSFER`. See SafetyBits.sol.
    /// @param token The address of the ERC20 token contract.
    /// @param destination The address to which the tokens will be transferred.
    /// @param amount The amount of tokens to transfer.
    function _transferUserERC20(address token, address destination, uint256 amount) internal {
        IPermit69(ATLAS).transferUserERC20(token, destination, amount, _user(), _control(), _config(), _phase());
    }

    /// @notice Transfers ERC20 tokens from the DApp of the current metacall tx, via Atlas, to a specified destination.
    /// @dev This will only succeed if Atlas is in a phase included in `SAFE_DAPP_TRANSFER`. See SafetyBits.sol.
    /// @param token The address of the ERC20 token contract.
    /// @param destination The address to which the tokens will be transferred.
    /// @param amount The amount of tokens to transfer.
    function _transferDAppERC20(address token, address destination, uint256 amount) internal {
        IPermit69(ATLAS).transferDAppERC20(token, destination, amount, _user(), _control(), _config(), _phase());
    }

    /// @notice Returns a bool indicating whether a source address has approved the Atlas contract to transfer a certain
    /// amount of a certain token, and whether Atlas is in the correct phase to transfer the token. Note: this is just
    /// for convenience - transfers via `_transferDAppERC20()` and `_transferUserERC20()` will independently ensure all
    /// necessary checks are made.
    /// @param _token The address of the ERC20 token contract.
    /// @param _source The address of the source of the tokens.
    /// @param _amount The amount of tokens to transfer.
    /// @param phase The phase of the current metacall tx.
    /// @return available A bool indicating whether a transfer from the source, via Atlas, of the specified amount of
    /// the specified token, will succeed.
    function _availableFundsERC20(
        address _token,
        address _source,
        uint256 _amount,
        ExecutionPhase phase
    )
        internal
        view
        returns (bool available)
    {
        uint256 balance = ERC20(_token).balanceOf(_source);
        if (balance < _amount) {
            return false;
        }

        uint8 phase_bitwise = uint8(1<<uint8(phase));
        address user = _user();
        address dapp = _control();

        if (_source == user) {
            if (phase_bitwise & SAFE_USER_TRANSFER == 0) {
                return false;
            }
            if (ERC20(_token).allowance(user, ATLAS) < _amount) {
                return false;
            }
            return true;
        }

        if (_source == dapp) {
            if (phase_bitwise & SAFE_DAPP_TRANSFER == 0) {
                return false;
            }
            if (ERC20(_token).allowance(dapp, ATLAS) < _amount) {
                return false;
            }
            return true;
        }

        return false;
    }
}
