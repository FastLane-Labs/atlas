//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.22;

import { CallConfig } from "src/contracts/types/DAppApprovalTypes.sol";
import "src/contracts/types/UserCallTypes.sol";
import "src/contracts/types/SolverCallTypes.sol";
import "src/contracts/types/LockTypes.sol";

// Atlas DApp-Control Imports
import { DAppControl } from "src/contracts/dapp/DAppControl.sol";
import { ChainlinkAtlasWrapper } from "src/contracts/examples/oev-example/ChainlinkAtlasWrapper.sol";

import "forge-std/Test.sol";

// Used for s_oracles[a].role, where a is an address, to track the purpose
// of the address, or to indicate that the address is unset.
enum Role {
    // No oracle role has been set for address a
    Unset,
    // Signing address for the s_oracles[a].index'th oracle. I.e., report
    // signatures from this oracle should ecrecover back to address a.
    Signer,
    // Transmission address for the s_oracles[a].index'th oracle. I.e., if a
    // report is received by OffchainAggregator.transmit in which msg.sender is
    // a, it is attributed to the s_oracles[a].index'th oracle.
    Transmitter
}

struct Oracle {
    uint8 index; // Index of oracle in s_signers/s_transmitters
    Role role; // Role of the address which mapped to this struct
}

struct VerificationVars {
    mapping(address signer => Oracle oracle) oracles;
    address[] signers;
}

// NOTE: This contract acts as the Chainlink DAppControl for Atlas,
// and as a factory for ChainlinkAtlasWrapper contracts
contract ChainlinkDAppControl is DAppControl {
    uint256 internal constant MAX_NUM_ORACLES = 31;

    mapping(address baseChainlinkFeed => VerificationVars) internal verificationVars;

    error InvalidBaseFeed();
    error FailedToAllocateOEV();
    error OnlyGovernance();

    event NewChainlinkWrapperCreated(address indexed wrapper, address indexed baseFeed, address indexed owner);

    constructor(address _atlas)
        DAppControl(
            _atlas,
            msg.sender,
            CallConfig({
                userNoncesSequenced: false,
                dappNoncesSequenced: false,
                requirePreOps: false,
                trackPreOpsReturnData: false,
                trackUserReturnData: true,
                delegateUser: false,
                preSolver: false,
                postSolver: false,
                requirePostOps: false,
                zeroSolvers: false,
                reuseUserOp: false,
                userAuctioneer: true,
                solverAuctioneer: false,
                unknownAuctioneer: true,
                verifyCallChainHash: true,
                forwardReturnData: false,
                requireFulfillment: false, // Update oracle even if all solvers fail
                trustedOpHash: true,
                invertBidValue: false
            })
        )
    { }

    //////////////////////////////////
    // CONTRACT-SPECIFIC FUNCTIONS  //
    //////////////////////////////////

    function _allocateValueCall(address bidToken, uint256 bidAmount, bytes calldata data) internal virtual override {
        address chainlinkWrapper = abi.decode(data, (address));
        (bool success,) = chainlinkWrapper.call{ value: bidAmount }("");
        if (!success) revert FailedToAllocateOEV();
    }

    // NOTE: Functions below are not delegatecalled

    // ---------------------------------------------------- //
    //                    View Functions                    //
    // ---------------------------------------------------- //

    function getBidFormat(UserOperation calldata userOp) public pure override returns (address bidToken) {
        return address(0); // ETH is bid token
    }

    function getBidValue(SolverOperation calldata solverOp) public pure override returns (uint256) {
        return solverOp.bidAmount;
    }

    function getSignersForBaseFeed(address baseChainlinkFeed) external view returns (address[] memory) {
        return verificationVars[baseChainlinkFeed].signers;
    }

    // ---------------------------------------------------- //
    //          ChainlinkWrapper Factory Functions          //
    // ---------------------------------------------------- //

    // Creates a new wrapper contract for a specific Chainlink feed, to attribute OEV captured by Atlas to the
    // OEV-generating protocol.
    function createNewChainlinkAtlasWrapper(address baseChainlinkFeed) external returns (address) {
        if (IChainlinkFeed(baseChainlinkFeed).latestAnswer() == 0) revert InvalidBaseFeed();

        // TODO reconsider min, max params. Can probably just check price != 0
        address newWrapper =
            address(new ChainlinkAtlasWrapper(atlas, baseChainlinkFeed, msg.sender, 1, type(int192).max));
        emit NewChainlinkWrapperCreated(newWrapper, baseChainlinkFeed, msg.sender);
        return newWrapper;
    }

    // Called by a ChainlinkAtlasWrapper to verify if the signers of a price update via `transmit` are verified.
    function verifyTransmitSigners(
        address baseChainlinkFeed,
        bytes calldata report,
        bytes32[] calldata rs,
        bytes32[] calldata ss,
        bytes32 rawVs
    )
        external
        view
        returns (bool verified)
    {
        bool[] memory signed = new bool[](MAX_NUM_ORACLES);
        bytes32 reportHash = keccak256(report);
        Oracle memory currOracle;

        for (uint256 i = 0; i < rs.length; ++i) {
            address signer = ecrecover(reportHash, uint8(rawVs[i]) + 27, rs[i], ss[i]);
            currOracle = verificationVars[baseChainlinkFeed].oracles[signer];

            // Signer must be pre-approved and only 1 observation per signer
            if (currOracle.role != Role.Signer || signed[currOracle.index]) {
                return false;
            }
            signed[currOracle.index] = true;
        }
        return true;
    }

    // ---------------------------------------------------- //
    //                    OnlyGov Functions                 //
    // ---------------------------------------------------- //

    // TODO this works for add, but need to loop through signers array to delete before adding new set
    function setSignersForBaseFeed(address baseChainlinkFeed, address[] calldata signers) external {
        if (msg.sender != governance) revert OnlyGovernance();
        VerificationVars storage vars = verificationVars[baseChainlinkFeed];
        for (uint256 i = 0; i < signers.length; ++i) {
            vars.oracles[signers[i]] = Oracle({ index: uint8(i), role: Role.Signer });
        }
        vars.signers = signers;
    }
}

interface IChainlinkAtlasWrapper {
    function transmit(bytes calldata report, bytes32[] calldata rs, bytes32[] calldata ss, bytes32 rawVs) external;
}

interface IChainlinkFeed {
    function latestAnswer() external view returns (int256);
}
