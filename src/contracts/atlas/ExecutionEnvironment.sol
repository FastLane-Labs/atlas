//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import {ISearcherContract} from "../interfaces/ISearcherContract.sol";
import {ISafetyLocks} from "../interfaces/ISafetyLocks.sol";
import {IProtocolControl} from "../interfaces/IProtocolControl.sol";

import {SafeTransferLib, ERC20} from "solmate/utils/SafeTransferLib.sol";

import {UserMetaTx, ProtocolCall, SearcherCall, BidData} from "../types/CallTypes.sol";

import {Base} from "../protocol/ExecutionBase.sol";

import {CallVerification} from "../libraries/CallVerification.sol";
import {CallBits} from "../libraries/CallBits.sol";

// import "forge-std/Test.sol";

import {
    FastLaneErrorsEvents
} from "./Emissions.sol";

contract ExecutionEnvironment is Base {
    using CallBits for uint16;


    constructor(address _atlas) Base(_atlas) {}

    //////////////////////////////////
    ///    CORE CALL FUNCTIONS     ///
    //////////////////////////////////
    function stagingWrapper(UserMetaTx calldata userMetaTx)
        external
        returns (bytes memory)
    {
        // msg.sender = atlas
        // address(this) = ExecutionEnvironment

        require(msg.sender == atlas && userMetaTx.from == _user(), "ERR-CE00 InvalidSenderStaging");
        require(userMetaTx.to != address(this), "ERR-EV008 InvalidTo");

        bytes memory stagingData = abi.encodeWithSelector(
            IProtocolControl.stagingCall.selector, userMetaTx
        );

        bool success;
        (success, stagingData) = _control().delegatecall(
            forward(stagingData)
        );

        require(success, "ERR-EC02 DelegateRevert");

        stagingData = abi.decode(stagingData, (bytes));
        return stagingData;
    }

    function userWrapper(UserMetaTx calldata userCall) external payable returns (bytes memory userData) {
        // msg.sender = atlas
        // address(this) = ExecutionEnvironment

        address user = _user();
        uint16 config = _config();

        require(msg.sender == atlas && userCall.from == user, "ERR-CE00 InvalidSenderUser");
        require(address(this).balance >= userCall.value, "ERR-CE01 ValueExceedsBalance");
        require(userCall.to != address(this), "ERR-EV008 InvalidTo");

        bool success;

        // regular user call - executed at regular destination and not performed locally
        if (!config.needsLocalUser()) {
            (success, userData) = userCall.to.call{value: userCall.value}(
                forward(userCall.data)
            );
            require(success, "ERR-EC04a CallRevert");

        } else {
            if (config.needsDelegateUser()) {

                userData = abi.encodeWithSelector(
                    IProtocolControl.userLocalCall.selector, userCall.data
                );

                (success, userData) = _control().delegatecall(forward(userData));

                require(success, "ERR-EC02 DelegateRevert");
            } else {
                revert("ERR-P02 UserCallStatic");
            }
        }
    }

    function verificationWrapper(
        bytes calldata stagingReturnData,
        bytes calldata userReturnData
    ) external {
        // msg.sender = atlas
        // address(this) = ExecutionEnvironment
        require(msg.sender == atlas, "ERR-CE00 InvalidSenderStaging");

        bytes memory data = abi.encodeWithSelector(
            IProtocolControl.verificationCall.selector, stagingReturnData, userReturnData);

        (bool success, bytes memory returnData) = _control().delegatecall(forward(data));

        require(success, "ERR-EC02 DelegateRevert");
        require(abi.decode(returnData, (bool)), "ERR-EC03a DelegateUnsuccessful");
    }

    function searcherMetaTryCatch(
        uint256 gasLimit,
        uint256 escrowBalance,
        SearcherCall calldata searcherCall,
        bytes calldata stagingReturnData
    ) external payable {
        // msg.sender = atlas
        // address(this) = ExecutionEnvironment
        require(msg.sender == atlas, "ERR-04 InvalidCaller");
        require(address(this).balance == searcherCall.metaTx.value, "ERR-CE05 IncorrectValue");
        require(searcherCall.metaTx.to != address(this), "ERR-EV008 InvalidTo");

        // Track token balances to measure if the bid amount is paid.
        uint256[] memory tokenBalances = new uint[](searcherCall.bids.length);
        uint256 i;
        for (; i < searcherCall.bids.length;) {
            // Ether balance
            if (searcherCall.bids[i].token == address(0)) {
                tokenBalances[i] = msg.value; // NOTE: this is the meta tx value

            // ERC20 balance
            } else {
                tokenBalances[i] = ERC20(searcherCall.bids[i].token).balanceOf(address(this));
            }
            unchecked {
                ++i;
            }
        }

        ////////////////////////////
        // SEARCHER SAFETY CHECKS //
        ////////////////////////////

        // Verify that the ProtocolControl contract matches the searcher's expectations
        if(searcherCall.metaTx.controlCodeHash != _controlCodeHash()) {
            revert FastLaneErrorsEvents.AlteredControlHash();
        }

        bool success;

        // Handle any searcher staging, if necessary
        if (_config().needsSearcherStaging()) {

            bytes memory data = abi.encode(searcherCall.metaTx.to, stagingReturnData);

            data = abi.encodeWithSelector(
                IProtocolControl.searcherPreCall.selector, 
                data
            );

            (success, data) = _control().delegatecall(
                forward(data)
            );
            if(!success) {
                revert FastLaneErrorsEvents.SearcherStagingFailed();
            } 

            success = abi.decode(data, (bool));
            if(!success) {
                revert FastLaneErrorsEvents.SearcherStagingFailed();
            } 
        }

        // Execute the searcher call.
        (success,) = ISearcherContract(searcherCall.metaTx.to).metaFlashCall{
            gas: gasLimit,
            value: searcherCall.metaTx.value
        }(searcherCall.metaTx.from, searcherCall.metaTx.data, searcherCall.bids);

        // Verify that it was successful
        if(!success) {
            revert FastLaneErrorsEvents.SearcherCallReverted();
        } 

        // If this was a user intent, handle and verify fulfillment
        if (_config().needsSearcherPostCall()) {
            
            bytes memory data = stagingReturnData;

            data = abi.encode(searcherCall.metaTx.to, data);

            data = abi.encodeWithSelector(
                IProtocolControl.searcherPostCall.selector, 
                // searcherCall.metaTx.to, 
                data
            );

            (success, data) = _control().delegatecall(
                forward(data)
            );
            if(!success) {
                revert FastLaneErrorsEvents.SearcherVerificationFailed();
            } 

            success = abi.decode(data, (bool));
            if(!success) {
                revert FastLaneErrorsEvents.IntentUnfulfilled();
            }
        }


        // Verify that the searcher paid what they bid
        bool etherIsBidToken;
        i = 0;
        uint256 balance;

        for (; i < searcherCall.bids.length;) {
            // ERC20 tokens as bid currency
            if (!(searcherCall.bids[i].token == address(0))) {
                balance = ERC20(searcherCall.bids[i].token).balanceOf(address(this));
                if (balance < tokenBalances[i] + searcherCall.bids[i].bidAmount) {
                    revert FastLaneErrorsEvents.SearcherBidUnpaid();
                }

                // Native Gas (Ether) as bid currency
            } else {
                balance = address(this).balance;
                if (balance < searcherCall.bids[i].bidAmount) { // tokenBalances[i] = 0 for ether
                    revert FastLaneErrorsEvents.SearcherBidUnpaid();
                }
        
                etherIsBidToken = true;

                // Transfer any surplus Ether back to escrow to add to searcher's balance
                if (balance > searcherCall.bids[i].bidAmount) {
                    SafeTransferLib.safeTransferETH(atlas, balance - searcherCall.bids[i].bidAmount);
                }
            }
            unchecked {
                ++i;
            }
        }

        if (!etherIsBidToken) {
            uint256 currentBalance = address(this).balance;
            if (currentBalance > 0) {
                SafeTransferLib.safeTransferETH(atlas, currentBalance);
            }
        }

        // Verify that the searcher repaid their msg.value
        // TODO: Add in a more discerning func that'll silo the 
        // donations to prevent double counting. 
        if (atlas.balance < escrowBalance) {
            revert FastLaneErrorsEvents.SearcherMsgValueUnpaid();
        }
    }

    function allocateRewards(BidData[] calldata bids, bytes memory stagingReturnData) external {
        // msg.sender = escrow
        // address(this) = ExecutionEnvironment
        require(msg.sender == atlas, "ERR-04 InvalidCaller");

        uint256 totalEtherReward;
        uint256 payment;
        uint256 i;

        BidData[] memory netBids = new BidData[](bids.length);

        for (; i < bids.length;) {
            payment = (bids[i].bidAmount * 5) / 100;

            if (bids[i].token != address(0)) {
                SafeTransferLib.safeTransfer(ERC20(bids[i].token), address(0xa71a5), payment);
                totalEtherReward = bids[i].bidAmount - payment; // NOTE: This is transferred to protocolControl as msg.value
            } else {
                SafeTransferLib.safeTransferETH(address(0xa71a5), payment);
            }

            unchecked {
                netBids[i].token = bids[i].token;
                netBids[i].bidAmount = bids[i].bidAmount - payment;
                ++i;
            }
        }

        bytes memory allocateData = abi.encodeWithSelector(IProtocolControl.allocatingCall.selector, abi.encode(totalEtherReward, bids, stagingReturnData));

        (bool success,) = _control().delegatecall(forward(allocateData));
        require(success, "ERR-EC02 DelegateRevert");
    }

    function validateUserCall(UserMetaTx calldata userMetaTx)   
        external 
        // view 
        returns (bool) {
        // msg.sender = atlas
        // address(this) = ExecutionEnvironment
        require(msg.sender == atlas, "ERR-CE00 InvalidSenderStaging");

        if (userMetaTx.from != _user()) {
            return false;
        }

        if (userMetaTx.control != _control()) {
            return false;
        }

        if (userMetaTx.deadline < block.number) {
            return false;
        }

        if (_controlCodeHash() != _control().codehash) {
            return false;
        }

        bytes memory data = abi.encodeWithSelector(
            IProtocolControl.validateUserCall.selector, userMetaTx);

        (bool success, bytes memory returnData) = _control().delegatecall(forward(data));

        if (!success) {
            return false;
        }
        return abi.decode(returnData, (bool));
    }

    ///////////////////////////////////////
    //  USER SUPPORT / ACCESS FUNCTIONS  //
    ///////////////////////////////////////
    function withdrawERC20(address token, uint256 amount) external {
        require(msg.sender == _user(), "ERR-EC01 NotEnvironmentOwner");
        require(ISafetyLocks(atlas).getLockState().lockState == 0, "ERR-EC15 EscrowLocked");

        if (ERC20(token).balanceOf(address(this)) >= amount) {
            SafeTransferLib.safeTransfer(ERC20(token), msg.sender, amount);
        } else {
            revert("ERR-EC02 BalanceTooLow");
        }
    }

    function factoryWithdrawERC20(address msgSender, address token, uint256 amount) external {
        require(msg.sender == atlas, "ERR-EC10 NotFactory");
        require(msgSender == _user(), "ERR-EC11 NotEnvironmentOwner");
        require(ISafetyLocks(atlas).getLockState().lockState == 0, "ERR-EC15 EscrowLocked");

        if (ERC20(token).balanceOf(address(this)) >= amount) {
            SafeTransferLib.safeTransfer(ERC20(token), _user(), amount);
        } else {
            revert("ERR-EC02 BalanceTooLow");
        }
    }

    function withdrawEther(uint256 amount) external {
        require(msg.sender == _user(), "ERR-EC01 NotEnvironmentOwner");
        require(ISafetyLocks(atlas).getLockState().lockState == 0, "ERR-EC15 EscrowLocked");

        if (address(this).balance >= amount) {
            SafeTransferLib.safeTransferETH(msg.sender, amount);
        } else {
            revert("ERR-EC03 BalanceTooLow");
        }
    }

    function factoryWithdrawEther(address msgSender, uint256 amount) external {
        require(msg.sender == atlas, "ERR-EC10 NotFactory");
        require(msgSender == _user(), "ERR-EC11 NotEnvironmentOwner");
        require(ISafetyLocks(atlas).getLockState().lockState == 0, "ERR-EC15 EscrowLocked");

        if (address(this).balance >= amount) {
            SafeTransferLib.safeTransferETH(_user(), amount);
        } else {
            revert("ERR-EC03 BalanceTooLow");
        }
    }

    function getUser() external pure returns (address user) {
        user = _user();
    }

    function getControl() external pure returns (address control) {
        control = _control();
    }

    function getConfig() external pure returns (uint16 config) {
        config = _config();
    }

    function getEscrow() external view returns (address escrow) {
        escrow = atlas;
    }

    receive() external payable {}

    fallback() external payable {}
}
