// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import "forge-std/Test.sol";
import "src/contracts/examples/redstone-oev/RedstoneAdapterAtlasWrapper.sol";
import "src/contracts/examples/redstone-oev/RedstoneDAppControl.sol";
import "src/contracts/types/DAppOperation.sol";
import { CallVerification } from "src/contracts/libraries/CallVerification.sol";
import { BaseTest } from "test/base/BaseTest.t.sol";

contract RedstoneDAppControlTest is BaseTest {
    uint256 auctioneerPK = 0xabcdef;
    address auctioneer = vm.addr(auctioneerPK);

    RedstoneDAppControl dappControl;
    RedstoneAdapterAtlasWrapper wrapper;
    address baseFeedAddress = 0xdDb6F90fFb4d3257dd666b69178e5B3c5Bf41136; //weETH USD oracle on ETH mainnet
    uint32 dataPointValue = 666999;

    uint256 oracleOwnerPk;

    Sig public sig;

    struct Sig {
        uint8 v;
        bytes32 r;
        bytes32 s;
    }

    function setUp() public override {
        super.setUp();

        oracleOwnerPk = 0x98765;

        vm.startPrank(auctioneer);
        dappControl = new RedstoneDAppControl(address(atlas));
        atlasVerification.initializeGovernance(address(dappControl));
        vm.stopPrank();

        vm.startPrank(vm.addr(oracleOwnerPk));
        wrapper = RedstoneAdapterAtlasWrapper(dappControl.createNewAtlasAdapter(baseFeedAddress));
        vm.stopPrank();
    }

    function testDeployDAppControlAndCreateWrapper() public {
        int256 baseAnswer = IFeed(baseFeedAddress).latestAnswer();
        console.log("base answer", uint256(baseAnswer));

        updateDataFeedsValues(0x123123);

        require(IFeed(baseFeedAddress).latestAnswer() == baseAnswer, "base feed answer should not change");
        int256 answer = wrapper.latestAnswer();

        require(uint256(answer) == uint256(dataPointValue), "answer should be equal to dataPointValue");

        (uint80 roundId, int256 ansround, uint256 startedAt, uint256 updatedAt,) = wrapper.latestRoundData();
        require(roundId == 1);
        require(uint256(ansround) == uint256(dataPointValue));

        console.log("startedAt", startedAt);
        console.log("updatedAt", updatedAt);

        (,,uint256 baseStartedAt, uint256 baseUpdatedAt,) = IFeed(baseFeedAddress).latestRoundData();
        console.log("base startedAt", baseStartedAt);
        console.log("base updatedAt", baseUpdatedAt);

        (uint128 dataTimestamp, uint128 blockTimestamp) = IAdapterWithRounds(address(IFeed(baseFeedAddress).getPriceFeedAdapter())).getTimestampsFromLatestUpdate();
        console.log("dataTimestamp", uint256(dataTimestamp));
        console.log("blockTimestamp", uint256(blockTimestamp));

        (uint128 dataTimestampWrapper, uint128 blockTimestampWrapper) = IAdapterWithRounds(address(wrapper)).getTimestampsFromLatestUpdate();
        console.log("dataTimestampWrapper", uint256(dataTimestampWrapper));
        console.log("blockTimestampWrapper", uint256(blockTimestampWrapper));
    }

    function testBaseAdapterHistoricalData() public view {
        uint80 roundId = IFeed(baseFeedAddress).latestRound();
        IAdapterWithRounds adapter = IAdapterWithRounds(address(IFeed(baseFeedAddress).getPriceFeedAdapter()));
        for (uint256 i = 0; i < 5; i++) {
            (uint256 value, uint128 dataTimestamp, uint128 blockTimestamp) = adapter.getRoundDataFromAdapter(IFeed(baseFeedAddress).getDataFeedId(), roundId);
            console.log("roundId", roundId);
            console.log("value", value);
            console.log("dataTimestamp", dataTimestamp);
            console.log("blockTimestamp", blockTimestamp);
            console.log("---------------------------------------");
            roundId--;
        }
    }

    function testAuthorizedUpdateDataFeedsValues() public {
        vm.prank(vm.addr(oracleOwnerPk));
        wrapper.addAuthorisedSigner(governanceEOA);

        bool success = updateDataFeedsValues(0x123123);
        require(!success, "should fail because of unauthorized signer");

        success = updateDataFeedsValues(oracleOwnerPk);
        require(!success, "should fail because of unauthorized signer");

        success = updateDataFeedsValues(governancePK);
        require(success, "should succeed because of authorized signer");
    }

    function testRedstoneMetacall() public {
        vm.prank(vm.addr(oracleOwnerPk));
        wrapper.addAuthorisedSigner(auctioneer);

        UserOperation memory userOp = UserOperation({
            from: auctioneer,
            to: address(atlas),
            value: 0,
            gas: 1000000,
            maxFeePerGas: tx.gasprice,
            nonce: 1,
            deadline: block.number,
            dapp: address(wrapper),
            control: address(dappControl),
            callConfig: dappControl.CALL_CONFIG(),
            sessionKey: address(0),
            data: generateUserOperationData(userPK),
            signature: new bytes(0)
        });
        (sig.v, sig.r, sig.s) = vm.sign(auctioneerPK, atlasVerification.getUserOperationPayload(userOp));
        userOp.signature = abi.encodePacked(sig.r, sig.s, sig.v);

        SolverOperation[] memory solverOps = new SolverOperation[](0);

        DAppOperation memory dappOp = DAppOperation({
            from: auctioneer,
            to: address(atlas),
            nonce: 0,
            deadline: userOp.deadline,
            control: address(dappControl),
            bundler: address(0),
            userOpHash: atlasVerification.getUserOperationHash(userOp),
            callChainHash: CallVerification.getCallChainHash(userOp, solverOps),
            signature: new bytes(0)
        });
        (sig.v, sig.r, sig.s) = vm.sign(auctioneerPK, atlasVerification.getDAppOperationPayload(dappOp));
        dappOp.signature = abi.encodePacked(sig.r, sig.s, sig.v);

        assertNotEq(uint256(wrapper.latestAnswer()), uint256(dataPointValue));

        address bundler = address(69);
        vm.deal(bundler, 10 ether);

        vm.startPrank(bundler);
        atlas.depositAndBond{value: 5 ether}(5 ether);
        atlas.metacall(userOp, solverOps, dappOp);
        vm.stopPrank();

        assertEq(uint256(wrapper.latestAnswer()), uint256(dataPointValue));
    }

    function updateDataFeedsValues(uint256 pk) public returns (bool success) {
        bytes memory data = generateUserOperationData(pk);
        vm.prank(vm.addr(pk));
        (success,) = address(wrapper).call(data);
    }

    function generateUserOperationData(uint256 pk) public view returns (bytes memory call) {
        bytes32 dataFeed = IFeed(baseFeedAddress).getDataFeedId();
        uint48 timestamp = uint48(block.timestamp * 1000);
        uint32 valueSize = 4;
        uint24 dataPointsCount = 1;

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, keccak256(abi.encodePacked(dataFeed, dataPointValue, timestamp, valueSize, dataPointsCount)));
        bytes memory signature = abi.encodePacked(r, s, v);

        bytes memory payload = abi.encodePacked(
            // *** SIGNED DATA PACKAGES ***
            // 1st data package
            // - 1st data point
            // -- feed identifier
            dataFeed,               // 32 bytes
            // -- value
            dataPointValue,         // 4 bytes
            // - more data points
            // ...
            // - timestamp (milliseconds)
            timestamp,              // 6 bytes
            // - value size
            valueSize,              // 4 bytes
            // - data points count
            dataPointsCount,        // 3 bytes
            // - signature
            signature, // 65 bytes

            // more data packages
            // ...

            // data packages count
            uint16(1),              // 2 bytes

            // *** UNSIGNED METADATA ***
            // - message
            uint256(666),           // 32 bytes
            // - message size
            uint24(32),             // 3 bytes
            // - red stone marker
            hex"000002ed57011e0000"    // 9 bytes
        );

        call = abi.encodeCall(wrapper.updateDataFeedsValues, (timestamp));
        call = bytes.concat(call, payload);
    }
}
