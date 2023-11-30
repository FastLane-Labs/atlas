import { CallConfig } from "../../src/contracts/types/DAppApprovalTypes.sol";


library CallConfigFactory {
    function allFalseCallConfig() public pure returns (CallConfig memory) {
        return CallConfig({
            sequenced: false,
            requirePreOps: true,
            trackPreOpsReturnData: false,
            trackUserReturnData: false,
            delegateUser: false,
            localUser: false,
            preSolver: false,
            postSolver: false,
            requirePostOps: false,
            zeroSolvers: false,
            reuseUserOp: false,
            userBundler: false,
            solverBundler: false,
            verifySolverBundlerCallChainHash: false,
            unknownBundler: false,
            forwardReturnData: false,
            requireFulfillment: false
        });
    }
}
