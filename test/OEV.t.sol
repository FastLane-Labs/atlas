// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import "forge-std/Test.sol";

import { ERC20 } from "solmate/tokens/ERC20.sol";

import { BaseTest } from "./base/BaseTest.t.sol";
import { TxBuilder } from "src/contracts/helpers/TxBuilder.sol";

import { SolverOperation } from "src/contracts/types/SolverCallTypes.sol";
import { UserOperation } from "src/contracts/types/UserCallTypes.sol";
import { DAppOperation, DAppConfig } from "src/contracts/types/DAppApprovalTypes.sol";

import { ChainlinkDAppControl } from "src/contracts/examples/oev-example/ChainlinkDAppControl.sol";
import {ChainlinkAtlasWrapperETHUSD, TransmitPayload, IChainlinkAggregator } from "src/contracts/examples/oev-example/ChainlinkAtlasWrapperETHUSD.sol";
import { SolverBase } from "src/contracts/solver/SolverBase.sol";


// Using this Chainlink update to ETHUSD feed as an example:
// Aggregator: https://etherscan.io/address/0xE62B71cf983019BFf55bC83B48601ce8419650CC
// Transmit tx: https://etherscan.io/tx/0x3645d1bc223efe0861e02aeb95d6204c5ebfe268b64a7d23d385520faf452bc0
// ETH/USD set to: $2941.02 == 294102000000

contract OEVTest is BaseTest {
    ChainlinkAtlasWrapperETHUSD public chainlinkAtlasWrapperETHUSD;
    ChainlinkDAppControl public chainlinkDAppControl;
    MockLiquidatable public mockLiquidatable;


    TxBuilder public txBuilder;
    Sig public sig;

    address chainlinkETHUSD = 0xE62B71cf983019BFf55bC83B48601ce8419650CC;
    uint256 forkBlock = 19289829; // Block just before the transmit tx above

    struct Sig {
        uint8 v;
        bytes32 r;
        bytes32 s;
    }

    function setUp() public virtual override {
        BaseTest.setUp();
        vm.rollFork(forkBlock);

        // Creating new gov address (ERR-V49 OwnerActive if already registered with controller)
        governancePK = 11_112;
        governanceEOA = vm.addr(governancePK);
        address liquidatableGovEOA = vm.addr(11_113);

        vm.startPrank(liquidatableGovEOA);
        // Lending protocol liquidations must use the Chainlink Atlas Wrapper for price feed
        mockLiquidatable = new MockLiquidatable(address(chainlinkAtlasWrapperETHUSD), 294102000000);
        vm.stopPrank();
        
        vm.startPrank(governanceEOA);
        // Chainlink's Gov address deploys the Chainlink DAppControl and AtlasWrapper
        chainlinkAtlasWrapperETHUSD = new ChainlinkAtlasWrapperETHUSD(address(atlas), chainlinkETHUSD);
        chainlinkDAppControl = new ChainlinkDAppControl(address(atlas), address(chainlinkAtlasWrapperETHUSD));

        // Chainlink's Gov address initializes the Chainlink DAppControl in Atlas, and as a transmitter in the wrapper
        atlasVerification.initializeGovernance(address(chainlinkDAppControl));
        chainlinkAtlasWrapperETHUSD.setTransmitterStatus(address(chainlinkDAppControl), true);
        vm.stopPrank();

        txBuilder = new TxBuilder({
            controller: address(chainlinkDAppControl),
            atlasAddress: address(atlas),
            _verification: address(atlasVerification)
        });
    }

    function testChainlinkOEV() public {

        TransmitPayload memory transmitPayload = getTransmitPayload();

        console.logBytes(transmitPayload.report);

        // NOTES:
        // - The EE must be whitelisted to post answers to Wrapper and Base oracles

        // Inside Atlas.metacall:
        // 1. userOp - updates the oracle wrapper with new int256
        // 2. solverOps - capture OEV by liquidating things that use the oracle wrapper
        // 3. postOpsCall - update the base chainlink oracle with signed `transmit` data
        
    }


    // ----------------
    // OEV Test Utils
    // ----------------

    // Returns calldata taken from a real Chainlink ETH/USD transmit tx
    function getTransmitPayload() public returns (TransmitPayload memory) {
        // From this ETHUSD transmit tx: Transmit tx:
        // https://etherscan.io/tx/0x3645d1bc223efe0861e02aeb95d6204c5ebfe268b64a7d23d385520faf452bc0
        // ETHUSD set to: $2941.02 == 294102000000

        bytes memory report = hex"000000000000000000000047ddec946856fa8055ac2202f633de330001769d050a1718161a110212090c1d1b191c0b0e030001140f131e1508060d04100705000000000000000000000000000000000000000000000000000000000000000060000000000000000000000000000000000000000000000000000000000000001f00000000000000000000000000000000000000000000000000000044759deacc0000000000000000000000000000000000000000000000000000004475d8ca020000000000000000000000000000000000000000000000000000004475d8ca020000000000000000000000000000000000000000000000000000004475d8ca100000000000000000000000000000000000000000000000000000004476517782000000000000000000000000000000000000000000000000000000447664840f0000000000000000000000000000000000000000000000000000004476a015190000000000000000000000000000000000000000000000000000004476a015190000000000000000000000000000000000000000000000000000004476a01519000000000000000000000000000000000000000000000000000000447779d953000000000000000000000000000000000000000000000000000000447914dd8f000000000000000000000000000000000000000000000000000000447914dd8f000000000000000000000000000000000000000000000000000000447914dd8f000000000000000000000000000000000000000000000000000000447914dd8f0000000000000000000000000000000000000000000000000000004479d861800000000000000000000000000000000000000000000000000000004479d861800000000000000000000000000000000000000000000000000000004479d861800000000000000000000000000000000000000000000000000000004479d861800000000000000000000000000000000000000000000000000000004479d861800000000000000000000000000000000000000000000000000000004479d9ce27000000000000000000000000000000000000000000000000000000447a9ebec0000000000000000000000000000000000000000000000000000000447a9ebec0000000000000000000000000000000000000000000000000000000447ad9a8c8000000000000000000000000000000000000000000000000000000447b281300000000000000000000000000000000000000000000000000000000447b281300000000000000000000000000000000000000000000000000000000447b281300000000000000000000000000000000000000000000000000000000447b3df490000000000000000000000000000000000000000000000000000000447b3df490000000000000000000000000000000000000000000000000000000447b5d3856000000000000000000000000000000000000000000000000000000447b5d3856000000000000000000000000000000000000000000000000000000447b5d3856";
        bytes32[] memory rs = new bytes32[](11);
        bytes32[] memory ss = new bytes32[](11);
        bytes32 rawVs = 0x0100010101000000000001000000000000000000000000000000000000000000;

        rs[0] = 0x5bde6c6a1b27f1421400fba9850abcd4d9701d7178d2df1d469c693a9ab6389e;
        rs[1] = 0xf9518ba45aaf8fc019962dee3144087723bcac49ce1b3d12d075abc030ae51f1;
        rs[2] = 0x657ae99064988794f99b98dfdd6ebc9f5c0967f75e5ce61392d81d78e8434e0a;
        rs[3] = 0xfc4ef6fa4d47c3a8cb247799831c4db601387106cc9f80ef710fec5d06b07c53;
        rs[4] = 0x813516330ff60244a90a062f4ddcb18611711ed217cf146041439e26a6c1d687;
        rs[5] = 0x8aa23424c2fdd1d2f459fc901c3b21c611d17c07b0df51c48f17bd6bcc5d8c54;
        rs[6] = 0xe40ea4755faebccfccbf9ca25bd518427877c9155526db04458b9753034ad552;
        rs[7] = 0x44fbb6b9ab6f56f29d5d1943fa6d6b13c993e213ba3b20f6a5d20224cb3f942d;
        rs[8] = 0xe2a4e3529c077a128bc52d5e1b11cf64bc922100bafe6ebc95654fea49a5d355;
        rs[9] = 0x4588680888b56cda77a1b49b32807ba33e7009a182a048d33496d70987aebcbc;
        rs[10] = 0x7ad51d2aa5e792f46ac17784a3a362f0fff3dc7f805ef8f74324113d8b475249;

        ss[0] = 0x3eb07f321322b7d0ea0c90ca48af408e9b6daaaf0e33993436155ef83d1e7d0e;
        ss[1] = 0x5ff05d281bf7c1db924036e0123765adfef8b4f563d981da9c7011dc3b1e6c79;
        ss[2] = 0x7fdb65f4084636a904129a327d99a8ef5cdcadc3e6e266626823eb1adab4532d;
        ss[3] = 0x07025b9483f5ad5ee55f07b6cddbabc1411d9570ced7d11a3d504cf38853e8a3;
        ss[4] = 0x332a4b577c831d9dae5ea3eb4ee5832cdd6672c4bd7c97e5fb2dae3b4b99d02f;
        ss[5] = 0x45b4181c3b95f15fc40a40fb74344d1ef45c33dfbe99587237a1a4c875aae024;
        ss[6] = 0x2a2eb5e729343c2f093c6b6ec71f0b1eb07bf133ead806976672dcbf90abcaca;
        ss[7] = 0x54ca9bd4122a43f119d3d24072db5be9479f9271d32f332e76ff3a70feeb7fd3;
        ss[8] = 0x1a7aaeda65f1cabb53a43f080ab8d76337107b0e7bf013096eecdefcf88af56a;
        ss[9] = 0x7a1e1d7b9c865b34d966a94e21f0d2c73473a30bf03c1f8eff7b88b5c3183c31;
        ss[10] = 0x2768d43bca650e9a452db41730c4e31b600f5398c49490d66f4065a0b357707f;

        return TransmitPayload({
            report: report,
            rs: rs,
            ss: ss,
            rawVs: rawVs
        });
    }
}

contract LiquidationOEVSolver is SolverBase {
    constructor(address weth, address atlas) SolverBase(weth, atlas, msg.sender) { }

    // This ensures a function can only be called through metaFlashCall
    // which includes security checks to work safely with Atlas
    modifier onlySelf() {
        require(msg.sender == address(this), "Not called via metaFlashCall");
        _;
    }

    fallback() external payable { }
    receive() external payable { }
}

// Super basic mock to represent a liquidation payout dependent on oracle price
contract MockLiquidatable {

    address public oracle;
    uint256 public liquidationPrice;

    constructor(address _oracle, uint256 _liquidationPrice) {
        oracle = _oracle;
        liquidationPrice = _liquidationPrice;
    }

    function liquidate() public {
        require(canLiquidate(), "Cannot liquidate");
        
        payable(msg.sender).call{value: address(this).balance}("");
    }

    // Can only liquidate if the oracle price is exactly the liquidation price
    function canLiquidate() public view returns (bool) {
        return uint256(IChainlinkAggregator(oracle).latestAnswer()) == liquidationPrice;
    }

}