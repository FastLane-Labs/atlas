//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { IPermit69 } from "../interfaces/IPermit69.sol";
import { ISafetyLocks } from "../interfaces/ISafetyLocks.sol";
import { IEscrow } from "../interfaces/IEscrow.sol";

import { SafeTransferLib, ERC20 } from "solmate/utils/SafeTransferLib.sol";

import { ExecutionPhase, BaseLock } from "../types/LockTypes.sol";
import { Party } from "../types/EscrowTypes.sol";

import { EXECUTION_PHASE_OFFSET, SAFE_USER_TRANSFER, SAFE_DAPP_TRANSFER } from "../libraries/SafetyBits.sol";
import { PartyMath } from "../libraries/GasParties.sol";

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
            _approvedCaller(),
            _makingPayments(),
            _paymentsComplete(),
            _callIndex(),
            _callMax(),
            _lockState(),
            _gasRefund(),
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
            _approvedCaller(),
            _makingPayments(),
            _paymentsComplete(),
            _callIndex(),
            _callMax(),
            lockState,
            _gasRefund(),
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

    function _gasRefund() internal pure returns (uint32 gasRefund) {
        assembly {
            gasRefund := shr(224, calldataload(sub(calldatasize(), 82)))
        }
    }

    function _lockState() internal pure returns (uint16 lockState) {
        assembly {
            lockState := shr(240, calldataload(sub(calldatasize(), 84)))
        }
    }

    function _callMax() internal pure returns (uint8 callMax) {
        assembly {
            callMax := shr(248, calldataload(sub(calldatasize(), 85)))
        }
    }

    function _callIndex() internal pure returns (uint8 callIndex) {
        assembly {
            callIndex := shr(248, calldataload(sub(calldatasize(), 86)))
        }
    }

    function _paymentsComplete() internal pure returns (bool paymentsComplete) {
        assembly {
            paymentsComplete := shr(248, calldataload(sub(calldatasize(), 87)))
        }
    }

    function _makingPayments() internal pure returns (bool makingPayments) {
        assembly {
            makingPayments := shr(248, calldataload(sub(calldatasize(), 88)))
        }
    }

    function _approvedCaller() internal pure returns (address approvedCaller) {
        assembly {
            approvedCaller := shr(96, calldataload(sub(calldatasize(), 108)))
        }
    }

    function _activeEnvironment() internal view returns (address activeEnvironment) {
        activeEnvironment = ISafetyLocks(atlas).activeEnvironment();
    }

    function _partyAddress(Party party) internal view returns (address partyAddress) {
        uint256 pIndex = uint256(party);
        // MEDIAN INDEX
        if (pIndex < uint256(Party.Solver)) {
            if (party == Party.Builder) {
                // CASE: BUILDER
                return block.coinbase;
            } else {
                // CASE: BUNDLER
                return tx.origin; // TODO: This may be unreliable for smart wallet integrations.
            }
        } else if (pIndex > uint256(Party.Solver)) {
            if (party == Party.User) {
                // CASE: USER
                return _user();
            } else {
                // CASE: DAPP
                return _control();
            }
        } else {
            // CASE: SOLVER
            // NOTE: Currently unimplemented
            // TODO: check if this is a SolverOp phase and use assembly to grab the solverOp.from from calldata
            revert("ERR-EB090 SolverPartyUnimplemented");
        }
    }
}

contract ExecutionBase is Base {
    using PartyMath for Party;

    constructor(address _atlas) Base(_atlas) { }


    // Deposit local funds to the recipient's balance
    function _deposit(Party recipient, uint256 amt) internal {
        if (msg.sender != atlas) revert("ERR-EB001 InvalidSender");
        if (amt > address(this).balance) revert("ERR-EB002 InsufficientLocalBalance");

        IEscrow(atlas).deposit{ value: amt }(recipient);
    }

    // Contribute funds on behalf of the donor to be used by the recipient
    // Any unused funds are returned to the donor
    function _contributeTo(Party donor, Party recipient, uint256 amountLocalValue, uint256 amountBalanceOf) internal {
        if (msg.sender != atlas) revert("ERR-EB001 InvalidSender");
        if (!donor.validContribution(_lockState())) revert("ERR-EB002 InvalidPhase");
        if (amountLocalValue > address(this).balance) revert("ERR-EB003 InsufficientLocalBalance");

        IEscrow(atlas).contributeTo{value: amountLocalValue}(donor, recipient, amountBalanceOf);
    }

    // Recipient requests a contribution from the donor.
    // NOTE: Can be fulfilled by any party.
    function _requestFrom(Party donor, Party recipient, uint256 amt) internal {
        if (msg.sender != atlas) revert("ERR-EB001 InvalidSender");
        if (!donor.validRequest(_lockState())) revert("ERR-EB002 InvalidPhase");

        IEscrow(atlas).requestFrom(donor, recipient, amt);
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
        address token,
        address source,
        uint256 amount,
        ExecutionPhase phase
    )
        internal
        view
        returns (bool available)
    {
        uint256 balance = ERC20(token).balanceOf(source);
        if (balance < amount) {
            return false;
        }

        uint16 shiftedPhase = uint16(1 << (EXECUTION_PHASE_OFFSET + uint16(phase)));
        address user = _user();
        address dapp = _control();

        if (source == user) {
            if (shiftedPhase & SAFE_USER_TRANSFER == 0) {
                return false;
            }
            if (ERC20(token).allowance(user, atlas) < amount) {
                return false;
            }
            return true;
        } else if (source == dapp) {
            if (shiftedPhase & SAFE_DAPP_TRANSFER == 0) {
                return false;
            }
            if (ERC20(token).allowance(dapp, atlas) < amount) {
                return false;
            }
            return true;
        }
        return false;
    }
}
