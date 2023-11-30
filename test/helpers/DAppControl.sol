import { DAppControl } from "../../src/contracts/dapp/DAppControl.sol";
import { CallConfig } from "../../src/contracts/types/DAppApprovalTypes.sol";
import { UserOperation } from "../../src/contracts/types/UserCallTypes.sol";
import { SolverOperation } from "../../src/contracts/types/SolverCallTypes.sol";


contract DummyDAppControl is DAppControl {
    constructor(address _escrow, address _governance, CallConfig memory _callConfig)
        DAppControl(
            _escrow,
            msg.sender,
            _callConfig
        )
    { }

    function _preOpsCall(UserOperation calldata userOp) internal override returns (bytes memory) {
        return bytes("");
    }

    function _allocateValueCall(address, uint256 bidAmount, bytes calldata) internal override {
    }

    function getBidFormat(UserOperation calldata) public pure override returns (address bidToken) {
        return address(0);
    }

    function getBidValue(SolverOperation calldata solverOp) public pure override returns (uint256) {
        return 0;
    }
}
