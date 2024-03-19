//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.22;

import { IPermit69 } from "../interfaces/IPermit69.sol";
import { ISafetyLocks } from "../interfaces/ISafetyLocks.sol";
import { IEscrow } from "../interfaces/IEscrow.sol";

import { SafeTransferLib, ERC20 } from "solmate/utils/SafeTransferLib.sol";

import { ExecutionPhase, BaseLock } from "../types/LockTypes.sol";

import { EXECUTION_PHASE_OFFSET, SAFE_USER_TRANSFER, SAFE_DAPP_TRANSFER } from "../libraries/SafetyBits.sol";

import "forge-std/Test.sol";

contract Base {
    address public immutable atlas;
    address public immutable source;
    bytes32 public immutable salt;

    uint16 internal phasesWithDonations; //TODO remember to clear after call

    constructor(address _atlas) {
        atlas = _atlas;
        source = address(this);
        salt = keccak256(abi.encodePacked(block.chainid, atlas, "Atlas 1.0"));
    }

    // These functions only work inside of the ExecutionEnvironment (mimic)
    // via delegatecall, but can be added to DAppControl as funcs that
    // can be used during DAppControl's delegated funcs

    modifier onlyAtlasEnvironment(ExecutionPhase phase, uint8 acceptableDepths) {
        _onlyAtlasEnvironment(phase, acceptableDepths);
        _;
    }

    function _onlyAtlasEnvironment(ExecutionPhase phase, uint8 acceptableDepths) internal view {
        if (address(this) == source) {
            revert("ERR-EB00 NotDelegated");
        }
        if (msg.sender != atlas) {
            revert("ERR-EB01 InvalidSender");
        }
        if (uint16(1 << (EXECUTION_PHASE_OFFSET + uint16(phase))) & _lockState() == 0) {
            revert("ERR-EB02 WrongPhase");
        }
        if (1 << _depth() & acceptableDepths == 0) {
            revert("ERR-EB03 WrongDepth");
        }
    }

    function forward(bytes memory data) internal pure returns (bytes memory) {
        // TODO: simplify this into just the bytes
        return bytes.concat(data, _firstSet(), _secondSet());
    }

    function _firstSet() internal pure returns (bytes memory data) {
        data = abi.encodePacked(
            _addressPointer(),
            _solverSuccessful(),
            _paymentsSuccessful(),
            _callIndex(),
            _callCount(),
            _lockState(),
            _blank(),
            _bidFind(),
            _simulation(),
            _depth() + 1
        );
    }

    function _secondSet() internal pure returns (bytes memory data) {
        data = abi.encodePacked(_user(), _control(), _config(), _controlCodeHash());
    }

    function forwardSpecial(bytes memory data, ExecutionPhase phase) internal pure returns (bytes memory) {
        // TODO: simplify this into just the bytes
        return bytes.concat(data, _firstSetSpecial(phase), _secondSet());
    }

    function _firstSetSpecial(ExecutionPhase phase) internal pure returns (bytes memory data) {
        uint8 depth = _depth();
        uint16 lockState = _lockState();

        if (depth == 1 && lockState & 1 << (EXECUTION_PHASE_OFFSET + uint16(ExecutionPhase.SolverOperations)) != 0) {
            if (phase == ExecutionPhase.PreSolver || phase == ExecutionPhase.PostSolver) {
                lockState = uint16(1) << uint16(BaseLock.Active) | uint16(1) << (EXECUTION_PHASE_OFFSET + uint16(phase));
            }
        }

        data = abi.encodePacked(
            _addressPointer(),
            _solverSuccessful(),
            _paymentsSuccessful(),
            _callIndex(),
            _callCount(),
            lockState,
            _blank(),
            _bidFind(),
            _simulation(),
            depth + 1
        );
    }

    // Returns the address(DAppControl).codehash for the calling
    // ExecutionEnvironment's DAppControl
    function _controlCodeHash() internal pure returns (bytes32 controlCodeHash) {
        assembly {
            controlCodeHash := calldataload(sub(calldatasize(), 32))
        }
    }

    function _config() internal pure returns (uint32 config) {
        assembly {
            config := shr(224, calldataload(sub(calldatasize(), 36)))
        }
    }

    function _control() internal pure returns (address control) {
        assembly {
            control := shr(96, calldataload(sub(calldatasize(), 56)))
        }
    }

    function _user() internal pure returns (address user) {
        assembly {
            user := shr(96, calldataload(sub(calldatasize(), 76)))
        }
    }

    function _depth() internal pure returns (uint8 callDepth) {
        assembly {
            callDepth := shr(248, calldataload(sub(calldatasize(), 77)))
        }
    }

    function _simulation() internal pure returns (bool simulation) {
        assembly {
            simulation := shr(248, calldataload(sub(calldatasize(), 78)))
        }
    }

    function _bidFind() internal pure returns (bool bidFind) {
        assembly {
            bidFind := shr(248, calldataload(sub(calldatasize(), 79)))
        }
    }

    function _blank() internal pure returns (uint24 blank) {
        assembly {
            blank := shr(232, calldataload(sub(calldatasize(), 82)))
        }
    }

    function _lockState() internal pure returns (uint16 lockState) {
        assembly {
            lockState := shr(240, calldataload(sub(calldatasize(), 84)))
        }
    }

    function _callCount() internal pure returns (uint8 callCount) {
        assembly {
            callCount := shr(248, calldataload(sub(calldatasize(), 85)))
        }
    }

    function _callIndex() internal pure returns (uint8 callIndex) {
        assembly {
            callIndex := shr(248, calldataload(sub(calldatasize(), 86)))
        }
    }

    function _paymentsSuccessful() internal pure returns (bool paymentsSuccessful) {
        assembly {
            paymentsSuccessful := shr(248, calldataload(sub(calldatasize(), 87)))
        }
    }

    function _solverSuccessful() internal pure returns (bool solverSuccessful) {
        assembly {
            solverSuccessful := shr(248, calldataload(sub(calldatasize(), 88)))
        }
    }

    function _addressPointer() internal pure returns (address addressPointer) {
        assembly {
            addressPointer := shr(96, calldataload(sub(calldatasize(), 108)))
        }
    }

    function _activeEnvironment() internal view returns (address activeEnvironment) {
        activeEnvironment = ISafetyLocks(atlas).activeEnvironment();
    }
}

contract ExecutionBase is Base {
    constructor(address _atlas) Base(_atlas) { }

    // Deposit local funds to the transient Atlas balance
    // NOTE that this will go towards the Bundler, with the surplus going to the Solver.
    function _contribute(uint256 amt) internal {
        if (msg.sender != atlas) revert("ERR-EB001 InvalidSender");
        if (amt > address(this).balance) revert("ERR-EB002 InsufficientLocalBalance");

        IEscrow(atlas).contribute{ value: amt }();
    }

    // Borrow funds from the transient Atlas balance that will be repaid by the Solver (or self via another deposit)
    function _borrow(uint256 amt) internal {
        if (msg.sender != atlas) revert("ERR-EB001 InvalidSender");

        IEscrow(atlas).borrow(amt);
    }

    function _transferUserERC20(address token, address destination, uint256 amount) internal {
        if (msg.sender != atlas) {
            revert("ERR-EB001 InvalidSender");
        }
        IPermit69(atlas).transferUserERC20(token, destination, amount, _user(), _control(), _config(), _lockState());
    }

    function _transferDAppERC20(address token, address destination, uint256 amount) internal {
        if (msg.sender != atlas) {
            revert("ERR-EB001 InvalidSender");
        }
        IPermit69(atlas).transferDAppERC20(token, destination, amount, _user(), _control(), _config(), _lockState());
    }

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

        uint16 shiftedPhase = uint16(1 << (EXECUTION_PHASE_OFFSET + uint16(phase)));
        address user = _user();
        address dapp = _control();

        if (_source == user) {
            if (shiftedPhase & SAFE_USER_TRANSFER == 0) {
                return false;
            }
            if (ERC20(_token).allowance(user, atlas) < _amount) {
                return false;
            }
            return true;
        } else if (_source == dapp) {
            if (shiftedPhase & SAFE_DAPP_TRANSFER == 0) {
                return false;
            }
            if (ERC20(_token).allowance(dapp, atlas) < _amount) {
                return false;
            }
            return true;
        }
        return false;
    }
}
