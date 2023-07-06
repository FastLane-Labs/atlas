//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import { ISearcherContract } from "../interfaces/ISearcherContract.sol";
import { ISafetyLocks } from "../interfaces/ISafetyLocks.sol";
import { IProtocolControl } from "../interfaces/IProtocolControl.sol";

import { SafeTransferLib, ERC20 } from "solmate/utils/SafeTransferLib.sol";

import {UserCall, ProtocolCall, SearcherCall, BidData, PayeeData} from "../types/CallTypes.sol";
import { CallChainProof } from "../types/VerificationTypes.sol";

import { CallVerification } from "../libraries/CallVerification.sol";
import { CallBits } from "../libraries/CallBits.sol";

// import "forge-std/Test.sol";

import {
    ALTERED_USER_HASH,
    SEARCHER_CALL_REVERTED,
    SEARCHER_MSG_VALUE_UNPAID,
    SEARCHER_FAILED_CALLBACK,
    SEARCHER_BID_UNPAID
 } from "./Emissions.sol";

contract ExecutionEnvironment {
    using CallVerification for CallChainProof;
    using CallBits for uint16;

    address immutable public atlas;

    constructor(address _atlas) {
        atlas = _atlas;
    }

    // MIMIC INTERACTION FUNCTIONS
    function _config() internal pure returns (uint16 config) {
        assembly {
            config := shr(240, calldataload(sub(calldatasize(), 2)))
        }
    }

    function _control() internal pure returns (address control) {
        assembly {
            control := shr(96, calldataload(sub(calldatasize(), 22)))
        }
    }

    function _user() internal pure returns (address user) {
        assembly {
            user := shr(96, calldataload(sub(calldatasize(), 42)))
        }
    }

      //////////////////////////////////
     ///    CORE CALL FUNCTIONS     ///
    //////////////////////////////////
    function stagingWrapper(
        CallChainProof calldata proof,
        UserCall calldata userCall
    ) external returns (bytes memory stagingData) {
        // msg.sender = atlas
        // address(this) = ExecutionEnvironment

        address control = _control();
        uint16 config = _config();

        require(msg.sender == atlas && userCall.from == _user(), "ERR-CE00 InvalidSenderStaging");

        bytes memory stagingCalldata = abi.encodeWithSelector(
            IProtocolControl.stageCall.selector,
            userCall.to, 
            userCall.from,
            bytes4(userCall.data), 
            userCall.data[4:]
        );

        // Verify the proof so that the callee knows this isn't happening out of sequence.
        require(proof.prove(control, stagingCalldata), "ERR-P01 ProofInvalid");

        bool success;

        if (config.needsDelegateStaging()) {
            (success, stagingData) = control.delegatecall(
                stagingCalldata
            );
            require(success, "ERR-EC02 DelegateRevert");
        
        } else {
            (success, stagingData) = control.staticcall(
                stagingCalldata
            );
            require(success, "ERR-EC03 StaticRevert");
        }
    }

    function userWrapper(
        CallChainProof calldata proof,
        UserCall calldata userCall
    ) external payable returns (bytes memory userReturnData) {
        // msg.sender = atlas
        // address(this) = ExecutionEnvironment

        address user = _user();
        uint16 config = _config();

        require(msg.sender == atlas && userCall.from == user, "ERR-CE00 InvalidSenderUser");
        require(address(this).balance >= userCall.value, "ERR-CE01 ValueExceedsBalance");

        // Verify the proof so that the callee knows this isn't happening out of sequence.
        require(proof.prove(userCall.to, userCall.data), "ERR-P01 ProofInvalid");

        bool success;

        // regular user call - executed at regular destination and not performed locally
        if (!config.needsLocalUser()) {

            (success, userReturnData) = userCall.to.call{
                value: userCall.value
            }(
                userCall.data
            );
            require(success, "ERR-EC04a CallRevert");
        
        } else {
            if (config.needsDelegateUser()) {
                (success, userReturnData) = _control().delegatecall(
                    abi.encodeWithSelector(
                        IProtocolControl.userLocalCall.selector,
                        userCall.to, 
                        userCall.value,
                        userCall.data
                    )
                );
                require(success, "ERR-EC02 DelegateRevert");
            
            } else {
                revert("ERR-P02 UserCallStatic");
            }
        }

        if (!config.allowsRecycledStorage()) {
            // NOTE: selfdestruct will continue to work post EIP-6780 when it is triggered
            // in the same transaction as contract creation, which is what we do here.
            selfdestruct(payable(user));

        } else {
            uint256 balance = address(this).balance;
            if (balance > 0) {
                SafeTransferLib.safeTransferETH(
                    payable(user), 
                    balance
                );
            }
        }
    }

    function verificationWrapper(
        CallChainProof calldata proof,
        bytes calldata stagingReturnData, 
        bytes calldata userReturnData
    ) external {
        // msg.sender = atlas
        // address(this) = ExecutionEnvironment
        require(msg.sender == atlas, "ERR-CE00 InvalidSenderStaging");

        bytes memory data = abi.encodeWithSelector(
            IProtocolControl.verificationCall.selector, 
            stagingReturnData,
            userReturnData
        );

        // Verify the proof so that the callee knows this isn't happening out of sequence.
        require(proof.prove(_control(), data), "ERR-P01 ProofInvalid");

        if (_config().needsDelegateVerification()) {
            (bool success, bytes memory returnData) = _control().delegatecall(
                data
            );
            require(success, "ERR-EC02 DelegateRevert");
            require(abi.decode(returnData, (bool)), "ERR-EC03a DelegateUnsuccessful");
        
        } else {
            (bool success, bytes memory returnData) = _control().staticcall(
                data
            );
            require(success, "ERR-EC03 StaticRevert");
            require(abi.decode(returnData, (bool)), "ERR-EC03b DelegateUnsuccessful");
        }
    }


    function searcherMetaTryCatch(
        CallChainProof calldata proof,
        uint256 gasLimit,
        uint256 escrowBalance,
        SearcherCall calldata searcherCall
    ) external payable {
        // msg.sender = atlas
        // address(this) = ExecutionEnvironment
        require(msg.sender == atlas, "ERR-04 InvalidCaller");
        require(
            address(this).balance == searcherCall.metaTx.value,
            "ERR-CE05 IncorrectValue"
        );

        // Track token balances to measure if the bid amount is paid.
        uint256[] memory tokenBalances = new uint[](searcherCall.bids.length);
        uint256 i;
        for (; i < searcherCall.bids.length;) {

            // Ether balance
            if (searcherCall.bids[i].token == address(0)) {
                tokenBalances[i] = msg.value;  // NOTE: this is the meta tx value

            // ERC20 balance
            } else {
                tokenBalances[i] = ERC20(searcherCall.bids[i].token).balanceOf(address(this));
            }
            unchecked {++i;}
        }

          ////////////////////////////
         // SEARCHER SAFETY CHECKS //
        ////////////////////////////

        // Verify that the searcher's view of the user's calldata hasn't been altered
        // NOTE: Although this check may seem redundant since the user's calldata is in the
        // searcher hash chain as verified below, remember that the protocol submits the  
        // full hash chain, which user verifies. This check therefore allows the searcher
        // not to have to worry about user+protocol collaboration to exploit the searcher. 
        require(proof.userCallHash == searcherCall.metaTx.userCallHash, ALTERED_USER_HASH);

        // Verify that the searcher's calldata is unaltered and being executed in the correct order
        proof.prove(searcherCall.metaTx.from, searcherCall.metaTx.data);

        // Execute the searcher call. 
        (bool success,) = ISearcherContract(searcherCall.metaTx.to).metaFlashCall{
            gas: gasLimit, 
            value: searcherCall.metaTx.value
        }(
            searcherCall.metaTx.from,
            searcherCall.metaTx.data,
            searcherCall.bids
        );

        // Verify that it was successful
        require(success, SEARCHER_CALL_REVERTED);
        require(ISafetyLocks(atlas).confirmSafetyCallback(), SEARCHER_FAILED_CALLBACK);

        // Verify that the searcher paid what they bid
        bool etherIsBidToken;
        i = 0;
        uint256 balance;

        for (; i < searcherCall.bids.length;) {
            
            // ERC20 tokens as bid currency
            if (!(searcherCall.bids[i].token == address(0))) {
                balance = ERC20(searcherCall.bids[i].token).balanceOf(address(this));
                require(
                    balance >= tokenBalances[i] + searcherCall.bids[i].bidAmount,
                    SEARCHER_BID_UNPAID
                );
            
            // Native Gas (Ether) as bid currency
            } else {
                balance = address(this).balance;
                require(
                    balance >= searcherCall.bids[i].bidAmount, // tokenBalances[i] = 0 for ether
                    SEARCHER_BID_UNPAID 
                );

                etherIsBidToken = true;
                
                // Transfer any surplus Ether back to escrow to add to searcher's balance
                if (balance > searcherCall.bids[i].bidAmount) {
                    SafeTransferLib.safeTransferETH(
                        atlas, 
                        balance - searcherCall.bids[i].bidAmount
                    );
                }
            }
            unchecked { ++i; }
        }

        if (!etherIsBidToken) {
            uint256 currentBalance = address(this).balance;
            if (currentBalance > 0) {
                SafeTransferLib.safeTransferETH(
                    atlas, 
                    currentBalance
                );
            }
        }

        // Verify that the searcher repaid their msg.value
        require(atlas.balance >= escrowBalance, SEARCHER_MSG_VALUE_UNPAID);
    }

    function allocateRewards(
        BidData[] calldata bids,
        PayeeData[] calldata payeeData
    ) external {
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

            unchecked{ 
                netBids[i].token = bids[i].token;
                netBids[i].bidAmount = bids[i].bidAmount - payment;
                ++i;
            }
        }

        if (_config().needsDelegateAllocating()) {
            (bool success,) = _control().delegatecall(
                abi.encodeWithSelector(
                    IProtocolControl.allocatingCall.selector,
                    totalEtherReward,
                    bids,
                    payeeData
                )
            );
            require(success, "ERR-EC02 DelegateRevert");
        
        } else {
            (bool success,) = _control().call{
                value: totalEtherReward
            }(
                abi.encodeWithSelector(
                    IProtocolControl.allocatingCall.selector,
                    totalEtherReward,
                    bids,
                    payeeData
                )
            );
            require(success, "ERR-EC04b CallRevert");
        }
    }

      ///////////////////////////////////////
     //  USER SUPPORT / ACCESS FUNCTIONS  //
    ///////////////////////////////////////
    function withdrawERC20(address token, uint256 amount) external {
        require(msg.sender == _user(), "ERR-EC01 NotEnvironmentOwner");

        if (ERC20(token).balanceOf(address(this)) >= amount) {
            SafeTransferLib.safeTransfer(
                ERC20(token), 
                msg.sender, 
                amount
            );

        } else {
            revert("ERR-EC02 BalanceTooLow");
        }
    }

    function factoryWithdrawERC20(address msgSender, address token, uint256 amount) external {
        require(msg.sender == atlas, "ERR-EC10 NotFactory");
        require(msgSender == _user(), "ERR-EC11 NotEnvironmentOwner");

        if (ERC20(token).balanceOf(address(this)) >= amount) {
            SafeTransferLib.safeTransfer(
                ERC20(token), 
                _user(), 
                amount
            );

        } else {
            revert("ERR-EC02 BalanceTooLow");
        }
    }

    function withdrawEther(uint256 amount) external {
        require(msg.sender == _user(), "ERR-EC01 NotEnvironmentOwner");

        if (address(this).balance >= amount) {
            SafeTransferLib.safeTransferETH(
                msg.sender, 
                amount
            );
            
        } else {
            revert("ERR-EC03 BalanceTooLow");
        }
    }

    function factoryWithdrawEther(address msgSender, uint256 amount) external {
        require(msg.sender == atlas, "ERR-EC10 NotFactory");
        require(msgSender == _user(), "ERR-EC11 NotEnvironmentOwner");

        if (address(this).balance >= amount) {
            SafeTransferLib.safeTransferETH(
                _user(), 
                amount
            );
            
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
