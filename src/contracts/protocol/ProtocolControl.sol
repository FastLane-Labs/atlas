//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import {ISafetyLocks} from "../interfaces/ISafetyLocks.sol";
import {IExecutionEnvironment} from "../interfaces/IExecutionEnvironment.sol";

import {CallBits} from "../libraries/CallBits.sol";

import {GovernanceControl} from "./GovernanceControl.sol";
import {ExecutionBase} from "./ExecutionBase.sol";

import "../types/CallTypes.sol";

import "forge-std/Test.sol";

abstract contract ProtocolControl is Test, GovernanceControl, ExecutionBase {
    address public immutable escrow;
    address public immutable governance;
    address public immutable control;

    bool public immutable sequenced;
    bool public immutable requireStaging;
    bool public immutable localUser;
    bool public immutable delegateUser;
    bool public immutable searcherStaging;
    bool public immutable searcherFulfillment;
    bool public immutable requireVerification;
    bool public immutable zeroSearchers;
    bool public immutable reuseUserOp;
    bool public immutable userBundler;
    bool public immutable protocolBundler;
    bool public immutable unknownBundler;

    constructor(
        address _escrow,
        address _governance,
        bool _sequenced,
        bool _requireStaging,
        bool _localUser,
        bool _delegateUser,
        bool _searcherStaging,
        bool _searcherFulfillment,
        bool _requireVerification,
        bool _zeroSearchers,
        bool _reuseUserOp,
        bool _userBundler,
        bool _protocolBundler,
        bool _unknownBundler
    ) {

        control = address(this);

        escrow = _escrow;
        governance = _governance;

        sequenced = _sequenced;
        requireStaging = _requireStaging;
        localUser = _localUser;
        delegateUser = _delegateUser;
        searcherStaging = _searcherStaging;
        searcherFulfillment = _searcherFulfillment;
        requireVerification = _requireVerification;
        zeroSearchers = _zeroSearchers;
        reuseUserOp = _reuseUserOp;
        userBundler = _userBundler; 
        protocolBundler = _protocolBundler;
        unknownBundler = _unknownBundler;
    }

    // Safety and support functions and modifiers that make the relationship between protocol
    // and FastLane's backend trustless.
    modifier validControl() {
        require(control == _control(), "ERR-PC050 InvalidControl");
        _;
    }
    modifier mustBeDelegated() {
        require(address(this) != control, "ERR-PC051 MustBeDelegated");
        _;
    }

    modifier onlyApprovedDelegateCaller() {
        require(msg.sender == escrow, "ERR-PC060 InvalidCaller");
        _;
    }

    modifier mustBeCalled() {
        require(address(this) == control, "ERR-PC052 MustBeCalled");
        _;
    }

    modifier onlyApprovedStandardCaller() {
        require(msg.sender == ISafetyLocks(escrow).approvedCaller(), "ERR-PC061 InvalidCaller");
        _;
    }

    modifier onlyApprovedCaller(bool isDelegated) {
        if (isDelegated) {
            require(msg.sender == escrow, "ERR-PC060 InvalidCaller");
            require(address(this) != control, "ERR-PC051 MustBeDelegated");
        } else {
            require(msg.sender == ISafetyLocks(escrow).approvedCaller(), "ERR-PC061 InvalidCaller");
            require(address(this) == control, "ERR-PC052 MustBeCalled");
        }
        require(control == _control(), "ERR-PC053 InvalidControl");
        _;
    }

    function stagingCall(address to, address from, bytes4 userSelector, bytes calldata userData)
        external
        mustBeDelegated
        onlyApprovedDelegateCaller
        validControl
        returns (bytes memory)
    {
        return _stagingCall(to, from, userSelector, userData);
    }

    function userLocalCall(bytes calldata data) 
        external 
        mustBeDelegated
        onlyApprovedDelegateCaller
        validControl
        returns (bytes memory) 
    {
        return delegateUser ? _userLocalDelegateCall(data) : _userLocalStandardCall(data);
    }

    function searcherPreCall(bytes calldata data) 
        external 
        mustBeDelegated
        onlyApprovedDelegateCaller
        validControl
        returns (bool)
    {
        return _searcherPreCall(data);
    }

    function searcherPostCall(bytes calldata data) 
        external 
        mustBeDelegated
        onlyApprovedDelegateCaller
        validControl
        returns (bool)
    {
        
        return _searcherPostCall(data);
    }

    function allocatingCall(bytes calldata data) 
        external 
        mustBeDelegated
        onlyApprovedDelegateCaller
        validControl
    {
        return _allocatingCall(data);
    }

    function verificationCall(bytes calldata data) 
        external 
        mustBeDelegated
        onlyApprovedDelegateCaller 
        validControl
        returns (bool) 
    {
        return _verificationCall(data);
    }

    // View functions
    function userDelegated() external view returns (bool delegated) {
        delegated = delegateUser;
    }

    function userLocal() external view returns (bool local) {
        local = localUser;
    }

    function userDelegatedLocal() external view returns (bool delegated, bool local) {
        delegated = delegateUser;
        local = localUser;
    }

    function requireSequencedNonces() external view returns (bool isSequenced) {
        isSequenced = sequenced;
    }

    function getProtocolCall() external view returns (ProtocolCall memory protocolCall) {
        protocolCall = ProtocolCall({
            to: address(this),
            callConfig: CallBits.encodeCallConfig(
                sequenced,
                requireStaging,
                localUser,
                delegateUser,
                searcherStaging,
                searcherFulfillment,
                requireVerification,
                zeroSearchers,
                reuseUserOp,
                userBundler,
                protocolBundler,
                unknownBundler
            )
        });
    }

    function _getCallConfig() internal view returns (bool, bool, bool, bool, bool, bool, bool, bool, bool, bool, bool, bool) {
        return (
            sequenced,
            requireStaging,
            localUser,
            delegateUser,
            searcherStaging,
            searcherFulfillment,
            requireVerification,
            zeroSearchers,
            reuseUserOp,
            userBundler,
            protocolBundler,
            unknownBundler
        );
    }

    function getCallConfig() external view returns (bool, bool, bool, bool, bool, bool, bool, bool, bool, bool, bool, bool) {
        return _getCallConfig();
    }

    function getProtocolSignatory() external view returns (address governanceAddress) {
        governanceAddress = governance;
    }
}
