//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import {IPermit69} from "../interfaces/IPermit69.sol";
import {ISafetyLocks} from "../interfaces/ISafetyLocks.sol";

// import "forge-std/Test.sol";

contract Base {
    address public immutable atlas;

    constructor(address _atlas) {
        atlas = _atlas;
    }

    // These functions only work inside of the ExecutionEnvironment (mimic)
    // via delegatecall, but can be added to ProtocolControl as funcs that 
    // can be used during ProtocolControl's delegated funcs
    
    function forward(bytes memory data) internal pure returns (bytes memory) {
        // TODO: simplify this into just the bytes
        return bytes.concat(
            data,
            _firstSet(),
            _secondSet()
        );
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
            uint16(0) // placeholder
        );
    }

    function _secondSet() internal pure returns (bytes memory data) {
        data = abi.encodePacked(
            _user(),
            _control(),
            _config(),
            _controlCodeHash()
        );
    }

    // Returns the address(ProtocolControl).codehash for the calling
    // ExecutionEnvironment's ProtocolControl
    function _controlCodeHash() internal pure returns (bytes32 controlCodeHash) {
        assembly {
            controlCodeHash := calldataload(sub(calldatasize(), 32))
        }
    }

    function _config() internal pure returns (uint16 config) {
        assembly {
            config := shr(240, calldataload(sub(calldatasize(), 34)))
        }
    }

    function _control() internal pure returns (address control) {
        assembly {
            control := shr(96, calldataload(sub(calldatasize(), 54)))
        }
    }

    function _user() internal pure returns (address user) {
        assembly {
            user := shr(96, calldataload(sub(calldatasize(), 74)))
        }
    }

    function _gasRefund() internal pure returns (uint32 gasRefund) {
        assembly {
            gasRefund := shr(224, calldataload(sub(calldatasize(), 96)))
        }
    }

    function _lockState() internal pure returns (uint16 lockState) {
        assembly {
            lockState := shr(240, calldataload(sub(calldatasize(), 100)))
        }
    }

    function _callMax() internal pure returns (uint8 callMax) {
        assembly {
            callMax := shr(248, calldataload(sub(calldatasize(), 102)))
        }
    }

    function _callIndex() internal pure returns (uint8 callIndex) {
        assembly {
            callIndex := shr(248, calldataload(sub(calldatasize(), 103)))
        }
    }

    function _paymentsComplete() internal pure returns (bool paymentsComplete) {
        assembly {
            paymentsComplete := shr(248, calldataload(sub(calldatasize(), 104)))
        }
    }

    function _makingPayments() internal pure returns (bool makingPayments) {
        assembly {
            makingPayments := shr(248, calldataload(sub(calldatasize(), 105)))
        }
    }

    function _approvedCaller() internal pure returns (address approvedCaller) {
        assembly {
            approvedCaller := shr(96, calldataload(sub(calldatasize(), 106)))
        }
    }

    function _activeEnvironment() internal view returns (address activeEnvironment) {
        activeEnvironment = ISafetyLocks(atlas).activeEnvironment();
    }
}

contract ExecutionBase is Base {

    constructor(address _atlas) Base(_atlas) {}

    function _transferUserERC20(
        address token,
        address destination,
        uint256 amount
    ) internal {
        if (msg.sender == atlas) {
            IPermit69(atlas).transferUserERC20(
                token, destination, amount, _user(), _control(), _config()
            );
        }
    }

    function _transferProtocolERC20(
        address token,
        address destination,
        uint256 amount
    ) internal {
        if (msg.sender == atlas) {
            IPermit69(msg.sender).transferProtocolERC20(
                token, destination, amount, _user(), _control(), _config()
            );
        }
    }
}