//SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.25 ^0.8.0 ^0.8.14 ^0.8.20 ^0.8.4;

// lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol

// OpenZeppelin Contracts (last updated v4.9.0) (token/ERC20/IERC20.sol)

/**
 * @dev Interface of the ERC20 standard as defined in the EIP.
 */
interface IERC20 {
    /**
     * @dev Emitted when `value` tokens are moved from one account (`from`) to
     * another (`to`).
     *
     * Note that `value` may be zero.
     */
    event Transfer(address indexed from, address indexed to, uint256 value);

    /**
     * @dev Emitted when the allowance of a `spender` for an `owner` is set by
     * a call to {approve}. `value` is the new allowance.
     */
    event Approval(address indexed owner, address indexed spender, uint256 value);

    /**
     * @dev Returns the amount of tokens in existence.
     */
    function totalSupply() external view returns (uint256);

    /**
     * @dev Returns the amount of tokens owned by `account`.
     */
    function balanceOf(address account) external view returns (uint256);

    /**
     * @dev Moves `amount` tokens from the caller's account to `to`.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transfer(address to, uint256 amount) external returns (bool);

    /**
     * @dev Returns the remaining number of tokens that `spender` will be
     * allowed to spend on behalf of `owner` through {transferFrom}. This is
     * zero by default.
     *
     * This value changes when {approve} or {transferFrom} are called.
     */
    function allowance(address owner, address spender) external view returns (uint256);

    /**
     * @dev Sets `amount` as the allowance of `spender` over the caller's tokens.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * IMPORTANT: Beware that changing an allowance with this method brings the risk
     * that someone may use both the old and the new allowance by unfortunate
     * transaction ordering. One possible solution to mitigate this race
     * condition is to first reduce the spender's allowance to 0 and set the
     * desired value afterwards:
     * https://github.com/ethereum/EIPs/issues/20#issuecomment-263524729
     *
     * Emits an {Approval} event.
     */
    function approve(address spender, uint256 amount) external returns (bool);

    /**
     * @dev Moves `amount` tokens from `from` to `to` using the
     * allowance mechanism. `amount` is then deducted from the caller's
     * allowance.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

// lib/openzeppelin-contracts/contracts/utils/Context.sol

// OpenZeppelin Contracts (last updated v4.9.4) (utils/Context.sol)

/**
 * @dev Provides information about the current execution context, including the
 * sender of the transaction and its data. While these are generally available
 * via msg.sender and msg.data, they should not be accessed in such a direct
 * manner, since when dealing with meta-transactions the account sending and
 * paying for execution may not be the actual sender (as far as an application
 * is concerned).
 *
 * This contract is only required for intermediate, library-like contracts.
 */
abstract contract Context_0 {
    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }

    function _msgData() internal view virtual returns (bytes calldata) {
        return msg.data;
    }

    function _contextSuffixLength() internal view virtual returns (uint256) {
        return 0;
    }
}

// lib/openzeppelin-contracts/contracts/utils/math/SafeCast.sol

// OpenZeppelin Contracts (last updated v4.8.0) (utils/math/SafeCast.sol)
// This file was procedurally generated from scripts/generate/templates/SafeCast.js.

/**
 * @dev Wrappers over Solidity's uintXX/intXX casting operators with added overflow
 * checks.
 *
 * Downcasting from uint256/int256 in Solidity does not revert on overflow. This can
 * easily result in undesired exploitation or bugs, since developers usually
 * assume that overflows raise errors. `SafeCast` restores this intuition by
 * reverting the transaction when such an operation overflows.
 *
 * Using this library instead of the unchecked operations eliminates an entire
 * class of bugs, so it's recommended to use it always.
 *
 * Can be combined with {SafeMath} and {SignedSafeMath} to extend it to smaller types, by performing
 * all math on `uint256` and `int256` and then downcasting.
 */
library SafeCast {
    /**
     * @dev Returns the downcasted uint248 from uint256, reverting on
     * overflow (when the input is greater than largest uint248).
     *
     * Counterpart to Solidity's `uint248` operator.
     *
     * Requirements:
     *
     * - input must fit into 248 bits
     *
     * _Available since v4.7._
     */
    function toUint248(uint256 value) internal pure returns (uint248) {
        require(value <= type(uint248).max, "SafeCast: value doesn't fit in 248 bits");
        return uint248(value);
    }

    /**
     * @dev Returns the downcasted uint240 from uint256, reverting on
     * overflow (when the input is greater than largest uint240).
     *
     * Counterpart to Solidity's `uint240` operator.
     *
     * Requirements:
     *
     * - input must fit into 240 bits
     *
     * _Available since v4.7._
     */
    function toUint240(uint256 value) internal pure returns (uint240) {
        require(value <= type(uint240).max, "SafeCast: value doesn't fit in 240 bits");
        return uint240(value);
    }

    /**
     * @dev Returns the downcasted uint232 from uint256, reverting on
     * overflow (when the input is greater than largest uint232).
     *
     * Counterpart to Solidity's `uint232` operator.
     *
     * Requirements:
     *
     * - input must fit into 232 bits
     *
     * _Available since v4.7._
     */
    function toUint232(uint256 value) internal pure returns (uint232) {
        require(value <= type(uint232).max, "SafeCast: value doesn't fit in 232 bits");
        return uint232(value);
    }

    /**
     * @dev Returns the downcasted uint224 from uint256, reverting on
     * overflow (when the input is greater than largest uint224).
     *
     * Counterpart to Solidity's `uint224` operator.
     *
     * Requirements:
     *
     * - input must fit into 224 bits
     *
     * _Available since v4.2._
     */
    function toUint224(uint256 value) internal pure returns (uint224) {
        require(value <= type(uint224).max, "SafeCast: value doesn't fit in 224 bits");
        return uint224(value);
    }

    /**
     * @dev Returns the downcasted uint216 from uint256, reverting on
     * overflow (when the input is greater than largest uint216).
     *
     * Counterpart to Solidity's `uint216` operator.
     *
     * Requirements:
     *
     * - input must fit into 216 bits
     *
     * _Available since v4.7._
     */
    function toUint216(uint256 value) internal pure returns (uint216) {
        require(value <= type(uint216).max, "SafeCast: value doesn't fit in 216 bits");
        return uint216(value);
    }

    /**
     * @dev Returns the downcasted uint208 from uint256, reverting on
     * overflow (when the input is greater than largest uint208).
     *
     * Counterpart to Solidity's `uint208` operator.
     *
     * Requirements:
     *
     * - input must fit into 208 bits
     *
     * _Available since v4.7._
     */
    function toUint208(uint256 value) internal pure returns (uint208) {
        require(value <= type(uint208).max, "SafeCast: value doesn't fit in 208 bits");
        return uint208(value);
    }

    /**
     * @dev Returns the downcasted uint200 from uint256, reverting on
     * overflow (when the input is greater than largest uint200).
     *
     * Counterpart to Solidity's `uint200` operator.
     *
     * Requirements:
     *
     * - input must fit into 200 bits
     *
     * _Available since v4.7._
     */
    function toUint200(uint256 value) internal pure returns (uint200) {
        require(value <= type(uint200).max, "SafeCast: value doesn't fit in 200 bits");
        return uint200(value);
    }

    /**
     * @dev Returns the downcasted uint192 from uint256, reverting on
     * overflow (when the input is greater than largest uint192).
     *
     * Counterpart to Solidity's `uint192` operator.
     *
     * Requirements:
     *
     * - input must fit into 192 bits
     *
     * _Available since v4.7._
     */
    function toUint192(uint256 value) internal pure returns (uint192) {
        require(value <= type(uint192).max, "SafeCast: value doesn't fit in 192 bits");
        return uint192(value);
    }

    /**
     * @dev Returns the downcasted uint184 from uint256, reverting on
     * overflow (when the input is greater than largest uint184).
     *
     * Counterpart to Solidity's `uint184` operator.
     *
     * Requirements:
     *
     * - input must fit into 184 bits
     *
     * _Available since v4.7._
     */
    function toUint184(uint256 value) internal pure returns (uint184) {
        require(value <= type(uint184).max, "SafeCast: value doesn't fit in 184 bits");
        return uint184(value);
    }

    /**
     * @dev Returns the downcasted uint176 from uint256, reverting on
     * overflow (when the input is greater than largest uint176).
     *
     * Counterpart to Solidity's `uint176` operator.
     *
     * Requirements:
     *
     * - input must fit into 176 bits
     *
     * _Available since v4.7._
     */
    function toUint176(uint256 value) internal pure returns (uint176) {
        require(value <= type(uint176).max, "SafeCast: value doesn't fit in 176 bits");
        return uint176(value);
    }

    /**
     * @dev Returns the downcasted uint168 from uint256, reverting on
     * overflow (when the input is greater than largest uint168).
     *
     * Counterpart to Solidity's `uint168` operator.
     *
     * Requirements:
     *
     * - input must fit into 168 bits
     *
     * _Available since v4.7._
     */
    function toUint168(uint256 value) internal pure returns (uint168) {
        require(value <= type(uint168).max, "SafeCast: value doesn't fit in 168 bits");
        return uint168(value);
    }

    /**
     * @dev Returns the downcasted uint160 from uint256, reverting on
     * overflow (when the input is greater than largest uint160).
     *
     * Counterpart to Solidity's `uint160` operator.
     *
     * Requirements:
     *
     * - input must fit into 160 bits
     *
     * _Available since v4.7._
     */
    function toUint160(uint256 value) internal pure returns (uint160) {
        require(value <= type(uint160).max, "SafeCast: value doesn't fit in 160 bits");
        return uint160(value);
    }

    /**
     * @dev Returns the downcasted uint152 from uint256, reverting on
     * overflow (when the input is greater than largest uint152).
     *
     * Counterpart to Solidity's `uint152` operator.
     *
     * Requirements:
     *
     * - input must fit into 152 bits
     *
     * _Available since v4.7._
     */
    function toUint152(uint256 value) internal pure returns (uint152) {
        require(value <= type(uint152).max, "SafeCast: value doesn't fit in 152 bits");
        return uint152(value);
    }

    /**
     * @dev Returns the downcasted uint144 from uint256, reverting on
     * overflow (when the input is greater than largest uint144).
     *
     * Counterpart to Solidity's `uint144` operator.
     *
     * Requirements:
     *
     * - input must fit into 144 bits
     *
     * _Available since v4.7._
     */
    function toUint144(uint256 value) internal pure returns (uint144) {
        require(value <= type(uint144).max, "SafeCast: value doesn't fit in 144 bits");
        return uint144(value);
    }

    /**
     * @dev Returns the downcasted uint136 from uint256, reverting on
     * overflow (when the input is greater than largest uint136).
     *
     * Counterpart to Solidity's `uint136` operator.
     *
     * Requirements:
     *
     * - input must fit into 136 bits
     *
     * _Available since v4.7._
     */
    function toUint136(uint256 value) internal pure returns (uint136) {
        require(value <= type(uint136).max, "SafeCast: value doesn't fit in 136 bits");
        return uint136(value);
    }

    /**
     * @dev Returns the downcasted uint128 from uint256, reverting on
     * overflow (when the input is greater than largest uint128).
     *
     * Counterpart to Solidity's `uint128` operator.
     *
     * Requirements:
     *
     * - input must fit into 128 bits
     *
     * _Available since v2.5._
     */
    function toUint128(uint256 value) internal pure returns (uint128) {
        require(value <= type(uint128).max, "SafeCast: value doesn't fit in 128 bits");
        return uint128(value);
    }

    /**
     * @dev Returns the downcasted uint120 from uint256, reverting on
     * overflow (when the input is greater than largest uint120).
     *
     * Counterpart to Solidity's `uint120` operator.
     *
     * Requirements:
     *
     * - input must fit into 120 bits
     *
     * _Available since v4.7._
     */
    function toUint120(uint256 value) internal pure returns (uint120) {
        require(value <= type(uint120).max, "SafeCast: value doesn't fit in 120 bits");
        return uint120(value);
    }

    /**
     * @dev Returns the downcasted uint112 from uint256, reverting on
     * overflow (when the input is greater than largest uint112).
     *
     * Counterpart to Solidity's `uint112` operator.
     *
     * Requirements:
     *
     * - input must fit into 112 bits
     *
     * _Available since v4.7._
     */
    function toUint112(uint256 value) internal pure returns (uint112) {
        require(value <= type(uint112).max, "SafeCast: value doesn't fit in 112 bits");
        return uint112(value);
    }

    /**
     * @dev Returns the downcasted uint104 from uint256, reverting on
     * overflow (when the input is greater than largest uint104).
     *
     * Counterpart to Solidity's `uint104` operator.
     *
     * Requirements:
     *
     * - input must fit into 104 bits
     *
     * _Available since v4.7._
     */
    function toUint104(uint256 value) internal pure returns (uint104) {
        require(value <= type(uint104).max, "SafeCast: value doesn't fit in 104 bits");
        return uint104(value);
    }

    /**
     * @dev Returns the downcasted uint96 from uint256, reverting on
     * overflow (when the input is greater than largest uint96).
     *
     * Counterpart to Solidity's `uint96` operator.
     *
     * Requirements:
     *
     * - input must fit into 96 bits
     *
     * _Available since v4.2._
     */
    function toUint96(uint256 value) internal pure returns (uint96) {
        require(value <= type(uint96).max, "SafeCast: value doesn't fit in 96 bits");
        return uint96(value);
    }

    /**
     * @dev Returns the downcasted uint88 from uint256, reverting on
     * overflow (when the input is greater than largest uint88).
     *
     * Counterpart to Solidity's `uint88` operator.
     *
     * Requirements:
     *
     * - input must fit into 88 bits
     *
     * _Available since v4.7._
     */
    function toUint88(uint256 value) internal pure returns (uint88) {
        require(value <= type(uint88).max, "SafeCast: value doesn't fit in 88 bits");
        return uint88(value);
    }

    /**
     * @dev Returns the downcasted uint80 from uint256, reverting on
     * overflow (when the input is greater than largest uint80).
     *
     * Counterpart to Solidity's `uint80` operator.
     *
     * Requirements:
     *
     * - input must fit into 80 bits
     *
     * _Available since v4.7._
     */
    function toUint80(uint256 value) internal pure returns (uint80) {
        require(value <= type(uint80).max, "SafeCast: value doesn't fit in 80 bits");
        return uint80(value);
    }

    /**
     * @dev Returns the downcasted uint72 from uint256, reverting on
     * overflow (when the input is greater than largest uint72).
     *
     * Counterpart to Solidity's `uint72` operator.
     *
     * Requirements:
     *
     * - input must fit into 72 bits
     *
     * _Available since v4.7._
     */
    function toUint72(uint256 value) internal pure returns (uint72) {
        require(value <= type(uint72).max, "SafeCast: value doesn't fit in 72 bits");
        return uint72(value);
    }

    /**
     * @dev Returns the downcasted uint64 from uint256, reverting on
     * overflow (when the input is greater than largest uint64).
     *
     * Counterpart to Solidity's `uint64` operator.
     *
     * Requirements:
     *
     * - input must fit into 64 bits
     *
     * _Available since v2.5._
     */
    function toUint64(uint256 value) internal pure returns (uint64) {
        require(value <= type(uint64).max, "SafeCast: value doesn't fit in 64 bits");
        return uint64(value);
    }

    /**
     * @dev Returns the downcasted uint56 from uint256, reverting on
     * overflow (when the input is greater than largest uint56).
     *
     * Counterpart to Solidity's `uint56` operator.
     *
     * Requirements:
     *
     * - input must fit into 56 bits
     *
     * _Available since v4.7._
     */
    function toUint56(uint256 value) internal pure returns (uint56) {
        require(value <= type(uint56).max, "SafeCast: value doesn't fit in 56 bits");
        return uint56(value);
    }

    /**
     * @dev Returns the downcasted uint48 from uint256, reverting on
     * overflow (when the input is greater than largest uint48).
     *
     * Counterpart to Solidity's `uint48` operator.
     *
     * Requirements:
     *
     * - input must fit into 48 bits
     *
     * _Available since v4.7._
     */
    function toUint48(uint256 value) internal pure returns (uint48) {
        require(value <= type(uint48).max, "SafeCast: value doesn't fit in 48 bits");
        return uint48(value);
    }

    /**
     * @dev Returns the downcasted uint40 from uint256, reverting on
     * overflow (when the input is greater than largest uint40).
     *
     * Counterpart to Solidity's `uint40` operator.
     *
     * Requirements:
     *
     * - input must fit into 40 bits
     *
     * _Available since v4.7._
     */
    function toUint40(uint256 value) internal pure returns (uint40) {
        require(value <= type(uint40).max, "SafeCast: value doesn't fit in 40 bits");
        return uint40(value);
    }

    /**
     * @dev Returns the downcasted uint32 from uint256, reverting on
     * overflow (when the input is greater than largest uint32).
     *
     * Counterpart to Solidity's `uint32` operator.
     *
     * Requirements:
     *
     * - input must fit into 32 bits
     *
     * _Available since v2.5._
     */
    function toUint32(uint256 value) internal pure returns (uint32) {
        require(value <= type(uint32).max, "SafeCast: value doesn't fit in 32 bits");
        return uint32(value);
    }

    /**
     * @dev Returns the downcasted uint24 from uint256, reverting on
     * overflow (when the input is greater than largest uint24).
     *
     * Counterpart to Solidity's `uint24` operator.
     *
     * Requirements:
     *
     * - input must fit into 24 bits
     *
     * _Available since v4.7._
     */
    function toUint24(uint256 value) internal pure returns (uint24) {
        require(value <= type(uint24).max, "SafeCast: value doesn't fit in 24 bits");
        return uint24(value);
    }

    /**
     * @dev Returns the downcasted uint16 from uint256, reverting on
     * overflow (when the input is greater than largest uint16).
     *
     * Counterpart to Solidity's `uint16` operator.
     *
     * Requirements:
     *
     * - input must fit into 16 bits
     *
     * _Available since v2.5._
     */
    function toUint16(uint256 value) internal pure returns (uint16) {
        require(value <= type(uint16).max, "SafeCast: value doesn't fit in 16 bits");
        return uint16(value);
    }

    /**
     * @dev Returns the downcasted uint8 from uint256, reverting on
     * overflow (when the input is greater than largest uint8).
     *
     * Counterpart to Solidity's `uint8` operator.
     *
     * Requirements:
     *
     * - input must fit into 8 bits
     *
     * _Available since v2.5._
     */
    function toUint8(uint256 value) internal pure returns (uint8) {
        require(value <= type(uint8).max, "SafeCast: value doesn't fit in 8 bits");
        return uint8(value);
    }

    /**
     * @dev Converts a signed int256 into an unsigned uint256.
     *
     * Requirements:
     *
     * - input must be greater than or equal to 0.
     *
     * _Available since v3.0._
     */
    function toUint256(int256 value) internal pure returns (uint256) {
        require(value >= 0, "SafeCast: value must be positive");
        return uint256(value);
    }

    /**
     * @dev Returns the downcasted int248 from int256, reverting on
     * overflow (when the input is less than smallest int248 or
     * greater than largest int248).
     *
     * Counterpart to Solidity's `int248` operator.
     *
     * Requirements:
     *
     * - input must fit into 248 bits
     *
     * _Available since v4.7._
     */
    function toInt248(int256 value) internal pure returns (int248 downcasted) {
        downcasted = int248(value);
        require(downcasted == value, "SafeCast: value doesn't fit in 248 bits");
    }

    /**
     * @dev Returns the downcasted int240 from int256, reverting on
     * overflow (when the input is less than smallest int240 or
     * greater than largest int240).
     *
     * Counterpart to Solidity's `int240` operator.
     *
     * Requirements:
     *
     * - input must fit into 240 bits
     *
     * _Available since v4.7._
     */
    function toInt240(int256 value) internal pure returns (int240 downcasted) {
        downcasted = int240(value);
        require(downcasted == value, "SafeCast: value doesn't fit in 240 bits");
    }

    /**
     * @dev Returns the downcasted int232 from int256, reverting on
     * overflow (when the input is less than smallest int232 or
     * greater than largest int232).
     *
     * Counterpart to Solidity's `int232` operator.
     *
     * Requirements:
     *
     * - input must fit into 232 bits
     *
     * _Available since v4.7._
     */
    function toInt232(int256 value) internal pure returns (int232 downcasted) {
        downcasted = int232(value);
        require(downcasted == value, "SafeCast: value doesn't fit in 232 bits");
    }

    /**
     * @dev Returns the downcasted int224 from int256, reverting on
     * overflow (when the input is less than smallest int224 or
     * greater than largest int224).
     *
     * Counterpart to Solidity's `int224` operator.
     *
     * Requirements:
     *
     * - input must fit into 224 bits
     *
     * _Available since v4.7._
     */
    function toInt224(int256 value) internal pure returns (int224 downcasted) {
        downcasted = int224(value);
        require(downcasted == value, "SafeCast: value doesn't fit in 224 bits");
    }

    /**
     * @dev Returns the downcasted int216 from int256, reverting on
     * overflow (when the input is less than smallest int216 or
     * greater than largest int216).
     *
     * Counterpart to Solidity's `int216` operator.
     *
     * Requirements:
     *
     * - input must fit into 216 bits
     *
     * _Available since v4.7._
     */
    function toInt216(int256 value) internal pure returns (int216 downcasted) {
        downcasted = int216(value);
        require(downcasted == value, "SafeCast: value doesn't fit in 216 bits");
    }

    /**
     * @dev Returns the downcasted int208 from int256, reverting on
     * overflow (when the input is less than smallest int208 or
     * greater than largest int208).
     *
     * Counterpart to Solidity's `int208` operator.
     *
     * Requirements:
     *
     * - input must fit into 208 bits
     *
     * _Available since v4.7._
     */
    function toInt208(int256 value) internal pure returns (int208 downcasted) {
        downcasted = int208(value);
        require(downcasted == value, "SafeCast: value doesn't fit in 208 bits");
    }

    /**
     * @dev Returns the downcasted int200 from int256, reverting on
     * overflow (when the input is less than smallest int200 or
     * greater than largest int200).
     *
     * Counterpart to Solidity's `int200` operator.
     *
     * Requirements:
     *
     * - input must fit into 200 bits
     *
     * _Available since v4.7._
     */
    function toInt200(int256 value) internal pure returns (int200 downcasted) {
        downcasted = int200(value);
        require(downcasted == value, "SafeCast: value doesn't fit in 200 bits");
    }

    /**
     * @dev Returns the downcasted int192 from int256, reverting on
     * overflow (when the input is less than smallest int192 or
     * greater than largest int192).
     *
     * Counterpart to Solidity's `int192` operator.
     *
     * Requirements:
     *
     * - input must fit into 192 bits
     *
     * _Available since v4.7._
     */
    function toInt192(int256 value) internal pure returns (int192 downcasted) {
        downcasted = int192(value);
        require(downcasted == value, "SafeCast: value doesn't fit in 192 bits");
    }

    /**
     * @dev Returns the downcasted int184 from int256, reverting on
     * overflow (when the input is less than smallest int184 or
     * greater than largest int184).
     *
     * Counterpart to Solidity's `int184` operator.
     *
     * Requirements:
     *
     * - input must fit into 184 bits
     *
     * _Available since v4.7._
     */
    function toInt184(int256 value) internal pure returns (int184 downcasted) {
        downcasted = int184(value);
        require(downcasted == value, "SafeCast: value doesn't fit in 184 bits");
    }

    /**
     * @dev Returns the downcasted int176 from int256, reverting on
     * overflow (when the input is less than smallest int176 or
     * greater than largest int176).
     *
     * Counterpart to Solidity's `int176` operator.
     *
     * Requirements:
     *
     * - input must fit into 176 bits
     *
     * _Available since v4.7._
     */
    function toInt176(int256 value) internal pure returns (int176 downcasted) {
        downcasted = int176(value);
        require(downcasted == value, "SafeCast: value doesn't fit in 176 bits");
    }

    /**
     * @dev Returns the downcasted int168 from int256, reverting on
     * overflow (when the input is less than smallest int168 or
     * greater than largest int168).
     *
     * Counterpart to Solidity's `int168` operator.
     *
     * Requirements:
     *
     * - input must fit into 168 bits
     *
     * _Available since v4.7._
     */
    function toInt168(int256 value) internal pure returns (int168 downcasted) {
        downcasted = int168(value);
        require(downcasted == value, "SafeCast: value doesn't fit in 168 bits");
    }

    /**
     * @dev Returns the downcasted int160 from int256, reverting on
     * overflow (when the input is less than smallest int160 or
     * greater than largest int160).
     *
     * Counterpart to Solidity's `int160` operator.
     *
     * Requirements:
     *
     * - input must fit into 160 bits
     *
     * _Available since v4.7._
     */
    function toInt160(int256 value) internal pure returns (int160 downcasted) {
        downcasted = int160(value);
        require(downcasted == value, "SafeCast: value doesn't fit in 160 bits");
    }

    /**
     * @dev Returns the downcasted int152 from int256, reverting on
     * overflow (when the input is less than smallest int152 or
     * greater than largest int152).
     *
     * Counterpart to Solidity's `int152` operator.
     *
     * Requirements:
     *
     * - input must fit into 152 bits
     *
     * _Available since v4.7._
     */
    function toInt152(int256 value) internal pure returns (int152 downcasted) {
        downcasted = int152(value);
        require(downcasted == value, "SafeCast: value doesn't fit in 152 bits");
    }

    /**
     * @dev Returns the downcasted int144 from int256, reverting on
     * overflow (when the input is less than smallest int144 or
     * greater than largest int144).
     *
     * Counterpart to Solidity's `int144` operator.
     *
     * Requirements:
     *
     * - input must fit into 144 bits
     *
     * _Available since v4.7._
     */
    function toInt144(int256 value) internal pure returns (int144 downcasted) {
        downcasted = int144(value);
        require(downcasted == value, "SafeCast: value doesn't fit in 144 bits");
    }

    /**
     * @dev Returns the downcasted int136 from int256, reverting on
     * overflow (when the input is less than smallest int136 or
     * greater than largest int136).
     *
     * Counterpart to Solidity's `int136` operator.
     *
     * Requirements:
     *
     * - input must fit into 136 bits
     *
     * _Available since v4.7._
     */
    function toInt136(int256 value) internal pure returns (int136 downcasted) {
        downcasted = int136(value);
        require(downcasted == value, "SafeCast: value doesn't fit in 136 bits");
    }

    /**
     * @dev Returns the downcasted int128 from int256, reverting on
     * overflow (when the input is less than smallest int128 or
     * greater than largest int128).
     *
     * Counterpart to Solidity's `int128` operator.
     *
     * Requirements:
     *
     * - input must fit into 128 bits
     *
     * _Available since v3.1._
     */
    function toInt128(int256 value) internal pure returns (int128 downcasted) {
        downcasted = int128(value);
        require(downcasted == value, "SafeCast: value doesn't fit in 128 bits");
    }

    /**
     * @dev Returns the downcasted int120 from int256, reverting on
     * overflow (when the input is less than smallest int120 or
     * greater than largest int120).
     *
     * Counterpart to Solidity's `int120` operator.
     *
     * Requirements:
     *
     * - input must fit into 120 bits
     *
     * _Available since v4.7._
     */
    function toInt120(int256 value) internal pure returns (int120 downcasted) {
        downcasted = int120(value);
        require(downcasted == value, "SafeCast: value doesn't fit in 120 bits");
    }

    /**
     * @dev Returns the downcasted int112 from int256, reverting on
     * overflow (when the input is less than smallest int112 or
     * greater than largest int112).
     *
     * Counterpart to Solidity's `int112` operator.
     *
     * Requirements:
     *
     * - input must fit into 112 bits
     *
     * _Available since v4.7._
     */
    function toInt112(int256 value) internal pure returns (int112 downcasted) {
        downcasted = int112(value);
        require(downcasted == value, "SafeCast: value doesn't fit in 112 bits");
    }

    /**
     * @dev Returns the downcasted int104 from int256, reverting on
     * overflow (when the input is less than smallest int104 or
     * greater than largest int104).
     *
     * Counterpart to Solidity's `int104` operator.
     *
     * Requirements:
     *
     * - input must fit into 104 bits
     *
     * _Available since v4.7._
     */
    function toInt104(int256 value) internal pure returns (int104 downcasted) {
        downcasted = int104(value);
        require(downcasted == value, "SafeCast: value doesn't fit in 104 bits");
    }

    /**
     * @dev Returns the downcasted int96 from int256, reverting on
     * overflow (when the input is less than smallest int96 or
     * greater than largest int96).
     *
     * Counterpart to Solidity's `int96` operator.
     *
     * Requirements:
     *
     * - input must fit into 96 bits
     *
     * _Available since v4.7._
     */
    function toInt96(int256 value) internal pure returns (int96 downcasted) {
        downcasted = int96(value);
        require(downcasted == value, "SafeCast: value doesn't fit in 96 bits");
    }

    /**
     * @dev Returns the downcasted int88 from int256, reverting on
     * overflow (when the input is less than smallest int88 or
     * greater than largest int88).
     *
     * Counterpart to Solidity's `int88` operator.
     *
     * Requirements:
     *
     * - input must fit into 88 bits
     *
     * _Available since v4.7._
     */
    function toInt88(int256 value) internal pure returns (int88 downcasted) {
        downcasted = int88(value);
        require(downcasted == value, "SafeCast: value doesn't fit in 88 bits");
    }

    /**
     * @dev Returns the downcasted int80 from int256, reverting on
     * overflow (when the input is less than smallest int80 or
     * greater than largest int80).
     *
     * Counterpart to Solidity's `int80` operator.
     *
     * Requirements:
     *
     * - input must fit into 80 bits
     *
     * _Available since v4.7._
     */
    function toInt80(int256 value) internal pure returns (int80 downcasted) {
        downcasted = int80(value);
        require(downcasted == value, "SafeCast: value doesn't fit in 80 bits");
    }

    /**
     * @dev Returns the downcasted int72 from int256, reverting on
     * overflow (when the input is less than smallest int72 or
     * greater than largest int72).
     *
     * Counterpart to Solidity's `int72` operator.
     *
     * Requirements:
     *
     * - input must fit into 72 bits
     *
     * _Available since v4.7._
     */
    function toInt72(int256 value) internal pure returns (int72 downcasted) {
        downcasted = int72(value);
        require(downcasted == value, "SafeCast: value doesn't fit in 72 bits");
    }

    /**
     * @dev Returns the downcasted int64 from int256, reverting on
     * overflow (when the input is less than smallest int64 or
     * greater than largest int64).
     *
     * Counterpart to Solidity's `int64` operator.
     *
     * Requirements:
     *
     * - input must fit into 64 bits
     *
     * _Available since v3.1._
     */
    function toInt64(int256 value) internal pure returns (int64 downcasted) {
        downcasted = int64(value);
        require(downcasted == value, "SafeCast: value doesn't fit in 64 bits");
    }

    /**
     * @dev Returns the downcasted int56 from int256, reverting on
     * overflow (when the input is less than smallest int56 or
     * greater than largest int56).
     *
     * Counterpart to Solidity's `int56` operator.
     *
     * Requirements:
     *
     * - input must fit into 56 bits
     *
     * _Available since v4.7._
     */
    function toInt56(int256 value) internal pure returns (int56 downcasted) {
        downcasted = int56(value);
        require(downcasted == value, "SafeCast: value doesn't fit in 56 bits");
    }

    /**
     * @dev Returns the downcasted int48 from int256, reverting on
     * overflow (when the input is less than smallest int48 or
     * greater than largest int48).
     *
     * Counterpart to Solidity's `int48` operator.
     *
     * Requirements:
     *
     * - input must fit into 48 bits
     *
     * _Available since v4.7._
     */
    function toInt48(int256 value) internal pure returns (int48 downcasted) {
        downcasted = int48(value);
        require(downcasted == value, "SafeCast: value doesn't fit in 48 bits");
    }

    /**
     * @dev Returns the downcasted int40 from int256, reverting on
     * overflow (when the input is less than smallest int40 or
     * greater than largest int40).
     *
     * Counterpart to Solidity's `int40` operator.
     *
     * Requirements:
     *
     * - input must fit into 40 bits
     *
     * _Available since v4.7._
     */
    function toInt40(int256 value) internal pure returns (int40 downcasted) {
        downcasted = int40(value);
        require(downcasted == value, "SafeCast: value doesn't fit in 40 bits");
    }

    /**
     * @dev Returns the downcasted int32 from int256, reverting on
     * overflow (when the input is less than smallest int32 or
     * greater than largest int32).
     *
     * Counterpart to Solidity's `int32` operator.
     *
     * Requirements:
     *
     * - input must fit into 32 bits
     *
     * _Available since v3.1._
     */
    function toInt32(int256 value) internal pure returns (int32 downcasted) {
        downcasted = int32(value);
        require(downcasted == value, "SafeCast: value doesn't fit in 32 bits");
    }

    /**
     * @dev Returns the downcasted int24 from int256, reverting on
     * overflow (when the input is less than smallest int24 or
     * greater than largest int24).
     *
     * Counterpart to Solidity's `int24` operator.
     *
     * Requirements:
     *
     * - input must fit into 24 bits
     *
     * _Available since v4.7._
     */
    function toInt24(int256 value) internal pure returns (int24 downcasted) {
        downcasted = int24(value);
        require(downcasted == value, "SafeCast: value doesn't fit in 24 bits");
    }

    /**
     * @dev Returns the downcasted int16 from int256, reverting on
     * overflow (when the input is less than smallest int16 or
     * greater than largest int16).
     *
     * Counterpart to Solidity's `int16` operator.
     *
     * Requirements:
     *
     * - input must fit into 16 bits
     *
     * _Available since v3.1._
     */
    function toInt16(int256 value) internal pure returns (int16 downcasted) {
        downcasted = int16(value);
        require(downcasted == value, "SafeCast: value doesn't fit in 16 bits");
    }

    /**
     * @dev Returns the downcasted int8 from int256, reverting on
     * overflow (when the input is less than smallest int8 or
     * greater than largest int8).
     *
     * Counterpart to Solidity's `int8` operator.
     *
     * Requirements:
     *
     * - input must fit into 8 bits
     *
     * _Available since v3.1._
     */
    function toInt8(int256 value) internal pure returns (int8 downcasted) {
        downcasted = int8(value);
        require(downcasted == value, "SafeCast: value doesn't fit in 8 bits");
    }

    /**
     * @dev Converts an unsigned uint256 into a signed int256.
     *
     * Requirements:
     *
     * - input must be less than or equal to maxInt256.
     *
     * _Available since v3.0._
     */
    function toInt256(uint256 value) internal pure returns (int256) {
        // Note: Unsafe cast below is okay because `type(int256).max` is guaranteed to be positive
        require(value <= uint256(type(int256).max), "SafeCast: value doesn't fit in an int256");
        return int256(value);
    }
}

// lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol

// OpenZeppelin Contracts (last updated v5.0.0) (proxy/utils/Initializable.sol)

/**
 * @dev This is a base contract to aid in writing upgradeable contracts, or any kind of contract that will be deployed
 * behind a proxy. Since proxied contracts do not make use of a constructor, it's common to move constructor logic to an
 * external initializer function, usually called `initialize`. It then becomes necessary to protect this initializer
 * function so it can only be called once. The {initializer} modifier provided by this contract will have this effect.
 *
 * The initialization functions use a version number. Once a version number is used, it is consumed and cannot be
 * reused. This mechanism prevents re-execution of each "step" but allows the creation of new initialization steps in
 * case an upgrade adds a module that needs to be initialized.
 *
 * For example:
 *
 * [.hljs-theme-light.nopadding]
 * ```solidity
 * contract MyToken is ERC20Upgradeable {
 *     function initialize() initializer public {
 *         __ERC20_init("MyToken", "MTK");
 *     }
 * }
 *
 * contract MyTokenV2 is MyToken, ERC20PermitUpgradeable {
 *     function initializeV2() reinitializer(2) public {
 *         __ERC20Permit_init("MyToken");
 *     }
 * }
 * ```
 *
 * TIP: To avoid leaving the proxy in an uninitialized state, the initializer function should be called as early as
 * possible by providing the encoded function call as the `_data` argument to {ERC1967Proxy-constructor}.
 *
 * CAUTION: When used with inheritance, manual care must be taken to not invoke a parent initializer twice, or to ensure
 * that all initializers are idempotent. This is not verified automatically as constructors are by Solidity.
 *
 * [CAUTION]
 * ====
 * Avoid leaving a contract uninitialized.
 *
 * An uninitialized contract can be taken over by an attacker. This applies to both a proxy and its implementation
 * contract, which may impact the proxy. To prevent the implementation contract from being used, you should invoke
 * the {_disableInitializers} function in the constructor to automatically lock it when it is deployed:
 *
 * [.hljs-theme-light.nopadding]
 * ```
 * /// @custom:oz-upgrades-unsafe-allow constructor
 * constructor() {
 *     _disableInitializers();
 * }
 * ```
 * ====
 */
abstract contract Initializable {
    /**
     * @dev Storage of the initializable contract.
     *
     * It's implemented on a custom ERC-7201 namespace to reduce the risk of storage collisions
     * when using with upgradeable contracts.
     *
     * @custom:storage-location erc7201:openzeppelin.storage.Initializable
     */
    struct InitializableStorage {
        /**
         * @dev Indicates that the contract has been initialized.
         */
        uint64 _initialized;
        /**
         * @dev Indicates that the contract is in the process of being initialized.
         */
        bool _initializing;
    }

    // keccak256(abi.encode(uint256(keccak256("openzeppelin.storage.Initializable")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant INITIALIZABLE_STORAGE = 0xf0c57e16840df040f15088dc2f81fe391c3923bec73e23a9662efc9c229c6a00;

    /**
     * @dev The contract is already initialized.
     */
    error InvalidInitialization();

    /**
     * @dev The contract is not initializing.
     */
    error NotInitializing();

    /**
     * @dev Triggered when the contract has been initialized or reinitialized.
     */
    event Initialized(uint64 version);

    /**
     * @dev A modifier that defines a protected initializer function that can be invoked at most once. In its scope,
     * `onlyInitializing` functions can be used to initialize parent contracts.
     *
     * Similar to `reinitializer(1)`, except that in the context of a constructor an `initializer` may be invoked any
     * number of times. This behavior in the constructor can be useful during testing and is not expected to be used in
     * production.
     *
     * Emits an {Initialized} event.
     */
    modifier initializer() {
        // solhint-disable-next-line var-name-mixedcase
        InitializableStorage storage $ = _getInitializableStorage();

        // Cache values to avoid duplicated sloads
        bool isTopLevelCall = !$._initializing;
        uint64 initialized = $._initialized;

        // Allowed calls:
        // - initialSetup: the contract is not in the initializing state and no previous version was
        //                 initialized
        // - construction: the contract is initialized at version 1 (no reininitialization) and the
        //                 current contract is just being deployed
        bool initialSetup = initialized == 0 && isTopLevelCall;
        bool construction = initialized == 1 && address(this).code.length == 0;

        if (!initialSetup && !construction) {
            revert InvalidInitialization();
        }
        $._initialized = 1;
        if (isTopLevelCall) {
            $._initializing = true;
        }
        _;
        if (isTopLevelCall) {
            $._initializing = false;
            emit Initialized(1);
        }
    }

    /**
     * @dev A modifier that defines a protected reinitializer function that can be invoked at most once, and only if the
     * contract hasn't been initialized to a greater version before. In its scope, `onlyInitializing` functions can be
     * used to initialize parent contracts.
     *
     * A reinitializer may be used after the original initialization step. This is essential to configure modules that
     * are added through upgrades and that require initialization.
     *
     * When `version` is 1, this modifier is similar to `initializer`, except that functions marked with `reinitializer`
     * cannot be nested. If one is invoked in the context of another, execution will revert.
     *
     * Note that versions can jump in increments greater than 1; this implies that if multiple reinitializers coexist in
     * a contract, executing them in the right order is up to the developer or operator.
     *
     * WARNING: Setting the version to 2**64 - 1 will prevent any future reinitialization.
     *
     * Emits an {Initialized} event.
     */
    modifier reinitializer(uint64 version) {
        // solhint-disable-next-line var-name-mixedcase
        InitializableStorage storage $ = _getInitializableStorage();

        if ($._initializing || $._initialized >= version) {
            revert InvalidInitialization();
        }
        $._initialized = version;
        $._initializing = true;
        _;
        $._initializing = false;
        emit Initialized(version);
    }

    /**
     * @dev Modifier to protect an initialization function so that it can only be invoked by functions with the
     * {initializer} and {reinitializer} modifiers, directly or indirectly.
     */
    modifier onlyInitializing() {
        _checkInitializing();
        _;
    }

    /**
     * @dev Reverts if the contract is not in an initializing state. See {onlyInitializing}.
     */
    function _checkInitializing() internal view virtual {
        if (!_isInitializing()) {
            revert NotInitializing();
        }
    }

    /**
     * @dev Locks the contract, preventing any future reinitialization. This cannot be part of an initializer call.
     * Calling this in the constructor of a contract will prevent that contract from being initialized or reinitialized
     * to any version. It is recommended to use this to lock implementation contracts that are designed to be called
     * through proxies.
     *
     * Emits an {Initialized} event the first time it is successfully executed.
     */
    function _disableInitializers() internal virtual {
        // solhint-disable-next-line var-name-mixedcase
        InitializableStorage storage $ = _getInitializableStorage();

        if ($._initializing) {
            revert InvalidInitialization();
        }
        if ($._initialized != type(uint64).max) {
            $._initialized = type(uint64).max;
            emit Initialized(type(uint64).max);
        }
    }

    /**
     * @dev Returns the highest version that has been initialized. See {reinitializer}.
     */
    function _getInitializedVersion() internal view returns (uint64) {
        return _getInitializableStorage()._initialized;
    }

    /**
     * @dev Returns `true` if the contract is currently initializing. See {onlyInitializing}.
     */
    function _isInitializing() internal view returns (bool) {
        return _getInitializableStorage()._initializing;
    }

    /**
     * @dev Returns a pointer to the storage namespace.
     */
    // solhint-disable-next-line var-name-mixedcase
    function _getInitializableStorage() private pure returns (InitializableStorage storage $) {
        assembly {
            $.slot := INITIALIZABLE_STORAGE
        }
    }
}

// lib/redstone-oracles-monorepo/packages/evm-connector/contracts/core/RedstoneConstants.sol

/**
 * @title The base contract with helpful constants
 * @author The Redstone Oracles team
 * @dev It mainly contains redstone-related values, which improve readability
 * of other contracts (e.g. CalldataExtractor and RedstoneConsumerBase)
 */
contract RedstoneConstants {
  // === Abbreviations ===
  // BS - Bytes size
  // PTR - Pointer (memory location)
  // SIG - Signature

  // Solidity and YUL constants
  uint256 internal constant STANDARD_SLOT_BS = 32;
  uint256 internal constant FREE_MEMORY_PTR = 0x40;
  uint256 internal constant BYTES_ARR_LEN_VAR_BS = 32;
  uint256 internal constant FUNCTION_SIGNATURE_BS = 4;
  uint256 internal constant REVERT_MSG_OFFSET = 68; // Revert message structure described here: https://ethereum.stackexchange.com/a/66173/106364
  uint256 internal constant STRING_ERR_MESSAGE_MASK = 0x08c379a000000000000000000000000000000000000000000000000000000000;

  // RedStone protocol consts
  uint256 internal constant SIG_BS = 65;
  uint256 internal constant TIMESTAMP_BS = 6;
  uint256 internal constant DATA_PACKAGES_COUNT_BS = 2;
  uint256 internal constant DATA_POINTS_COUNT_BS = 3;
  uint256 internal constant DATA_POINT_VALUE_BYTE_SIZE_BS = 4;
  uint256 internal constant DATA_POINT_SYMBOL_BS = 32;
  uint256 internal constant DEFAULT_DATA_POINT_VALUE_BS = 32;
  uint256 internal constant UNSIGNED_METADATA_BYTE_SIZE_BS = 3;
  uint256 internal constant REDSTONE_MARKER_BS = 9; // byte size of 0x000002ed57011e0000
  uint256 internal constant REDSTONE_MARKER_MASK = 0x0000000000000000000000000000000000000000000000000002ed57011e0000;

  // Derived values (based on consts)
  uint256 internal constant TIMESTAMP_NEGATIVE_OFFSET_IN_DATA_PACKAGE_WITH_STANDARD_SLOT_BS = 104; // SIG_BS + DATA_POINTS_COUNT_BS + DATA_POINT_VALUE_BYTE_SIZE_BS + STANDARD_SLOT_BS
  uint256 internal constant DATA_PACKAGE_WITHOUT_DATA_POINTS_BS = 78; // DATA_POINT_VALUE_BYTE_SIZE_BS + TIMESTAMP_BS + DATA_POINTS_COUNT_BS + SIG_BS
  uint256 internal constant DATA_PACKAGE_WITHOUT_DATA_POINTS_AND_SIG_BS = 13; // DATA_POINT_VALUE_BYTE_SIZE_BS + TIMESTAMP_BS + DATA_POINTS_COUNT_BS
  uint256 internal constant REDSTONE_MARKER_BS_PLUS_STANDARD_SLOT_BS = 41; // REDSTONE_MARKER_BS + STANDARD_SLOT_BS

  // Error messages
  error CalldataOverOrUnderFlow();
  error IncorrectUnsignedMetadataSize();
  error InsufficientNumberOfUniqueSigners(uint256 receivedSignersCount, uint256 requiredSignersCount);
  error EachSignerMustProvideTheSameValue();
  error EmptyCalldataPointersArr();
  error InvalidCalldataPointer();
  error CalldataMustHaveValidPayload();
  error SignerNotAuthorised(address receivedSigner);
  error DataTimestampCannotBeZero();
  error TimestampsMustBeEqual();
}

// lib/redstone-oracles-monorepo/packages/evm-connector/contracts/libs/BitmapLib.sol

library BitmapLib {
  function setBitInBitmap(uint256 bitmap, uint256 bitIndex) internal pure returns (uint256) {
    return bitmap | (1 << bitIndex);
  }

  function getBitFromBitmap(uint256 bitmap, uint256 bitIndex) internal pure returns (bool) {
    uint256 bitAtIndex = bitmap & (1 << bitIndex);
    return bitAtIndex > 0;
  }
}

// lib/redstone-oracles-monorepo/packages/evm-connector/contracts/libs/NumericArrayLib.sol

library NumericArrayLib {
  // This function sort array in memory using bubble sort algorithm,
  // which performs even better than quick sort for small arrays

  uint256 constant BYTES_ARR_LEN_VAR_BS = 32;
  uint256 constant UINT256_VALUE_BS = 32;

  error CanNotPickMedianOfEmptyArray();

  // This function modifies the array
  function pickMedian(uint256[] memory arr) internal pure returns (uint256) {
    if (arr.length == 2) {
      return (arr[0] + arr[1]) / 2;
    }
    if (arr.length == 0) {
      revert CanNotPickMedianOfEmptyArray();
    }
    sort(arr);
    uint256 middleIndex = arr.length / 2;
    if (arr.length % 2 == 0) {
      uint256 sum = arr[middleIndex - 1] + arr[middleIndex];
      return sum / 2;
    } else {
      return arr[middleIndex];
    }
  }

  function sort(uint256[] memory arr) internal pure {
    assembly {
      let arrLength := mload(arr)
      let valuesPtr := add(arr, BYTES_ARR_LEN_VAR_BS)
      let endPtr := add(valuesPtr, mul(arrLength, UINT256_VALUE_BS))
      for {
        let arrIPtr := valuesPtr
      } lt(arrIPtr, endPtr) {
        arrIPtr := add(arrIPtr, UINT256_VALUE_BS) // arrIPtr += 32
      } {
        for {
          let arrJPtr := valuesPtr
        } lt(arrJPtr, arrIPtr) {
          arrJPtr := add(arrJPtr, UINT256_VALUE_BS) // arrJPtr += 32
        } {
          let arrI := mload(arrIPtr)
          let arrJ := mload(arrJPtr)
          if lt(arrI, arrJ) {
            mstore(arrIPtr, arrJ)
            mstore(arrJPtr, arrI)
          }
        }
      }
    }
  }
}

// lib/redstone-oracles-monorepo/packages/evm-connector/contracts/libs/SignatureLib.sol

library SignatureLib {
  uint256 constant ECDSA_SIG_R_BS = 32;
  uint256 constant ECDSA_SIG_S_BS = 32;

  function recoverSignerAddress(bytes32 signedHash, uint256 signatureCalldataNegativeOffset)
    internal
    pure
    returns (address)
  {
    bytes32 r;
    bytes32 s;
    uint8 v;
    assembly {
      let signatureCalldataStartPos := sub(calldatasize(), signatureCalldataNegativeOffset)
      r := calldataload(signatureCalldataStartPos)
      signatureCalldataStartPos := add(signatureCalldataStartPos, ECDSA_SIG_R_BS)
      s := calldataload(signatureCalldataStartPos)
      signatureCalldataStartPos := add(signatureCalldataStartPos, ECDSA_SIG_S_BS)
      v := byte(0, calldataload(signatureCalldataStartPos)) // last byte of the signature memory array
    }
    return ecrecover(signedHash, v, r, s);
  }
}

// lib/redstone-oracles-monorepo/packages/on-chain-relayer/contracts/core/IRedstoneAdapter.sol

/**
 * @title Interface of RedStone adapter
 * @author The Redstone Oracles team
 */
interface IRedstoneAdapter {

  /**
   * @notice Updates values of all data feeds supported by the Adapter contract
   * @dev This function requires an attached redstone payload to the transaction calldata.
   * It also requires each data package to have exactly the same timestamp
   * @param dataPackagesTimestamp Timestamp of each signed data package in the redstone payload
   */
  function updateDataFeedsValues(uint256 dataPackagesTimestamp) external;

  /**
   * @notice Returns the latest properly reported value of the data feed
   * @param dataFeedId The identifier of the requested data feed
   * @return value The latest value of the given data feed
   */
  function getValueForDataFeed(bytes32 dataFeedId) external view returns (uint256);

  /**
   * @notice Returns the latest properly reported values for several data feeds
   * @param requestedDataFeedIds The array of identifiers for the requested feeds
   * @return values Values of the requested data feeds in the corresponding order
   */
  function getValuesForDataFeeds(bytes32[] memory requestedDataFeedIds) external view returns (uint256[] memory);

  /**
   * @notice Returns data timestamp from the latest update
   * @dev It's virtual, because its implementation can sometimes be different
   * (e.g. SinglePriceFeedAdapterWithClearing)
   * @return lastDataTimestamp Timestamp of the latest reported data packages
   */
  function getDataTimestampFromLatestUpdate() external view returns (uint256 lastDataTimestamp);

  /**
   * @notice Returns block timestamp of the latest successful update
   * @return blockTimestamp The block timestamp of the latest successful update
   */
  function getBlockTimestampFromLatestUpdate() external view returns (uint256 blockTimestamp);

  /**
   * @notice Returns timestamps of the latest successful update
   * @return dataTimestamp timestamp (usually in milliseconds) from the signed data packages
   * @return blockTimestamp timestamp of the block when the update has happened
   */
  function getTimestampsFromLatestUpdate() external view returns (uint128 dataTimestamp, uint128 blockTimestamp);

  /**
   * @notice Returns identifiers of all data feeds supported by the Adapter contract
   * @return An array of data feed identifiers
   */
  function getDataFeedIds() external view returns (bytes32[] memory);

  /**
   * @notice Returns the unique index of the given data feed
   * @param dataFeedId The data feed identifier
   * @return index The index of the data feed
   */
  function getDataFeedIndex(bytes32 dataFeedId) external view returns (uint256);

  /**
   * @notice Returns minimal required interval (usually in seconds) between subsequent updates
   * @return interval The required interval between updates
   */
  function getMinIntervalBetweenUpdates() external view returns (uint256);

  /**
   * @notice Reverts if the proposed timestamp of data packages it too old or too new
   * comparing to the block.timestamp. It also ensures that the proposed timestamp is newer
   * Then the one from the previous update
   * @param dataPackagesTimestamp The proposed timestamp (usually in milliseconds)
   */
  function validateProposedDataPackagesTimestamp(uint256 dataPackagesTimestamp) external view;

  /**
   * @notice Reverts if the updater is not authorised
   * @dev This function should revert if msg.sender is not allowed to update data feed values
   * @param updater The address of the proposed updater
   */
  function requireAuthorisedUpdater(address updater) external view;
}

// lib/redstone-oracles-monorepo/packages/on-chain-relayer/contracts/price-feeds/interfaces/IPriceFeedLegacy.sol

/**
 * @title Interface with the old Chainlink Price Feed functions
 * @author The Redstone Oracles team
 * @dev There are some projects (e.g. gmx-contracts) that still
 * rely on some legacy functions
 */
interface IPriceFeedLegacy {
  /**
   * @notice Old Chainlink function for getting the number of latest round
   * @return latestRound The number of the latest update round
   */
  function latestRound() external view returns (uint80);

  
  /**
   * @notice Old Chainlink function for getting the latest successfully reported value
   * @return latestAnswer The latest successfully reported value
   */
  function latestAnswer() external view returns (int256);
}

// lib/solady/src/utils/SafeTransferLib.sol

/// @notice Safe ETH and ERC20 transfer library that gracefully handles missing return values.
/// @author Solady (https://github.com/vectorized/solady/blob/main/src/utils/SafeTransferLib.sol)
/// @author Modified from Solmate (https://github.com/transmissions11/solmate/blob/main/src/utils/SafeTransferLib.sol)
/// @author Permit2 operations from (https://github.com/Uniswap/permit2/blob/main/src/libraries/Permit2Lib.sol)
///
/// @dev Note:
/// - For ETH transfers, please use `forceSafeTransferETH` for DoS protection.
/// - For ERC20s, this implementation won't check that a token has code,
///   responsibility is delegated to the caller.
library SafeTransferLib {
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       CUSTOM ERRORS                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev The ETH transfer has failed.
    error ETHTransferFailed();

    /// @dev The ERC20 `transferFrom` has failed.
    error TransferFromFailed();

    /// @dev The ERC20 `transfer` has failed.
    error TransferFailed();

    /// @dev The ERC20 `approve` has failed.
    error ApproveFailed();

    /// @dev The Permit2 operation has failed.
    error Permit2Failed();

    /// @dev The Permit2 amount must be less than `2**160 - 1`.
    error Permit2AmountOverflow();

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         CONSTANTS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev Suggested gas stipend for contract receiving ETH that disallows any storage writes.
    uint256 internal constant GAS_STIPEND_NO_STORAGE_WRITES = 2300;

    /// @dev Suggested gas stipend for contract receiving ETH to perform a few
    /// storage reads and writes, but low enough to prevent griefing.
    uint256 internal constant GAS_STIPEND_NO_GRIEF = 100000;

    /// @dev The unique EIP-712 domain domain separator for the DAI token contract.
    bytes32 internal constant DAI_DOMAIN_SEPARATOR =
        0xdbb8cf42e1ecb028be3f3dbc922e1d878b963f411dc388ced501601c60f7c6f7;

    /// @dev The address for the WETH9 contract on Ethereum mainnet.
    address internal constant WETH9 = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    /// @dev The canonical Permit2 address.
    /// [Github](https://github.com/Uniswap/permit2)
    /// [Etherscan](https://etherscan.io/address/0x000000000022D473030F116dDEE9F6B43aC78BA3)
    address internal constant PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       ETH OPERATIONS                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    // If the ETH transfer MUST succeed with a reasonable gas budget, use the force variants.
    //
    // The regular variants:
    // - Forwards all remaining gas to the target.
    // - Reverts if the target reverts.
    // - Reverts if the current contract has insufficient balance.
    //
    // The force variants:
    // - Forwards with an optional gas stipend
    //   (defaults to `GAS_STIPEND_NO_GRIEF`, which is sufficient for most cases).
    // - If the target reverts, or if the gas stipend is exhausted,
    //   creates a temporary contract to force send the ETH via `SELFDESTRUCT`.
    //   Future compatible with `SENDALL`: https://eips.ethereum.org/EIPS/eip-4758.
    // - Reverts if the current contract has insufficient balance.
    //
    // The try variants:
    // - Forwards with a mandatory gas stipend.
    // - Instead of reverting, returns whether the transfer succeeded.

    /// @dev Sends `amount` (in wei) ETH to `to`.
    function safeTransferETH(address to, uint256 amount) internal {
        /// @solidity memory-safe-assembly
        assembly {
            if iszero(call(gas(), to, amount, codesize(), 0x00, codesize(), 0x00)) {
                mstore(0x00, 0xb12d13eb) // `ETHTransferFailed()`.
                revert(0x1c, 0x04)
            }
        }
    }

    /// @dev Sends all the ETH in the current contract to `to`.
    function safeTransferAllETH(address to) internal {
        /// @solidity memory-safe-assembly
        assembly {
            // Transfer all the ETH and check if it succeeded or not.
            if iszero(call(gas(), to, selfbalance(), codesize(), 0x00, codesize(), 0x00)) {
                mstore(0x00, 0xb12d13eb) // `ETHTransferFailed()`.
                revert(0x1c, 0x04)
            }
        }
    }

    /// @dev Force sends `amount` (in wei) ETH to `to`, with a `gasStipend`.
    function forceSafeTransferETH(address to, uint256 amount, uint256 gasStipend) internal {
        /// @solidity memory-safe-assembly
        assembly {
            if lt(selfbalance(), amount) {
                mstore(0x00, 0xb12d13eb) // `ETHTransferFailed()`.
                revert(0x1c, 0x04)
            }
            if iszero(call(gasStipend, to, amount, codesize(), 0x00, codesize(), 0x00)) {
                mstore(0x00, to) // Store the address in scratch space.
                mstore8(0x0b, 0x73) // Opcode `PUSH20`.
                mstore8(0x20, 0xff) // Opcode `SELFDESTRUCT`.
                if iszero(create(amount, 0x0b, 0x16)) { revert(codesize(), codesize()) } // For gas estimation.
            }
        }
    }

    /// @dev Force sends all the ETH in the current contract to `to`, with a `gasStipend`.
    function forceSafeTransferAllETH(address to, uint256 gasStipend) internal {
        /// @solidity memory-safe-assembly
        assembly {
            if iszero(call(gasStipend, to, selfbalance(), codesize(), 0x00, codesize(), 0x00)) {
                mstore(0x00, to) // Store the address in scratch space.
                mstore8(0x0b, 0x73) // Opcode `PUSH20`.
                mstore8(0x20, 0xff) // Opcode `SELFDESTRUCT`.
                if iszero(create(selfbalance(), 0x0b, 0x16)) { revert(codesize(), codesize()) } // For gas estimation.
            }
        }
    }

    /// @dev Force sends `amount` (in wei) ETH to `to`, with `GAS_STIPEND_NO_GRIEF`.
    function forceSafeTransferETH(address to, uint256 amount) internal {
        /// @solidity memory-safe-assembly
        assembly {
            if lt(selfbalance(), amount) {
                mstore(0x00, 0xb12d13eb) // `ETHTransferFailed()`.
                revert(0x1c, 0x04)
            }
            if iszero(call(GAS_STIPEND_NO_GRIEF, to, amount, codesize(), 0x00, codesize(), 0x00)) {
                mstore(0x00, to) // Store the address in scratch space.
                mstore8(0x0b, 0x73) // Opcode `PUSH20`.
                mstore8(0x20, 0xff) // Opcode `SELFDESTRUCT`.
                if iszero(create(amount, 0x0b, 0x16)) { revert(codesize(), codesize()) } // For gas estimation.
            }
        }
    }

    /// @dev Force sends all the ETH in the current contract to `to`, with `GAS_STIPEND_NO_GRIEF`.
    function forceSafeTransferAllETH(address to) internal {
        /// @solidity memory-safe-assembly
        assembly {
            // forgefmt: disable-next-item
            if iszero(call(GAS_STIPEND_NO_GRIEF, to, selfbalance(), codesize(), 0x00, codesize(), 0x00)) {
                mstore(0x00, to) // Store the address in scratch space.
                mstore8(0x0b, 0x73) // Opcode `PUSH20`.
                mstore8(0x20, 0xff) // Opcode `SELFDESTRUCT`.
                if iszero(create(selfbalance(), 0x0b, 0x16)) { revert(codesize(), codesize()) } // For gas estimation.
            }
        }
    }

    /// @dev Sends `amount` (in wei) ETH to `to`, with a `gasStipend`.
    function trySafeTransferETH(address to, uint256 amount, uint256 gasStipend)
        internal
        returns (bool success)
    {
        /// @solidity memory-safe-assembly
        assembly {
            success := call(gasStipend, to, amount, codesize(), 0x00, codesize(), 0x00)
        }
    }

    /// @dev Sends all the ETH in the current contract to `to`, with a `gasStipend`.
    function trySafeTransferAllETH(address to, uint256 gasStipend)
        internal
        returns (bool success)
    {
        /// @solidity memory-safe-assembly
        assembly {
            success := call(gasStipend, to, selfbalance(), codesize(), 0x00, codesize(), 0x00)
        }
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      ERC20 OPERATIONS                      */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev Sends `amount` of ERC20 `token` from `from` to `to`.
    /// Reverts upon failure.
    ///
    /// The `from` account must have at least `amount` approved for
    /// the current contract to manage.
    function safeTransferFrom(address token, address from, address to, uint256 amount) internal {
        /// @solidity memory-safe-assembly
        assembly {
            let m := mload(0x40) // Cache the free memory pointer.
            mstore(0x60, amount) // Store the `amount` argument.
            mstore(0x40, to) // Store the `to` argument.
            mstore(0x2c, shl(96, from)) // Store the `from` argument.
            mstore(0x0c, 0x23b872dd000000000000000000000000) // `transferFrom(address,address,uint256)`.
            // Perform the transfer, reverting upon failure.
            if iszero(
                and( // The arguments of `and` are evaluated from right to left.
                    or(eq(mload(0x00), 1), iszero(returndatasize())), // Returned 1 or nothing.
                    call(gas(), token, 0, 0x1c, 0x64, 0x00, 0x20)
                )
            ) {
                mstore(0x00, 0x7939f424) // `TransferFromFailed()`.
                revert(0x1c, 0x04)
            }
            mstore(0x60, 0) // Restore the zero slot to zero.
            mstore(0x40, m) // Restore the free memory pointer.
        }
    }

    /// @dev Sends `amount` of ERC20 `token` from `from` to `to`.
    ///
    /// The `from` account must have at least `amount` approved for the current contract to manage.
    function trySafeTransferFrom(address token, address from, address to, uint256 amount)
        internal
        returns (bool success)
    {
        /// @solidity memory-safe-assembly
        assembly {
            let m := mload(0x40) // Cache the free memory pointer.
            mstore(0x60, amount) // Store the `amount` argument.
            mstore(0x40, to) // Store the `to` argument.
            mstore(0x2c, shl(96, from)) // Store the `from` argument.
            mstore(0x0c, 0x23b872dd000000000000000000000000) // `transferFrom(address,address,uint256)`.
            success :=
                and( // The arguments of `and` are evaluated from right to left.
                    or(eq(mload(0x00), 1), iszero(returndatasize())), // Returned 1 or nothing.
                    call(gas(), token, 0, 0x1c, 0x64, 0x00, 0x20)
                )
            mstore(0x60, 0) // Restore the zero slot to zero.
            mstore(0x40, m) // Restore the free memory pointer.
        }
    }

    /// @dev Sends all of ERC20 `token` from `from` to `to`.
    /// Reverts upon failure.
    ///
    /// The `from` account must have their entire balance approved for the current contract to manage.
    function safeTransferAllFrom(address token, address from, address to)
        internal
        returns (uint256 amount)
    {
        /// @solidity memory-safe-assembly
        assembly {
            let m := mload(0x40) // Cache the free memory pointer.
            mstore(0x40, to) // Store the `to` argument.
            mstore(0x2c, shl(96, from)) // Store the `from` argument.
            mstore(0x0c, 0x70a08231000000000000000000000000) // `balanceOf(address)`.
            // Read the balance, reverting upon failure.
            if iszero(
                and( // The arguments of `and` are evaluated from right to left.
                    gt(returndatasize(), 0x1f), // At least 32 bytes returned.
                    staticcall(gas(), token, 0x1c, 0x24, 0x60, 0x20)
                )
            ) {
                mstore(0x00, 0x7939f424) // `TransferFromFailed()`.
                revert(0x1c, 0x04)
            }
            mstore(0x00, 0x23b872dd) // `transferFrom(address,address,uint256)`.
            amount := mload(0x60) // The `amount` is already at 0x60. We'll need to return it.
            // Perform the transfer, reverting upon failure.
            if iszero(
                and( // The arguments of `and` are evaluated from right to left.
                    or(eq(mload(0x00), 1), iszero(returndatasize())), // Returned 1 or nothing.
                    call(gas(), token, 0, 0x1c, 0x64, 0x00, 0x20)
                )
            ) {
                mstore(0x00, 0x7939f424) // `TransferFromFailed()`.
                revert(0x1c, 0x04)
            }
            mstore(0x60, 0) // Restore the zero slot to zero.
            mstore(0x40, m) // Restore the free memory pointer.
        }
    }

    /// @dev Sends `amount` of ERC20 `token` from the current contract to `to`.
    /// Reverts upon failure.
    function safeTransfer(address token, address to, uint256 amount) internal {
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x14, to) // Store the `to` argument.
            mstore(0x34, amount) // Store the `amount` argument.
            mstore(0x00, 0xa9059cbb000000000000000000000000) // `transfer(address,uint256)`.
            // Perform the transfer, reverting upon failure.
            if iszero(
                and( // The arguments of `and` are evaluated from right to left.
                    or(eq(mload(0x00), 1), iszero(returndatasize())), // Returned 1 or nothing.
                    call(gas(), token, 0, 0x10, 0x44, 0x00, 0x20)
                )
            ) {
                mstore(0x00, 0x90b8ec18) // `TransferFailed()`.
                revert(0x1c, 0x04)
            }
            mstore(0x34, 0) // Restore the part of the free memory pointer that was overwritten.
        }
    }

    /// @dev Sends all of ERC20 `token` from the current contract to `to`.
    /// Reverts upon failure.
    function safeTransferAll(address token, address to) internal returns (uint256 amount) {
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, 0x70a08231) // Store the function selector of `balanceOf(address)`.
            mstore(0x20, address()) // Store the address of the current contract.
            // Read the balance, reverting upon failure.
            if iszero(
                and( // The arguments of `and` are evaluated from right to left.
                    gt(returndatasize(), 0x1f), // At least 32 bytes returned.
                    staticcall(gas(), token, 0x1c, 0x24, 0x34, 0x20)
                )
            ) {
                mstore(0x00, 0x90b8ec18) // `TransferFailed()`.
                revert(0x1c, 0x04)
            }
            mstore(0x14, to) // Store the `to` argument.
            amount := mload(0x34) // The `amount` is already at 0x34. We'll need to return it.
            mstore(0x00, 0xa9059cbb000000000000000000000000) // `transfer(address,uint256)`.
            // Perform the transfer, reverting upon failure.
            if iszero(
                and( // The arguments of `and` are evaluated from right to left.
                    or(eq(mload(0x00), 1), iszero(returndatasize())), // Returned 1 or nothing.
                    call(gas(), token, 0, 0x10, 0x44, 0x00, 0x20)
                )
            ) {
                mstore(0x00, 0x90b8ec18) // `TransferFailed()`.
                revert(0x1c, 0x04)
            }
            mstore(0x34, 0) // Restore the part of the free memory pointer that was overwritten.
        }
    }

    /// @dev Sets `amount` of ERC20 `token` for `to` to manage on behalf of the current contract.
    /// Reverts upon failure.
    function safeApprove(address token, address to, uint256 amount) internal {
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x14, to) // Store the `to` argument.
            mstore(0x34, amount) // Store the `amount` argument.
            mstore(0x00, 0x095ea7b3000000000000000000000000) // `approve(address,uint256)`.
            // Perform the approval, reverting upon failure.
            if iszero(
                and( // The arguments of `and` are evaluated from right to left.
                    or(eq(mload(0x00), 1), iszero(returndatasize())), // Returned 1 or nothing.
                    call(gas(), token, 0, 0x10, 0x44, 0x00, 0x20)
                )
            ) {
                mstore(0x00, 0x3e3f8f73) // `ApproveFailed()`.
                revert(0x1c, 0x04)
            }
            mstore(0x34, 0) // Restore the part of the free memory pointer that was overwritten.
        }
    }

    /// @dev Sets `amount` of ERC20 `token` for `to` to manage on behalf of the current contract.
    /// If the initial attempt to approve fails, attempts to reset the approved amount to zero,
    /// then retries the approval again (some tokens, e.g. USDT, requires this).
    /// Reverts upon failure.
    function safeApproveWithRetry(address token, address to, uint256 amount) internal {
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x14, to) // Store the `to` argument.
            mstore(0x34, amount) // Store the `amount` argument.
            mstore(0x00, 0x095ea7b3000000000000000000000000) // `approve(address,uint256)`.
            // Perform the approval, retrying upon failure.
            if iszero(
                and( // The arguments of `and` are evaluated from right to left.
                    or(eq(mload(0x00), 1), iszero(returndatasize())), // Returned 1 or nothing.
                    call(gas(), token, 0, 0x10, 0x44, 0x00, 0x20)
                )
            ) {
                mstore(0x34, 0) // Store 0 for the `amount`.
                mstore(0x00, 0x095ea7b3000000000000000000000000) // `approve(address,uint256)`.
                pop(call(gas(), token, 0, 0x10, 0x44, codesize(), 0x00)) // Reset the approval.
                mstore(0x34, amount) // Store back the original `amount`.
                // Retry the approval, reverting upon failure.
                if iszero(
                    and(
                        or(eq(mload(0x00), 1), iszero(returndatasize())), // Returned 1 or nothing.
                        call(gas(), token, 0, 0x10, 0x44, 0x00, 0x20)
                    )
                ) {
                    mstore(0x00, 0x3e3f8f73) // `ApproveFailed()`.
                    revert(0x1c, 0x04)
                }
            }
            mstore(0x34, 0) // Restore the part of the free memory pointer that was overwritten.
        }
    }

    /// @dev Returns the amount of ERC20 `token` owned by `account`.
    /// Returns zero if the `token` does not exist.
    function balanceOf(address token, address account) internal view returns (uint256 amount) {
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x14, account) // Store the `account` argument.
            mstore(0x00, 0x70a08231000000000000000000000000) // `balanceOf(address)`.
            amount :=
                mul( // The arguments of `mul` are evaluated from right to left.
                    mload(0x20),
                    and( // The arguments of `and` are evaluated from right to left.
                        gt(returndatasize(), 0x1f), // At least 32 bytes returned.
                        staticcall(gas(), token, 0x10, 0x24, 0x20, 0x20)
                    )
                )
        }
    }

    /// @dev Sends `amount` of ERC20 `token` from `from` to `to`.
    /// If the initial attempt fails, try to use Permit2 to transfer the token.
    /// Reverts upon failure.
    ///
    /// The `from` account must have at least `amount` approved for the current contract to manage.
    function safeTransferFrom2(address token, address from, address to, uint256 amount) internal {
        if (!trySafeTransferFrom(token, from, to, amount)) {
            permit2TransferFrom(token, from, to, amount);
        }
    }

    /// @dev Sends `amount` of ERC20 `token` from `from` to `to` via Permit2.
    /// Reverts upon failure.
    function permit2TransferFrom(address token, address from, address to, uint256 amount)
        internal
    {
        /// @solidity memory-safe-assembly
        assembly {
            let m := mload(0x40)
            mstore(add(m, 0x74), shr(96, shl(96, token)))
            mstore(add(m, 0x54), amount)
            mstore(add(m, 0x34), to)
            mstore(add(m, 0x20), shl(96, from))
            // `transferFrom(address,address,uint160,address)`.
            mstore(m, 0x36c78516000000000000000000000000)
            let p := PERMIT2
            let exists := eq(chainid(), 1)
            if iszero(exists) { exists := iszero(iszero(extcodesize(p))) }
            if iszero(and(call(gas(), p, 0, add(m, 0x10), 0x84, codesize(), 0x00), exists)) {
                mstore(0x00, 0x7939f4248757f0fd) // `TransferFromFailed()` or `Permit2AmountOverflow()`.
                revert(add(0x18, shl(2, iszero(iszero(shr(160, amount))))), 0x04)
            }
        }
    }

    /// @dev Permit a user to spend a given amount of
    /// another user's tokens via native EIP-2612 permit if possible, falling
    /// back to Permit2 if native permit fails or is not implemented on the token.
    function permit2(
        address token,
        address owner,
        address spender,
        uint256 amount,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) internal {
        bool success;
        /// @solidity memory-safe-assembly
        assembly {
            for {} shl(96, xor(token, WETH9)) {} {
                mstore(0x00, 0x3644e515) // `DOMAIN_SEPARATOR()`.
                if iszero(
                    and( // The arguments of `and` are evaluated from right to left.
                        lt(iszero(mload(0x00)), eq(returndatasize(), 0x20)), // Returns 1 non-zero word.
                        // Gas stipend to limit gas burn for tokens that don't refund gas when
                        // an non-existing function is called. 5K should be enough for a SLOAD.
                        staticcall(5000, token, 0x1c, 0x04, 0x00, 0x20)
                    )
                ) { break }
                // After here, we can be sure that token is a contract.
                let m := mload(0x40)
                mstore(add(m, 0x34), spender)
                mstore(add(m, 0x20), shl(96, owner))
                mstore(add(m, 0x74), deadline)
                if eq(mload(0x00), DAI_DOMAIN_SEPARATOR) {
                    mstore(0x14, owner)
                    mstore(0x00, 0x7ecebe00000000000000000000000000) // `nonces(address)`.
                    mstore(add(m, 0x94), staticcall(gas(), token, 0x10, 0x24, add(m, 0x54), 0x20))
                    mstore(m, 0x8fcbaf0c000000000000000000000000) // `IDAIPermit.permit`.
                    // `nonces` is already at `add(m, 0x54)`.
                    // `1` is already stored at `add(m, 0x94)`.
                    mstore(add(m, 0xb4), and(0xff, v))
                    mstore(add(m, 0xd4), r)
                    mstore(add(m, 0xf4), s)
                    success := call(gas(), token, 0, add(m, 0x10), 0x104, codesize(), 0x00)
                    break
                }
                mstore(m, 0xd505accf000000000000000000000000) // `IERC20Permit.permit`.
                mstore(add(m, 0x54), amount)
                mstore(add(m, 0x94), and(0xff, v))
                mstore(add(m, 0xb4), r)
                mstore(add(m, 0xd4), s)
                success := call(gas(), token, 0, add(m, 0x10), 0xe4, codesize(), 0x00)
                break
            }
        }
        if (!success) simplePermit2(token, owner, spender, amount, deadline, v, r, s);
    }

    /// @dev Simple permit on the Permit2 contract.
    function simplePermit2(
        address token,
        address owner,
        address spender,
        uint256 amount,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) internal {
        /// @solidity memory-safe-assembly
        assembly {
            let m := mload(0x40)
            mstore(m, 0x927da105) // `allowance(address,address,address)`.
            {
                let addressMask := shr(96, not(0))
                mstore(add(m, 0x20), and(addressMask, owner))
                mstore(add(m, 0x40), and(addressMask, token))
                mstore(add(m, 0x60), and(addressMask, spender))
                mstore(add(m, 0xc0), and(addressMask, spender))
            }
            let p := mul(PERMIT2, iszero(shr(160, amount)))
            if iszero(
                and( // The arguments of `and` are evaluated from right to left.
                    gt(returndatasize(), 0x5f), // Returns 3 words: `amount`, `expiration`, `nonce`.
                    staticcall(gas(), p, add(m, 0x1c), 0x64, add(m, 0x60), 0x60)
                )
            ) {
                mstore(0x00, 0x6b836e6b8757f0fd) // `Permit2Failed()` or `Permit2AmountOverflow()`.
                revert(add(0x18, shl(2, iszero(p))), 0x04)
            }
            mstore(m, 0x2b67b570) // `Permit2.permit` (PermitSingle variant).
            // `owner` is already `add(m, 0x20)`.
            // `token` is already at `add(m, 0x40)`.
            mstore(add(m, 0x60), amount)
            mstore(add(m, 0x80), 0xffffffffffff) // `expiration = type(uint48).max`.
            // `nonce` is already at `add(m, 0xa0)`.
            // `spender` is already at `add(m, 0xc0)`.
            mstore(add(m, 0xe0), deadline)
            mstore(add(m, 0x100), 0x100) // `signature` offset.
            mstore(add(m, 0x120), 0x41) // `signature` length.
            mstore(add(m, 0x140), r)
            mstore(add(m, 0x160), s)
            mstore(add(m, 0x180), shl(248, v))
            if iszero(call(gas(), p, 0, add(m, 0x1c), 0x184, codesize(), 0x00)) {
                mstore(0x00, 0x6b836e6b) // `Permit2Failed()`.
                revert(0x1c, 0x04)
            }
        }
    }
}

// node_modules/@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol

interface AggregatorV3Interface_0 {
  function decimals() external view returns (uint8);

  function description() external view returns (string memory);

  function version() external view returns (uint256);

  function getRoundData(uint80 _roundId)
    external
    view
    returns (
      uint80 roundId,
      int256 answer,
      uint256 startedAt,
      uint256 updatedAt,
      uint80 answeredInRound
    );

  function latestRoundData()
    external
    view
    returns (
      uint80 roundId,
      int256 answer,
      uint256 startedAt,
      uint256 updatedAt,
      uint80 answeredInRound
    );
}

// src/contracts/examples/oev-example/IChainlinkDAppControl.sol

interface IChainlinkDAppControl {
    function verifyTransmitSigners(
        address baseChainlinkFeed,
        bytes calldata report,
        bytes32[] calldata rs,
        bytes32[] calldata ss,
        bytes32 rawVs
    )
        external
        view
        returns (bool verified);
}

// src/contracts/types/AtlasEvents.sol

contract AtlasEvents {
    // Metacall
    event MetacallResult(
        address indexed bundler,
        address indexed user,
        bool solverSuccessful,
        bool disbursementSuccessful,
        uint256 ethPaidToBundler,
        uint256 netGasSurcharge
    );

    // AtlETH
    event Bond(address indexed owner, uint256 amount);
    event Unbond(address indexed owner, uint256 amount, uint256 earliestAvailable);
    event Redeem(address indexed owner, uint256 amount);
    event Transfer(address indexed from, address indexed to, uint256 amount);
    event Approval(address indexed owner, address indexed spender, uint256 amount);

    // Escrow events
    event SolverTxResult(
        address indexed solverTo, address indexed solverFrom, bool executed, bool success, uint256 result
    );

    // Factory events
    event ExecutionEnvironmentCreated(address indexed user, address indexed executionEnvironment);

    // Surcharge events
    event SurchargeWithdrawn(address to, uint256 amount);
    event SurchargeRecipientTransferStarted(address currentRecipient, address newRecipient);
    event SurchargeRecipientTransferred(address newRecipient);

    // DAppControl events
    event GovernanceTransferStarted(address indexed previousGovernance, address indexed newGovernance);
    event GovernanceTransferred(address indexed previousGovernance, address indexed newGovernance);

    // DAppIntegration events
    event NewDAppSignatory(
        address indexed control, address indexed governance, address indexed signatory, uint32 callConfig
    );
    event RemovedDAppSignatory(
        address indexed control, address indexed governance, address indexed signatory, uint32 callConfig
    );
    event DAppGovernanceChanged(
        address indexed control, address indexed oldGovernance, address indexed newGovernance, uint32 callConfig
    );
    event DAppDisabled(address indexed control, address indexed governance, uint32 callConfig);
}

// src/contracts/types/ConfigTypes.sol

struct DAppConfig {
    address to; // Address of the DAppControl contract
    uint32 callConfig; // Configuration
    address bidToken; // address(0) for ETH
    uint32 solverGasLimit; // Max gas limit for solverOps
}

struct CallConfig {
    // userNoncesSequential: The userOp nonce must be the next sequential nonce for that user’s address in Atlas’
    // nonce system. If false, the userOp nonces are allowed to be non-sequential (unordered), as long as they are
    // unique.
    bool userNoncesSequential;
    // dappNoncesSequential: The dappOp nonce must be the next sequential nonce for that dApp signer’s address in
    // Atlas’ nonce system. If false, the dappOp nonce is not checked, as the dAppOp is tied to its userOp's nonce via
    // the callChainHash.
    bool dappNoncesSequential;
    // requirePreOps: The preOps hook is executed before the userOp is executed. If false, the preOps hook is skipped.
    // the dapp control should check the validity of the user operation (whether its dapps can support userOp.dapp and
    // userOp.data) in the preOps hook.
    bool requirePreOps;
    // trackPreOpsReturnData: The return data from the preOps hook is passed to the next call phase. If false preOps
    // return data is discarded. If both trackPreOpsReturnData and trackUserReturnData are true, they are concatenated.
    bool trackPreOpsReturnData;
    // trackUserReturnData: The return data from the userOp call is passed to the next call phase. If false userOp
    // return data is discarded. If both trackPreOpsReturnData and trackUserReturnData are true, they are concatenated.
    bool trackUserReturnData;
    // delegateUser: The userOp call is made using delegatecall from the Execution Environment. If false, userOp is
    // called using call.
    bool delegateUser;
    // requirePreSolver: The preSolver hook is executed before the solverOp is executed. If false, the preSolver hook is
    // skipped.
    bool requirePreSolver;
    // requirePostSolver: The postSolver hook is executed after the solverOp is executed. If false, the postSolver hook
    // is skipped.
    bool requirePostSolver;
    // requirePostOps: The postOps hook is executed as the last step of the metacall. If false, the postOps hook is
    // skipped.
    bool requirePostOps;
    // zeroSolvers: Allow the metacall to proceed even if there are no solverOps. The solverOps do not necessarily need
    // to be successful, but at least 1 must exist.
    bool zeroSolvers;
    // reuseUserOp: If true, the metacall will revert if unsuccessful so as not to store nonce data, so the userOp can
    // be reused.
    bool reuseUserOp;
    // userAuctioneer: The user is allowed to be the auctioneer (the signer of the dAppOp). More than one auctioneer
    // option can be set to true for the same DAppControl.
    bool userAuctioneer;
    // solverAuctioneer: The solver is allowed to be the auctioneer (the signer of the dAppOp). If the solver is the
    // auctioneer then their solverOp must be the only one. More than one auctioneer option can be set to true for the
    // same DAppControl.
    bool solverAuctioneer;
    // unknownAuctioneer: Anyone is allowed to be the auctioneer - dAppOp.from must be the signer of the dAppOp, but the
    // usual signatory[] checks are skipped. More than one auctioneer option can be set to true for the same
    // DAppControl.
    bool unknownAuctioneer;
    // verifyCallChainHash: Check that the dAppOp callChainHash matches the actual callChainHash as calculated in
    // AtlasVerification.
    bool verifyCallChainHash;
    // forwardReturnData: The return data from previous steps is included as calldata in the call from the Execution
    // Environment to the solver contract. If false, return data is not passed to the solver contract.
    bool forwardReturnData;
    // requireFulfillment: If true, a winning solver must be found, otherwise the metacall will fail.
    bool requireFulfillment;
    // trustedOpHash: If true, the userOpHash excludes some userOp inputs such as `value`, `gas`, `maxFeePerGas`,
    // `nonce`, `deadline`, and `data`, implying solvers trust changes made to these parts of the userOp after signing
    // their associated solverOps.
    bool trustedOpHash;
    // invertBidValue: If true, the solver with the lowest successful bid wins.
    bool invertBidValue;
    // exPostBids: Bids are found on-chain using `_getBidAmount` in Atlas, and solverOp.bidAmount is used as the max
    // bid. If solverOp.bidAmount is 0, then there is no max bid limit for that solver.
    bool exPostBids;
    // allowAllocateValueFailure: If true, the metacall will proceed even if the value allocation fails. If false, the
    // metacall will revert if the value allocation fails.
    bool allowAllocateValueFailure;
}

enum CallConfigIndex {
    UserNoncesSequential,
    DAppNoncesSequential,
    RequirePreOps,
    TrackPreOpsReturnData,
    TrackUserReturnData,
    DelegateUser,
    RequirePreSolver,
    RequirePostSolver,
    RequirePostOpsCall,
    ZeroSolvers,
    ReuseUserOp,
    UserAuctioneer,
    SolverAuctioneer,
    UnknownAuctioneer,
    // Default = DAppAuctioneer
    VerifyCallChainHash,
    ForwardReturnData,
    RequireFulfillment,
    TrustedOpHash,
    InvertBidValue,
    ExPostBids,
    AllowAllocateValueFailure
}

// src/contracts/types/DAppOperation.sol

bytes32 constant DAPP_TYPEHASH = keccak256(
    "DAppOperation(address from,address to,uint256 nonce,uint256 deadline,address control,address bundler,bytes32 userOpHash,bytes32 callChainHash)"
);

struct DAppOperation {
    address from; // signer of the DAppOperation
    address to; // Atlas address
    uint256 nonce; // Atlas nonce of the DAppOperation available in the AtlasVerification contract
    uint256 deadline; // block.number deadline for the DAppOperation
    address control; // DAppControl address
    address bundler; // Signer of the atlas tx (msg.sender)
    bytes32 userOpHash; // keccak256 of userOp.to, userOp.data
    bytes32 callChainHash; // keccak256 of the solvers' txs
    bytes signature; // DAppOperation signed by DAppOperation.from
}

// src/contracts/types/EscrowTypes.sol

// bonded = total - unbonding
struct EscrowAccountBalance {
    uint112 balance;
    uint112 unbonding;
}

struct EscrowAccountAccessData {
    uint112 bonded;
    uint32 lastAccessedBlock;
    uint24 auctionWins;
    uint24 auctionFails;
    uint64 totalGasValueUsed; // The cumulative ETH value spent on gas in metacalls. Measured in gwei.
}

// Additional struct to avoid Stack Too Deep while tracking variables related to the solver call.
struct SolverTracker {
    uint256 bidAmount;
    uint256 floor;
    uint256 ceiling;
    bool etherIsBidToken;
    bool invertsBidValue;
}

/// @title SolverOutcome
/// @notice Enum for SolverOutcome
/// @dev Multiple SolverOutcomes can be used to represent the outcome of a solver call
/// @dev Typical usage looks like solverOutcome = (1 << SolverOutcome.InvalidSignature) | (1 <<
/// SolverOutcome.InvalidUserHash) to indicate SolverOutcome.InvalidSignature and SolverOutcome.InvalidUserHash
enum SolverOutcome {
    // No Refund (relay error or hostile user)
    InvalidSignature,
    InvalidUserHash,
    DeadlinePassedAlt,
    GasPriceBelowUsersAlt,
    InvalidTo,
    UserOutOfGas,
    AlteredControl,
    AltOpHashMismatch,
    // Partial Refund but no execution
    DeadlinePassed,
    GasPriceOverCap,
    InvalidSolver,
    InvalidBidToken,
    PerBlockLimit, // solvers can only send one tx per block
    // if they sent two we wouldn't be able to flag builder censorship
    InsufficientEscrow,
    GasPriceBelowUsers,
    CallValueTooHigh,
    PreSolverFailed,
    // execution, with Full Refund
    SolverOpReverted,
    PostSolverFailed,
    BidNotPaid,
    InvertedBidExceedsCeiling,
    BalanceNotReconciled,
    CallbackNotCalled,
    EVMError
}

// src/contracts/types/LockTypes.sol

struct Context_1 {
    bytes32 userOpHash; // not packed
    address executionEnvironment; // not packed
    uint24 solverOutcome;
    uint8 solverIndex;
    uint8 solverCount;
    uint8 callDepth;
    uint8 phase;
    bool solverSuccessful;
    bool paymentsSuccessful;
    bool bidFind;
    bool isSimulation;
    address bundler;
}

enum ExecutionPhase {
    Uninitialized,
    PreOps,
    UserOperation,
    PreSolver,
    SolverOperation,
    PostSolver,
    AllocateValue,
    PostOps,
    FullyLocked
}

// src/contracts/types/SolverOperation.sol

bytes32 constant SOLVER_TYPEHASH = keccak256(
    "SolverOperation(address from,address to,uint256 value,uint256 gas,uint256 maxFeePerGas,uint256 deadline,address solver,address control,bytes32 userOpHash,address bidToken,uint256 bidAmount,bytes data)"
);

// NOTE: The calldata length of this SolverOperation struct is 608 bytes when the `data` field is excluded. This value
// is stored in the `_SOLVER_OP_BASE_CALLDATA` constant in Storage.sol and must be kept up-to-date with any changes to
// this struct.
struct SolverOperation {
    address from; // Solver address
    address to; // Atlas address
    uint256 value; // Amount of ETH required for the solver operation (used in `value` field of the solver call)
    uint256 gas; // Gas limit for the solver operation
    uint256 maxFeePerGas; // maxFeePerGas solver is willing to pay.  This goes to validator, not dApp or user
    uint256 deadline; // block.number deadline for the solver operation
    address solver; // Nested "to" address (used in `to` field of the solver call)
    address control; // DAppControl address
    bytes32 userOpHash; // hash of User's Operation, for verification of user's tx (if not matched, solver wont be
        // charged for gas)
    address bidToken; // address(0) for ETH
    uint256 bidAmount; // Amount of bidToken that the solver bids
    bytes data; // Solver op calldata (used in `data` field of the solver call)
    bytes signature; // Solver operation signature signed by SolverOperation.from
}

// src/contracts/types/UserOperation.sol

// Default UserOperation typehash
bytes32 constant USER_TYPEHASH_DEFAULT = keccak256(
    "UserOperation(address from,address to,uint256 value,uint256 gas,uint256 maxFeePerGas,uint256 nonce,uint256 deadline,address dapp,address control,uint32 callConfig,address sessionKey,bytes data)"
);

// Trusted UserOperation typehash
// NOTE: This is explicitly for the 'trustedOpHash' configuration option meant so that solvers can submit
// SolverOperations
// prior to seeing the UserOperation or its hash. In this scenario, the Solvers should trust the signer of the
// UserOperation.
bytes32 constant USER_TYPEHASH_TRUSTED = keccak256(
    "UserOperation(address from,address to,address dapp,address control,uint32 callConfig,address sessionKey)"
);

struct UserOperation {
    address from; // User address
    address to; // Atlas address
    uint256 value; // Amount of ETH required for the user operation (used in `value` field of the user call)
    uint256 gas; // Gas limit for the user operation
    uint256 maxFeePerGas; // Max fee per gas for the user operation
    uint256 nonce; // Atlas nonce of the user operation available in the AtlasVerification contract
    uint256 deadline; // block.number deadline for the user operation
    address dapp; // Nested "to" for user's call (used in `to` field of the user call)
    address control; // Address of the DAppControl contract
    uint32 callConfig; // Call configuration expected by user, refer to
        // `src/contracts/types/ConfigTypes.sol:CallConfig`
    address sessionKey; // Address of the temporary session key which is used to sign the DappOperation
    bytes data; // User operation calldata (used in `data` field of the user call)
    bytes signature; // User operation signature signed by UserOperation.from
}

// src/contracts/types/ValidCalls.sol

/// @title ValidCallsResult
/// @notice Enum for ValidCallsResult
/// @dev A single ValidCallsResult is returned by `validateCalls` in AtlasVerification
enum ValidCallsResult {
    Valid,
    // Results below this line will cause metacall to revert
    UserFromInvalid,
    UserSignatureInvalid,
    DAppSignatureInvalid,
    UserNonceInvalid,
    InvalidDAppNonce,
    UnknownAuctioneerNotAllowed,
    InvalidAuctioneer,
    InvalidBundler,
    // Results above this line will cause metacall to revert
    InvertBidValueCannotBeExPostBids, // Threshold value (included in the revert range), any new reverting values should
        // be included above this line
    // Results below this line will cause metacall to gracefully return
    GasPriceHigherThanMax,
    TxValueLowerThanCallValue,
    TooManySolverOps,
    UserDeadlineReached,
    DAppDeadlineReached,
    ExecutionEnvEmpty,
    NoSolverOp,
    InvalidSequence,
    OpHashMismatch,
    DeadlineMismatch,
    InvalidControl,
    InvalidSolverGasLimit,
    InvalidCallConfig,
    CallConfigMismatch,
    DAppToInvalid,
    UserToInvalid,
    ControlMismatch,
    InvalidCallChainHash,
    DAppNotEnabled,
    BothUserAndDAppNoncesCannotBeSequential
}

// lib/openzeppelin-contracts/contracts/access/Ownable.sol

// OpenZeppelin Contracts (last updated v4.9.0) (access/Ownable.sol)

/**
 * @dev Contract module which provides a basic access control mechanism, where
 * there is an account (an owner) that can be granted exclusive access to
 * specific functions.
 *
 * By default, the owner account will be the one that deploys the contract. This
 * can later be changed with {transferOwnership}.
 *
 * This module is used through inheritance. It will make available the modifier
 * `onlyOwner`, which can be applied to your functions to restrict their use to
 * the owner.
 */
abstract contract Ownable is Context_0 {
    address private _owner;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    /**
     * @dev Initializes the contract setting the deployer as the initial owner.
     */
    constructor() {
        _transferOwnership(_msgSender());
    }

    /**
     * @dev Throws if called by any account other than the owner.
     */
    modifier onlyOwner() {
        _checkOwner();
        _;
    }

    /**
     * @dev Returns the address of the current owner.
     */
    function owner() public view virtual returns (address) {
        return _owner;
    }

    /**
     * @dev Throws if the sender is not the owner.
     */
    function _checkOwner() internal view virtual {
        require(owner() == _msgSender(), "Ownable: caller is not the owner");
    }

    /**
     * @dev Leaves the contract without owner. It will not be possible to call
     * `onlyOwner` functions. Can only be called by the current owner.
     *
     * NOTE: Renouncing ownership will leave the contract without an owner,
     * thereby disabling any functionality that is only available to the owner.
     */
    function renounceOwnership() public virtual onlyOwner {
        _transferOwnership(address(0));
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Can only be called by the current owner.
     */
    function transferOwnership(address newOwner) public virtual onlyOwner {
        require(newOwner != address(0), "Ownable: new owner is the zero address");
        _transferOwnership(newOwner);
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Internal function without access restriction.
     */
    function _transferOwnership(address newOwner) internal virtual {
        address oldOwner = _owner;
        _owner = newOwner;
        emit OwnershipTransferred(oldOwner, newOwner);
    }
}

// lib/redstone-oracles-monorepo/packages/evm-connector/contracts/core/CalldataExtractor.sol

/**
 * @title The base contract with the main logic of data extraction from calldata
 * @author The Redstone Oracles team
 * @dev This contract was created to reuse the same logic in the RedstoneConsumerBase
 * and the ProxyConnector contracts
 */
contract CalldataExtractor is RedstoneConstants {

  error DataPackageTimestampMustNotBeZero();
  error DataPackageTimestampsMustBeEqual();
  error RedstonePayloadMustHaveAtLeastOneDataPackage();
  error TooLargeValueByteSize(uint256 valueByteSize);

  function extractTimestampsAndAssertAllAreEqual() public pure returns (uint256 extractedTimestamp) {
    uint256 calldataNegativeOffset = _extractByteSizeOfUnsignedMetadata();
    uint256 dataPackagesCount;
    (dataPackagesCount, calldataNegativeOffset) = _extractDataPackagesCountFromCalldata(calldataNegativeOffset);

    if (dataPackagesCount == 0) {
      revert RedstonePayloadMustHaveAtLeastOneDataPackage();
    }

    for (uint256 dataPackageIndex = 0; dataPackageIndex < dataPackagesCount; dataPackageIndex++) {
      uint256 dataPackageByteSize = _getDataPackageByteSize(calldataNegativeOffset);

      // Extracting timestamp for the current data package
      uint48 dataPackageTimestamp; // uint48, because timestamp uses 6 bytes
      uint256 timestampNegativeOffset = (calldataNegativeOffset + TIMESTAMP_NEGATIVE_OFFSET_IN_DATA_PACKAGE_WITH_STANDARD_SLOT_BS);
      uint256 timestampOffset = msg.data.length - timestampNegativeOffset;
      assembly {
        dataPackageTimestamp := calldataload(timestampOffset)
      }

      if (dataPackageTimestamp == 0) {
        revert DataPackageTimestampMustNotBeZero();
      }

      if (extractedTimestamp == 0) {
        extractedTimestamp = dataPackageTimestamp;
      } else if (dataPackageTimestamp != extractedTimestamp) {
        revert DataPackageTimestampsMustBeEqual();
      }

      calldataNegativeOffset += dataPackageByteSize;
    }
  }

  function _getDataPackageByteSize(uint256 calldataNegativeOffset) internal pure returns (uint256) {
    (
      uint256 dataPointsCount,
      uint256 eachDataPointValueByteSize
    ) = _extractDataPointsDetailsForDataPackage(calldataNegativeOffset);

    return
      dataPointsCount *
      (DATA_POINT_SYMBOL_BS + eachDataPointValueByteSize) +
      DATA_PACKAGE_WITHOUT_DATA_POINTS_BS;
  }

  function _extractByteSizeOfUnsignedMetadata() internal pure returns (uint256) {
    // Checking if the calldata ends with the RedStone marker
    bool hasValidRedstoneMarker;
    assembly {
      let calldataLast32Bytes := calldataload(sub(calldatasize(), STANDARD_SLOT_BS))
      hasValidRedstoneMarker := eq(
        REDSTONE_MARKER_MASK,
        and(calldataLast32Bytes, REDSTONE_MARKER_MASK)
      )
    }
    if (!hasValidRedstoneMarker) {
      revert CalldataMustHaveValidPayload();
    }

    // Using uint24, because unsigned metadata byte size number has 3 bytes
    uint24 unsignedMetadataByteSize;
    if (REDSTONE_MARKER_BS_PLUS_STANDARD_SLOT_BS > msg.data.length) {
      revert CalldataOverOrUnderFlow();
    }
    assembly {
      unsignedMetadataByteSize := calldataload(
        sub(calldatasize(), REDSTONE_MARKER_BS_PLUS_STANDARD_SLOT_BS)
      )
    }
    uint256 calldataNegativeOffset = unsignedMetadataByteSize
      + UNSIGNED_METADATA_BYTE_SIZE_BS
      + REDSTONE_MARKER_BS;
    if (calldataNegativeOffset + DATA_PACKAGES_COUNT_BS > msg.data.length) {
      revert IncorrectUnsignedMetadataSize();
    }
    return calldataNegativeOffset;
  }

  // We return uint16, because unsigned metadata byte size number has 2 bytes
  function _extractDataPackagesCountFromCalldata(uint256 calldataNegativeOffset)
    internal
    pure
    returns (uint16 dataPackagesCount, uint256 nextCalldataNegativeOffset)
  {
    uint256 calldataNegativeOffsetWithStandardSlot = calldataNegativeOffset + STANDARD_SLOT_BS;
    if (calldataNegativeOffsetWithStandardSlot > msg.data.length) {
      revert CalldataOverOrUnderFlow();
    }
    assembly {
      dataPackagesCount := calldataload(
        sub(calldatasize(), calldataNegativeOffsetWithStandardSlot)
      )
    }
    return (dataPackagesCount, calldataNegativeOffset + DATA_PACKAGES_COUNT_BS);
  }

  function _extractDataPointValueAndDataFeedId(
    uint256 dataPointNegativeOffset,
    uint256 dataPointValueByteSize
  ) internal pure virtual returns (bytes32 dataPointDataFeedId, uint256 dataPointValue) {
    uint256 dataPointCalldataOffset = msg.data.length - dataPointNegativeOffset;
    assembly {
      dataPointDataFeedId := calldataload(dataPointCalldataOffset)
      dataPointValue := calldataload(add(dataPointCalldataOffset, DATA_POINT_SYMBOL_BS))
    }
    if (dataPointValueByteSize >= 33) {
      revert TooLargeValueByteSize(dataPointValueByteSize);
    }
    unchecked {
      dataPointValue = dataPointValue >> (32 - dataPointValueByteSize) * 8; 
    }
  }

  function _extractDataPointsDetailsForDataPackage(uint256 calldataNegativeOffsetForDataPackage)
    internal
    pure
    returns (uint256 dataPointsCount, uint256 eachDataPointValueByteSize)
  {
    // Using uint24, because data points count byte size number has 3 bytes
    uint24 dataPointsCount_;

    // Using uint32, because data point value byte size has 4 bytes
    uint32 eachDataPointValueByteSize_;

    // Extract data points count
    uint256 calldataOffset = msg.data.length - (calldataNegativeOffsetForDataPackage + SIG_BS + STANDARD_SLOT_BS);
    assembly {
      dataPointsCount_ := calldataload(calldataOffset)
    }

    // Extract each data point value size
    calldataOffset = calldataOffset - DATA_POINTS_COUNT_BS;
    assembly {
      eachDataPointValueByteSize_ := calldataload(calldataOffset)
    }

    // Prepare returned values
    dataPointsCount = dataPointsCount_;
    eachDataPointValueByteSize = eachDataPointValueByteSize_;
  }
}

// lib/redstone-oracles-monorepo/packages/evm-connector/contracts/core/RedstoneDefaultsLib.sol

/**
 * @title Default implementations of virtual redstone consumer base functions
 * @author The Redstone Oracles team
 */
library RedstoneDefaultsLib {
  uint256 constant DEFAULT_MAX_DATA_TIMESTAMP_DELAY_SECONDS = 3 minutes;
  uint256 constant DEFAULT_MAX_DATA_TIMESTAMP_AHEAD_SECONDS = 1 minutes;

  error TimestampFromTooLongFuture(uint256 receivedTimestampSeconds, uint256 blockTimestamp);
  error TimestampIsTooOld(uint256 receivedTimestampSeconds, uint256 blockTimestamp);

  function validateTimestamp(uint256 receivedTimestampMilliseconds) internal view {
    // Getting data timestamp from future seems quite unlikely
    // But we've already spent too much time with different cases
    // Where block.timestamp was less than dataPackage.timestamp.
    // Some blockchains may case this problem as well.
    // That's why we add MAX_BLOCK_TIMESTAMP_DELAY
    // and allow data "from future" but with a small delay
    uint256 receivedTimestampSeconds = receivedTimestampMilliseconds / 1000;

    if (block.timestamp < receivedTimestampSeconds) {
      if ((receivedTimestampSeconds - block.timestamp) > DEFAULT_MAX_DATA_TIMESTAMP_AHEAD_SECONDS) {
        revert TimestampFromTooLongFuture(receivedTimestampSeconds, block.timestamp);
      }
    } else if ((block.timestamp - receivedTimestampSeconds) > DEFAULT_MAX_DATA_TIMESTAMP_DELAY_SECONDS) {
      revert TimestampIsTooOld(receivedTimestampSeconds, block.timestamp);
    }
  }

  function aggregateValues(uint256[] memory values) internal pure returns (uint256) {
    return NumericArrayLib.pickMedian(values);
  }
}

// src/contracts/examples/oev-example/IChainlinkAtlasWrapper.sol

interface AggregatorInterface {
    function latestAnswer() external view returns (int256);
    function latestTimestamp() external view returns (uint256);
    function latestRound() external view returns (uint256);
    function getAnswer(uint256 roundId) external view returns (int256);
    function getTimestamp(uint256 roundId) external view returns (uint256);

    event AnswerUpdated(int256 indexed current, uint256 indexed roundId, uint256 updatedAt);
    event NewRound(uint256 indexed roundId, address indexed startedBy, uint256 startedAt);
}

interface AggregatorV3Interface_1 {
    function decimals() external view returns (uint8);
    function description() external view returns (string memory);
    function version() external view returns (uint256);

    // getRoundData and latestRoundData should both raise "No data present"
    // if they do not have data to report, instead of returning unset values
    // which could be misinterpreted as actual reported values.
    function getRoundData(
        uint80 _roundId
    )
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);
    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);
}

interface AggregatorV2V3Interface is AggregatorInterface, AggregatorV3Interface_1 { }

interface IChainlinkAtlasWrapper is AggregatorV2V3Interface {
    function transmit(
        bytes calldata report,
        bytes32[] calldata rs,
        bytes32[] calldata ss,
        bytes32 rawVs
    )
        external
        returns (address);

    function setTransmitterStatus(address transmitter, bool trusted) external;
    function withdrawETH(address recipient) external;
    function withdrawERC20(address token, address recipient) external;
}

// src/contracts/libraries/SafetyBits.sol

// NOTE: No user transfers allowed during AllocateValue
uint8 constant SAFE_USER_TRANSFER = uint8(
    1 << (uint8(ExecutionPhase.PreOps)) | 1 << (uint8(ExecutionPhase.UserOperation))
        | 1 << (uint8(ExecutionPhase.PreSolver)) | 1 << (uint8(ExecutionPhase.PostSolver))
        | 1 << (uint8(ExecutionPhase.PostOps))
);

// NOTE: No Dapp transfers allowed during UserOperation
uint8 constant SAFE_DAPP_TRANSFER = uint8(
    1 << (uint8(ExecutionPhase.PreOps)) | 1 << (uint8(ExecutionPhase.PreSolver))
        | 1 << (uint8(ExecutionPhase.PostSolver)) | 1 << (uint8(ExecutionPhase.AllocateValue))
        | 1 << (uint8(ExecutionPhase.PostOps))
);

library SafetyBits {
    function setAndPack(Context_1 memory self, ExecutionPhase phase) internal pure returns (bytes memory packedCtx) {
        self.phase = uint8(phase);
        packedCtx = abi.encodePacked(
            self.bundler,
            self.solverSuccessful,
            self.paymentsSuccessful,
            self.solverIndex,
            self.solverCount,
            uint8(phase),
            self.solverOutcome,
            self.bidFind,
            self.isSimulation,
            uint8(1) // callDepth
        );
    }
}

// src/contracts/types/AtlasErrors.sol

contract AtlasErrors {
    // Simulator
    error Unauthorized();
    error Unreachable();
    error NoAuctionWinner();
    error InvalidEntryFunction();
    error SimulationPassed();

    error UserSimulationFailed();
    error UserSimulationSucceeded();
    error UserUnexpectedSuccess();
    error UserNotFulfilled();

    error BidFindSuccessful(uint256 bidAmount);
    error UnexpectedNonRevert();

    error InvalidSolver();
    error BidNotPaid();
    error InvertedBidExceedsCeiling();
    error BalanceNotReconciled();
    error SolverOpReverted();
    error AlteredControl();
    error InvalidEntry();
    error CallbackNotCalled();
    error PreSolverFailed();
    error PostSolverFailed();
    error InsufficientEscrow();

    error VerificationSimFail(ValidCallsResult);
    error PreOpsSimFail();
    error UserOpSimFail();
    error SolverSimFail(uint256 solverOutcomeResult); // uint param is result returned in `verifySolverOp`
    error AllocateValueSimFail();
    error PostOpsSimFail();
    error ValidCalls(ValidCallsResult);

    // Execution Environment
    error InvalidUser();
    error InvalidTo();
    error InvalidCodeHash();
    error PreOpsDelegatecallFail();
    error UserOpValueExceedsBalance();
    error UserWrapperDelegatecallFail();
    error UserWrapperCallFail();
    error PostOpsDelegatecallFail();
    error PostOpsDelegatecallReturnedFalse();
    error AllocateValueDelegatecallFail();
    error NotEnvironmentOwner();
    error ExecutionEnvironmentBalanceTooLow();

    // Atlas
    error PreOpsFail();
    error UserOpFail();
    // error SolverFail(); // Only sim version of err is used
    error AllocateValueFail();
    error PostOpsFail();
    error InvalidAccess();

    // Escrow
    error UncoveredResult();
    error InvalidEscrowDuration();

    // AtlETH
    error InsufficientUnbondedBalance(uint256 balance, uint256 requested);
    error InsufficientBondedBalance(uint256 balance, uint256 requested);
    error PermitDeadlineExpired();
    error InvalidSigner();
    error EscrowLockActive();
    error InsufficientWithdrawableBalance(uint256 balance, uint256 requested);
    error InsufficientAvailableBalance(uint256 balance, uint256 requested);
    error InsufficientSurchargeBalance(uint256 balance, uint256 requested);
    error InsufficientBalanceForDeduction(uint256 balance, uint256 requested);
    error ValueTooLarge();
    error BidTooHigh(uint256 indexInSolverOps, uint256 bidAmount);

    // DAppIntegration
    error OnlyGovernance();
    error SignatoryActive();
    error InvalidCaller();
    error InvalidDAppControl();
    error DAppNotEnabled();
    error AtlasLockActive();
    error InvalidSignatory();

    // Permit69
    error InvalidEnvironment();
    error EnvironmentMismatch();
    error InvalidLockState();

    // GasAccounting
    error LedgerFinalized(uint8 id);
    error LedgerBalancing(uint8 id);
    error MissingFunds(uint8 id);
    error InsufficientFunds();
    error NoUnfilledRequests();
    error SolverMustReconcile();
    error DoubleReconcile();
    error InvalidExecutionEnvironment(address correctEnvironment);
    error InvalidSolverFrom(address solverFrom);
    error InsufficientSolverBalance(uint256 actual, uint256 msgValue, uint256 holds, uint256 needed);
    error InsufficientAtlETHBalance(uint256 actual, uint256 needed);
    error InsufficientTotalBalance(uint256 shortfall);
    error UnbalancedAccounting();

    // SafetyLocks
    error NotInitialized();
    error AlreadyInitialized();

    // AtlasVerification
    error NoUnusedNonceInBitmap();

    // DAppControl
    error BothUserAndDAppNoncesCannotBeSequential();
    error BothPreOpsAndUserReturnDataCannotBeTracked();
    error InvalidControl();
    error NoDelegatecall();
    error MustBeDelegatecalled();
    error OnlyAtlas();
    error WrongPhase();
    error WrongDepth();
    error InsufficientLocalFunds();
    error NotImplemented();
    error InvertBidValueCannotBeExPostBids();
}

// lib/redstone-oracles-monorepo/packages/on-chain-relayer/contracts/price-feeds/MergedPriceFeedAdapterCommon.sol

abstract contract MergedPriceFeedAdapterCommon {
  event AnswerUpdated(int256 indexed current, uint256 indexed roundId, uint256 updatedAt);

  error CannotUpdateMoreThanOneDataFeed();

  function getPriceFeedAdapter() public view virtual returns (IRedstoneAdapter) {
    return IRedstoneAdapter(address(this));
  }

  function aggregator() public view virtual returns (address) {
    return address(getPriceFeedAdapter());
  }
}

// lib/redstone-oracles-monorepo/packages/on-chain-relayer/contracts/price-feeds/interfaces/IPriceFeed.sol

/**
 * @title Complete price feed interface
 * @author The Redstone Oracles team
 * @dev All required public functions that must be implemented
 * by each Redstone PriceFeed contract
 */
interface IPriceFeed is IPriceFeedLegacy, AggregatorV3Interface_0 {
  /**
   * @notice Returns data feed identifier for the PriceFeed contract
   * @return dataFeedId The identifier of the data feed
   */
  function getDataFeedId() external view returns (bytes32);
}

// src/contracts/interfaces/IDAppControl.sol

interface IDAppControl {
    function preOpsCall(UserOperation calldata userOp) external payable returns (bytes memory);

    function preSolverCall(SolverOperation calldata solverOp, bytes calldata returnData) external payable;

    function postSolverCall(SolverOperation calldata solverOp, bytes calldata returnData) external payable;

    function postOpsCall(bool solved, bytes calldata data) external payable;

    function allocateValueCall(address bidToken, uint256 bidAmount, bytes calldata data) external;

    function getDAppConfig(UserOperation calldata userOp) external view returns (DAppConfig memory dConfig);

    function getCallConfig() external view returns (CallConfig memory callConfig);

    function getBidFormat(UserOperation calldata userOp) external view returns (address bidToken);

    function getBidValue(SolverOperation calldata solverOp) external view returns (uint256);

    function getDAppSignatory() external view returns (address governanceAddress);

    function requireSequentialUserNonces() external view returns (bool isSequential);

    function requireSequentialDAppNonces() external view returns (bool isSequential);

    function preOpsDelegated() external view returns (bool delegated);

    function userDelegated() external view returns (bool delegated);

    function allocatingDelegated() external view returns (bool delegated);

    function verificationDelegated() external view returns (bool delegated);

    function CALL_CONFIG() external view returns (uint32);
}

// src/contracts/interfaces/IAtlas.sol

interface IAtlas {
    // Atlas.sol
    function metacall(
        UserOperation calldata userOp,
        SolverOperation[] calldata solverOps,
        DAppOperation calldata dAppOp
    )
        external
        payable
        returns (bool auctionWon);

    // Factory.sol
    function createExecutionEnvironment(address control) external returns (address executionEnvironment);
    function getExecutionEnvironment(
        address user,
        address control
    )
        external
        view
        returns (address executionEnvironment, uint32 callConfig, bool exists);

    // AtlETH.sol
    function balanceOf(address account) external view returns (uint256);
    function balanceOfBonded(address account) external view returns (uint256);
    function balanceOfUnbonding(address account) external view returns (uint256);
    function accountLastActiveBlock(address account) external view returns (uint256);
    function unbondingCompleteBlock(address account) external view returns (uint256);
    function deposit() external payable;
    function withdraw(uint256 amount) external;
    function bond(uint256 amount) external;
    function depositAndBond(uint256 amountToBond) external payable;
    function unbond(uint256 amount) external;
    function redeem(uint256 amount) external;
    function withdrawSurcharge() external;
    function transferSurchargeRecipient(address newRecipient) external;
    function becomeSurchargeRecipient() external;

    // Permit69.sol
    function transferUserERC20(
        address token,
        address destination,
        uint256 amount,
        address user,
        address control
    )
        external;
    function transferDAppERC20(
        address token,
        address destination,
        uint256 amount,
        address user,
        address control
    )
        external;

    // GasAccounting.sol
    function contribute() external payable;
    function borrow(uint256 amount) external payable;
    function shortfall() external view returns (uint256);
    function reconcile(uint256 maxApprovedGasSpend) external payable returns (uint256 owed);

    // SafetyLocks.sol
    function isUnlocked() external view returns (bool);

    // Storage.sol
    function VERIFICATION() external view returns (address);
    function solverLockData() external view returns (address currentSolver, bool calledBack, bool fulfilled);
    function totalSupply() external view returns (uint256);
    function bondedTotalSupply() external view returns (uint256);
    function accessData(
        address account
    )
        external
        view
        returns (
            uint112 bonded,
            uint32 lastAccessedBlock,
            uint24 auctionWins,
            uint24 auctionFails,
            uint64 totalGasValueUsed
        );
    function solverOpHashes(bytes32 opHash) external view returns (bool);
    function lock() external view returns (address activeEnvironment, uint32 callConfig, uint8 phase);
    function solverLock() external view returns (uint256);
    function cumulativeSurcharge() external view returns (uint256);
    function surchargeRecipient() external view returns (address);
    function pendingSurchargeRecipient() external view returns (address);
}

// src/contracts/libraries/CallBits.sol

library CallBits {
    uint32 internal constant _ONE = uint32(1);

    function buildCallConfig(address control) internal view returns (uint32 callConfig) {
        callConfig = IDAppControl(control).CALL_CONFIG();
    }

    function encodeCallConfig(CallConfig memory callConfig) internal pure returns (uint32 encodedCallConfig) {
        if (callConfig.userNoncesSequential) {
            encodedCallConfig ^= _ONE << uint32(CallConfigIndex.UserNoncesSequential);
        }
        if (callConfig.dappNoncesSequential) {
            encodedCallConfig ^= _ONE << uint32(CallConfigIndex.DAppNoncesSequential);
        }
        if (callConfig.requirePreOps) {
            encodedCallConfig ^= _ONE << uint32(CallConfigIndex.RequirePreOps);
        }
        if (callConfig.trackPreOpsReturnData) {
            encodedCallConfig ^= _ONE << uint32(CallConfigIndex.TrackPreOpsReturnData);
        }
        if (callConfig.trackUserReturnData) {
            encodedCallConfig ^= _ONE << uint32(CallConfigIndex.TrackUserReturnData);
        }
        if (callConfig.delegateUser) {
            encodedCallConfig ^= _ONE << uint32(CallConfigIndex.DelegateUser);
        }
        if (callConfig.requirePreSolver) {
            encodedCallConfig ^= _ONE << uint32(CallConfigIndex.RequirePreSolver);
        }
        if (callConfig.requirePostSolver) {
            encodedCallConfig ^= _ONE << uint32(CallConfigIndex.RequirePostSolver);
        }
        if (callConfig.requirePostOps) {
            encodedCallConfig ^= _ONE << uint32(CallConfigIndex.RequirePostOpsCall);
        }
        if (callConfig.zeroSolvers) {
            encodedCallConfig ^= _ONE << uint32(CallConfigIndex.ZeroSolvers);
        }
        if (callConfig.reuseUserOp) {
            encodedCallConfig ^= _ONE << uint32(CallConfigIndex.ReuseUserOp);
        }
        if (callConfig.userAuctioneer) {
            encodedCallConfig ^= _ONE << uint32(CallConfigIndex.UserAuctioneer);
        }
        if (callConfig.solverAuctioneer) {
            encodedCallConfig ^= _ONE << uint32(CallConfigIndex.SolverAuctioneer);
        }
        if (callConfig.unknownAuctioneer) {
            encodedCallConfig ^= _ONE << uint32(CallConfigIndex.UnknownAuctioneer);
        }
        if (callConfig.verifyCallChainHash) {
            encodedCallConfig ^= _ONE << uint32(CallConfigIndex.VerifyCallChainHash);
        }
        if (callConfig.forwardReturnData) {
            encodedCallConfig ^= _ONE << uint32(CallConfigIndex.ForwardReturnData);
        }
        if (callConfig.requireFulfillment) {
            encodedCallConfig ^= _ONE << uint32(CallConfigIndex.RequireFulfillment);
        }
        if (callConfig.trustedOpHash) {
            encodedCallConfig ^= _ONE << uint32(CallConfigIndex.TrustedOpHash);
        }
        if (callConfig.invertBidValue) {
            encodedCallConfig ^= _ONE << uint32(CallConfigIndex.InvertBidValue);
        }
        if (callConfig.exPostBids) {
            encodedCallConfig ^= _ONE << uint32(CallConfigIndex.ExPostBids);
        }
        if (callConfig.allowAllocateValueFailure) {
            encodedCallConfig ^= _ONE << uint32(CallConfigIndex.AllowAllocateValueFailure);
        }
    }

    function decodeCallConfig(uint32 encodedCallConfig) internal pure returns (CallConfig memory callConfig) {
        callConfig = CallConfig({
            userNoncesSequential: needsSequentialUserNonces(encodedCallConfig),
            dappNoncesSequential: needsSequentialDAppNonces(encodedCallConfig),
            requirePreOps: needsPreOpsCall(encodedCallConfig),
            trackPreOpsReturnData: needsPreOpsReturnData(encodedCallConfig),
            trackUserReturnData: needsUserReturnData(encodedCallConfig),
            delegateUser: needsDelegateUser(encodedCallConfig),
            requirePreSolver: needsPreSolverCall(encodedCallConfig),
            requirePostSolver: needsPostSolverCall(encodedCallConfig),
            requirePostOps: needsPostOpsCall(encodedCallConfig),
            zeroSolvers: allowsZeroSolvers(encodedCallConfig),
            reuseUserOp: allowsReuseUserOps(encodedCallConfig),
            userAuctioneer: allowsUserAuctioneer(encodedCallConfig),
            solverAuctioneer: allowsSolverAuctioneer(encodedCallConfig),
            unknownAuctioneer: allowsUnknownAuctioneer(encodedCallConfig),
            verifyCallChainHash: verifyCallChainHash(encodedCallConfig),
            forwardReturnData: forwardReturnData(encodedCallConfig),
            requireFulfillment: needsFulfillment(encodedCallConfig),
            trustedOpHash: allowsTrustedOpHash(encodedCallConfig),
            invertBidValue: invertsBidValue(encodedCallConfig),
            exPostBids: exPostBids(encodedCallConfig),
            allowAllocateValueFailure: allowAllocateValueFailure(encodedCallConfig)
        });
    }

    function needsSequentialUserNonces(uint32 callConfig) internal pure returns (bool sequential) {
        sequential = callConfig & (1 << uint32(CallConfigIndex.UserNoncesSequential)) != 0;
    }

    function needsSequentialDAppNonces(uint32 callConfig) internal pure returns (bool sequential) {
        sequential = callConfig & (1 << uint32(CallConfigIndex.DAppNoncesSequential)) != 0;
    }

    function needsPreOpsCall(uint32 callConfig) internal pure returns (bool needsPreOps) {
        needsPreOps = callConfig & (1 << uint32(CallConfigIndex.RequirePreOps)) != 0;
    }

    function needsPreOpsReturnData(uint32 callConfig) internal pure returns (bool needsReturnData) {
        needsReturnData = callConfig & (1 << uint32(CallConfigIndex.TrackPreOpsReturnData)) != 0;
    }

    function needsUserReturnData(uint32 callConfig) internal pure returns (bool needsReturnData) {
        needsReturnData = callConfig & (1 << uint32(CallConfigIndex.TrackUserReturnData)) != 0;
    }

    function needsDelegateUser(uint32 callConfig) internal pure returns (bool delegateUser) {
        delegateUser = callConfig & (1 << uint32(CallConfigIndex.DelegateUser)) != 0;
    }

    function needsPreSolverCall(uint32 callConfig) internal pure returns (bool needsPreSolver) {
        needsPreSolver = callConfig & (1 << uint32(CallConfigIndex.RequirePreSolver)) != 0;
    }

    function needsPostSolverCall(uint32 callConfig) internal pure returns (bool needsPostSolver) {
        needsPostSolver = callConfig & (1 << uint32(CallConfigIndex.RequirePostSolver)) != 0;
    }

    function needsPostOpsCall(uint32 callConfig) internal pure returns (bool needsPostOps) {
        needsPostOps = callConfig & (1 << uint32(CallConfigIndex.RequirePostOpsCall)) != 0;
    }

    function allowsZeroSolvers(uint32 callConfig) internal pure returns (bool zeroSolvers) {
        zeroSolvers = callConfig & (1 << uint32(CallConfigIndex.ZeroSolvers)) != 0;
    }

    function allowsReuseUserOps(uint32 callConfig) internal pure returns (bool reuseUserOp) {
        reuseUserOp = callConfig & (1 << uint32(CallConfigIndex.ReuseUserOp)) != 0;
    }

    function allowsUserAuctioneer(uint32 callConfig) internal pure returns (bool userAuctioneer) {
        userAuctioneer = callConfig & (1 << uint32(CallConfigIndex.UserAuctioneer)) != 0;
    }

    function allowsSolverAuctioneer(uint32 callConfig) internal pure returns (bool userAuctioneer) {
        userAuctioneer = callConfig & (1 << uint32(CallConfigIndex.SolverAuctioneer)) != 0;
    }

    function allowsUnknownAuctioneer(uint32 callConfig) internal pure returns (bool unknownAuctioneer) {
        unknownAuctioneer = callConfig & (1 << uint32(CallConfigIndex.UnknownAuctioneer)) != 0;
    }

    function verifyCallChainHash(uint32 callConfig) internal pure returns (bool verify) {
        verify = callConfig & (1 << uint32(CallConfigIndex.VerifyCallChainHash)) != 0;
    }

    function forwardReturnData(uint32 callConfig) internal pure returns (bool) {
        return callConfig & (1 << uint32(CallConfigIndex.ForwardReturnData)) != 0;
    }

    function needsFulfillment(uint32 callConfig) internal pure returns (bool) {
        return callConfig & (1 << uint32(CallConfigIndex.RequireFulfillment)) != 0;
    }

    function allowsTrustedOpHash(uint32 callConfig) internal pure returns (bool) {
        return callConfig & (1 << uint32(CallConfigIndex.TrustedOpHash)) != 0;
    }

    function invertsBidValue(uint32 callConfig) internal pure returns (bool) {
        return callConfig & (1 << uint32(CallConfigIndex.InvertBidValue)) != 0;
    }

    function exPostBids(uint32 callConfig) internal pure returns (bool) {
        return callConfig & (1 << uint32(CallConfigIndex.ExPostBids)) != 0;
    }

    function allowAllocateValueFailure(uint32 callConfig) internal pure returns (bool) {
        return callConfig & (1 << uint32(CallConfigIndex.AllowAllocateValueFailure)) != 0;
    }
}

// lib/redstone-oracles-monorepo/packages/on-chain-relayer/contracts/price-feeds/PriceFeedBase.sol

/**
 * @title Main logic of the price feed contract
 * @author The Redstone Oracles team
 * @dev Implementation of common functions for the PriceFeed contract
 * that queries data from the specified PriceFeedAdapter
 * 
 * It can be used by projects that have already implemented with Chainlink-like
 * price feeds and would like to minimise changes in their existing codebase.
 * 
 * If you are flexible, it's much better (and cheaper in terms of gas) to query
 * the PriceFeedAdapter contract directly
 */
abstract contract PriceFeedBase is IPriceFeed, Initializable {
  uint256 internal constant INT256_MAX = uint256(type(int256).max);

  error UnsafeUintToIntConversion(uint256 value);

  /**
   * @dev Helpful function for upgradable contracts
   */
  function initialize() public virtual initializer {
    // We don't have storage variables, but we keep this function
    // Because it is used for contract setup in upgradable contracts
  }

  /**
   * @notice Returns data feed identifier for the PriceFeed contract
   * @return dataFeedId The identifier of the data feed
   */
  function getDataFeedId() public view virtual returns (bytes32);

  /**
   * @notice Returns the address of the price feed adapter
   * @return address The address of the price feed adapter
   */
  function getPriceFeedAdapter() public view virtual returns (IRedstoneAdapter);

  /**
   * @notice Returns the number of decimals for the price feed
   * @dev By default, RedStone uses 8 decimals for data feeds
   * @return decimals The number of decimals in the price feed values
   */
  function decimals() public virtual pure override returns (uint8) {
    return 8;
  }

  /**
   * @notice Description of the Price Feed
   * @return description
   */
  function description() public view virtual override returns (string memory) {
    return "Redstone Price Feed";
  }

  /**
   * @notice Version of the Price Feed
   * @dev Currently it has no specific motivation and was added
   * only to be compatible with the Chainlink interface
   * @return version
   */
  function version() public virtual pure override returns (uint256) {
    return 1;
  }

  /**
   * @notice Returns details of the latest successful update round
   * @dev It uses few helpful functions to abstract logic of getting
   * latest round id and value
   * @return roundId The number of the latest round
   * @return answer The latest reported value
   * @return startedAt Block timestamp when the latest successful round started
   * @return updatedAt Block timestamp of the latest successful round
   * @return answeredInRound The number of the latest round
   */
  function latestRoundData()
    public
    view
    override
    virtual
    returns (
      uint80 roundId,
      int256 answer,
      uint256 startedAt,
      uint256 updatedAt,
      uint80 answeredInRound
    )
  {
    roundId = latestRound();
    answer = latestAnswer();

    uint256 blockTimestamp = getPriceFeedAdapter().getBlockTimestampFromLatestUpdate();

    // These values are equal after chainlink’s OCR update
    startedAt = blockTimestamp;
    updatedAt = blockTimestamp;

    // We want to be compatible with Chainlink's interface
    // And in our case the roundId is always equal to answeredInRound
    answeredInRound = roundId;
  }

  /**
   * @notice Old Chainlink function for getting the latest successfully reported value
   * @return latestAnswer The latest successfully reported value
   */
  function latestAnswer() public virtual view returns (int256) {
    bytes32 dataFeedId = getDataFeedId();

    uint256 uintAnswer = getPriceFeedAdapter().getValueForDataFeed(dataFeedId);

    if (uintAnswer > INT256_MAX) {
      revert UnsafeUintToIntConversion(uintAnswer);
    }

    return int256(uintAnswer);
  }

  /**
   * @notice Old Chainlink function for getting the number of latest round
   * @return latestRound The number of the latest update round
   */
  function latestRound() public view virtual returns (uint80);
}

// src/contracts/dapp/ControlTemplate.sol

abstract contract DAppControlTemplate {
    uint32 internal constant DEFAULT_SOLVER_GAS_LIMIT = 1_000_000;

    constructor() { }

    // Virtual functions to be overridden by participating dApp governance
    // (not FastLane) prior to deploying contract. Note that dApp governance
    // will "own" this contract but that it should be immutable.

    /////////////////////////////////////////////////////////
    //                  PRE OPS                            //
    /////////////////////////////////////////////////////////
    //
    // PreOps:
    // Data should be decoded as:
    //
    //     bytes calldata userOpData
    //

    // _preOpsCall
    // Details:
    //  preOps/delegate =
    //      Inputs: User's calldata
    //      Function: Executing the function set by DAppControl
    //      Container: Inside of the FastLane ExecutionEnvironment
    //      Access: With storage access (read + write) only to the ExecutionEnvironment
    //
    // DApp exposure: Trustless
    // User exposure: Trustless
    function _preOpsCall(UserOperation calldata) internal virtual returns (bytes memory) {
        revert AtlasErrors.NotImplemented();
    }

    /////////////////////////////////////////////////////////
    //         CHECK USER OPERATION                        //
    /////////////////////////////////////////////////////////
    //
    // PreOps:
    // Data should be decoded as:
    //
    //     bytes memory userOpData
    //

    // _checkUserOperation
    // Details:
    //  preOps/delegate =
    //      Inputs: User's calldata
    //      Function: Executing the function set by DAppControl
    //      Container: Inside of the FastLane ExecutionEnvironment
    //      Access: With storage access (read + write) only to the ExecutionEnvironment
    //
    // DApp exposure: Trustless
    // User exposure: Trustless
    function _checkUserOperation(UserOperation memory) internal virtual { }

    /////////////////////////////////////////////////////////
    //                MEV ALLOCATION                       //
    /////////////////////////////////////////////////////////
    //
    // _allocateValueCall
    // Details:
    //  allocate/delegate =
    //      Inputs: MEV Profits (ERC20 balances)
    //      Function: Executing the function set by DAppControl / MEVAllocator
    //      Container: Inside of the FastLane ExecutionEnvironment
    //      Access: With storage access (read + write) only to the ExecutionEnvironment
    //
    // DApp exposure: Trustless
    // User exposure: Trustless
    function _allocateValueCall(address bidToken, uint256 bidAmount, bytes calldata data) internal virtual;

    /////////////////////////////////////////////////////////
    //              INTENT FULFILLMENT                     //
    /////////////////////////////////////////////////////////
    //

    // _preSolverCall
    //
    // Details:
    //  Data should be decoded as:
    //
    //    address solverTo, bytes memory returnData
    //
    //  fulfillment(preOps)/delegatecall =
    //      Inputs: preOps call's returnData, winning solver to address
    //      Function: Executing the function set by DAppControl
    //      Container: Inside of the FastLane ExecutionEnvironment
    //      Access: Storage access (read+write) to the ExecutionEnvironment contract
    //      NOTE: This happens *inside* of the solver's try/catch wrapper
    //      and is designed to give the solver everything they need to fulfill
    //      the user's 'intent.'
    //      NOTE: If using invertsBid mode, the inventory being invert-bidded on should be in the ExecutionEnvironment
    //      before the PreSolver phase - it should be moved in during the PreOps or UserOperation phases.
    //      NOTE: If using invertsBid mode, the dapp should either transfer the inventory to the solver in this
    //      PreSolver phase, or set an allowance so the solver can pull the tokens during their SolverOperation.

    function _preSolverCall(SolverOperation calldata, bytes calldata) internal virtual {
        revert AtlasErrors.NotImplemented();
    }

    // _postSolverCall
    //
    // Details:
    //
    //  Data should be decoded as:
    //
    //    address solverTo, bytes memory returnData
    //

    //  fulfillment(verification)/delegatecall =
    //      Inputs: preOps call's returnData, winning solver to address
    //      Function: Executing the function set by DAppControl
    //      Container: Inside of the FastLane ExecutionEnvironment
    //      Access: Storage access (read+write) to the ExecutionEnvironment contract
    //      NOTE: This happens *inside* of the solver's try/catch wrapper
    //      and is designed to make sure that the solver is fulfilling
    //      the user's 'intent.'

    function _postSolverCall(SolverOperation calldata, bytes calldata) internal virtual {
        revert AtlasErrors.NotImplemented();
    }

    /////////////////////////////////////////////////////////
    //                  VERIFICATION                       //
    /////////////////////////////////////////////////////////
    //
    // Data should be decoded as:
    //
    //    bytes memory returnData
    //

    // _postOpsCall
    // Details:
    //  verification/delegatecall =
    //      Inputs: User's return data + preOps call's returnData
    //      Function: Executing the function set by DAppControl
    //      Container: Inside of the FastLane ExecutionEnvironment
    //      Access: Storage access (read+write) to the ExecutionEnvironment contract
    function _postOpsCall(bool, bytes calldata) internal virtual {
        revert AtlasErrors.NotImplemented();
    }

    /////////////////////////////////////////////////////////
    //                 GETTERS & HELPERS                   //
    /////////////////////////////////////////////////////////
    //
    // View functions used by the backend to verify bid format
    // and by the factory and DAppVerification to verify the
    // backend.
    function getBidFormat(UserOperation calldata userOp) public view virtual returns (address bidToken);

    function getBidValue(SolverOperation calldata solverOp) public view virtual returns (uint256);

    function getSolverGasLimit() public view virtual returns (uint32) {
        return DEFAULT_SOLVER_GAS_LIMIT;
    }
}

// lib/redstone-oracles-monorepo/packages/evm-connector/contracts/core/RedstoneConsumerBase.sol

/**
 * @title The base contract with the main Redstone logic
 * @author The Redstone Oracles team
 * @dev Do not use this contract directly in consumer contracts, take a
 * look at `RedstoneConsumerNumericBase` and `RedstoneConsumerBytesBase` instead
 */
abstract contract RedstoneConsumerBase is CalldataExtractor {

  error GetDataServiceIdNotImplemented();

  /* ========== VIRTUAL FUNCTIONS (MAY BE OVERRIDDEN IN CHILD CONTRACTS) ========== */

  /**
   * @dev This function must be implemented by the child consumer contract.
   * It should return dataServiceId which DataServiceWrapper will use if not provided explicitly .
   * If not overridden, value will always have to be provided explicitly in DataServiceWrapper.
   * @return dataServiceId being consumed by contract
   */
  function getDataServiceId() public view virtual returns (string memory) {
    revert GetDataServiceIdNotImplemented();
  }

  /**
   * @dev This function must be implemented by the child consumer contract.
   * It should return a unique index for a given signer address if the signer
   * is authorised, otherwise it should revert
   * @param receivedSigner The address of a signer, recovered from ECDSA signature
   * @return Unique index for a signer in the range [0..255]
   */
  function getAuthorisedSignerIndex(address receivedSigner) public view virtual returns (uint8);

  /**
   * @dev This function may be overridden by the child consumer contract.
   * It should validate the timestamp against the current time (block.timestamp)
   * It should revert with a helpful message if the timestamp is not valid
   * @param receivedTimestampMilliseconds Timestamp extracted from calldata
   */
  function validateTimestamp(uint256 receivedTimestampMilliseconds) public view virtual {
    RedstoneDefaultsLib.validateTimestamp(receivedTimestampMilliseconds);
  }

  /**
   * @dev This function should be overridden by the child consumer contract.
   * @return The minimum required value of unique authorised signers
   */
  function getUniqueSignersThreshold() public view virtual returns (uint8) {
    return 1;
  }

  /**
   * @dev This function may be overridden by the child consumer contract.
   * It should aggregate values from different signers to a single uint value.
   * By default, it calculates the median value
   * @param values An array of uint256 values from different signers
   * @return Result of the aggregation in the form of a single number
   */
  function aggregateValues(uint256[] memory values) public view virtual returns (uint256) {
    return RedstoneDefaultsLib.aggregateValues(values);
  }

  /* ========== FUNCTIONS WITH IMPLEMENTATION (CAN NOT BE OVERRIDDEN) ========== */

  /**
   * @dev This is an internal helpful function for secure extraction oracle values
   * from the tx calldata. Security is achieved by signatures verification, timestamp
   * validation, and aggregating values from different authorised signers into a
   * single numeric value. If any of the required conditions (e.g. packages with different 
   * timestamps or insufficient number of authorised signers) do not match, the function 
   * will revert.
   *
   * Note! You should not call this function in a consumer contract. You can use
   * `getOracleNumericValuesFromTxMsg` or `getOracleNumericValueFromTxMsg` instead.
   *
   * @param dataFeedIds An array of unique data feed identifiers
   * @return An array of the extracted and verified oracle values in the same order
   * as they are requested in dataFeedIds array
   * @return dataPackagesTimestamp timestamp equal for all data packages
   */
  function _securelyExtractOracleValuesAndTimestampFromTxMsg(bytes32[] memory dataFeedIds)
    internal
    view
    returns (uint256[] memory, uint256 dataPackagesTimestamp)
  {
    // Initializing helpful variables and allocating memory
    uint256[] memory uniqueSignerCountForDataFeedIds = new uint256[](dataFeedIds.length);
    uint256[] memory signersBitmapForDataFeedIds = new uint256[](dataFeedIds.length);
    uint256[][] memory valuesForDataFeeds = new uint256[][](dataFeedIds.length);
    for (uint256 i = 0; i < dataFeedIds.length;) {
      // The line below is commented because newly allocated arrays are filled with zeros
      // But we left it for better readability
      // signersBitmapForDataFeedIds[i] = 0; // <- setting to an empty bitmap
      valuesForDataFeeds[i] = new uint256[](getUniqueSignersThreshold());
      unchecked {
        i++;
      }
    }

    // Extracting the number of data packages from calldata
    uint256 calldataNegativeOffset = _extractByteSizeOfUnsignedMetadata();
    uint256 dataPackagesCount;
    (dataPackagesCount, calldataNegativeOffset) = _extractDataPackagesCountFromCalldata(calldataNegativeOffset);

    // Saving current free memory pointer
    uint256 freeMemPtr;
    assembly {
      freeMemPtr := mload(FREE_MEMORY_PTR)
    }

    // Data packages extraction in a loop
    for (uint256 dataPackageIndex = 0; dataPackageIndex < dataPackagesCount;) {
      // Extract data package details and update calldata offset
      uint256 dataPackageTimestamp;
      (calldataNegativeOffset, dataPackageTimestamp) = _extractDataPackage(
        dataFeedIds,
        uniqueSignerCountForDataFeedIds,
        signersBitmapForDataFeedIds,
        valuesForDataFeeds,
        calldataNegativeOffset
      );

      if (dataPackageTimestamp == 0) {
        revert DataTimestampCannotBeZero();
      }

      if (dataPackageTimestamp != dataPackagesTimestamp && dataPackagesTimestamp != 0) {
        revert TimestampsMustBeEqual();
      }

      dataPackagesTimestamp = dataPackageTimestamp;

      // Shifting memory pointer back to the "safe" value
      assembly {
        mstore(FREE_MEMORY_PTR, freeMemPtr)
      }
      unchecked {
        dataPackageIndex++;
      }
    }

    // Validating numbers of unique signers and calculating aggregated values for each dataFeedId
    return (_getAggregatedValues(valuesForDataFeeds, uniqueSignerCountForDataFeedIds), dataPackagesTimestamp);
  }

  /**
   * @dev This is a private helpful function, which extracts data for a data package based
   * on the given negative calldata offset, verifies them, and in the case of successful
   * verification updates the corresponding data package values in memory
   *
   * @param dataFeedIds an array of unique data feed identifiers
   * @param uniqueSignerCountForDataFeedIds an array with the numbers of unique signers
   * for each data feed
   * @param signersBitmapForDataFeedIds an array of signer bitmaps for data feeds
   * @param valuesForDataFeeds 2-dimensional array, valuesForDataFeeds[i][j] contains
   * j-th value for the i-th data feed
   * @param calldataNegativeOffset negative calldata offset for the given data package
   *
   * @return nextCalldataNegativeOffset negative calldata offset for the next data package
   * @return dataPackageTimestamp data package timestamp
   */
  function _extractDataPackage(
    bytes32[] memory dataFeedIds,
    uint256[] memory uniqueSignerCountForDataFeedIds,
    uint256[] memory signersBitmapForDataFeedIds,
    uint256[][] memory valuesForDataFeeds,
    uint256 calldataNegativeOffset
  ) private view returns (uint256 nextCalldataNegativeOffset, uint256 dataPackageTimestamp) {
    uint256 signerIndex;

    (
      uint256 dataPointsCount,
      uint256 eachDataPointValueByteSize
    ) = _extractDataPointsDetailsForDataPackage(calldataNegativeOffset);

    // We use scopes to resolve problem with too deep stack
    {
      address signerAddress;
      bytes32 signedHash;
      bytes memory signedMessage;
      uint256 signedMessageBytesCount;
      uint48 extractedTimestamp;

      signedMessageBytesCount = dataPointsCount * (eachDataPointValueByteSize + DATA_POINT_SYMBOL_BS)
        + DATA_PACKAGE_WITHOUT_DATA_POINTS_AND_SIG_BS; //DATA_POINT_VALUE_BYTE_SIZE_BS + TIMESTAMP_BS + DATA_POINTS_COUNT_BS

      uint256 timestampCalldataOffset = msg.data.length - 
        (calldataNegativeOffset + TIMESTAMP_NEGATIVE_OFFSET_IN_DATA_PACKAGE_WITH_STANDARD_SLOT_BS);

      uint256 signedMessageCalldataOffset = msg.data.length - 
        (calldataNegativeOffset + SIG_BS + signedMessageBytesCount);

      assembly {
        // Extracting the signed message
        signedMessage := extractBytesFromCalldata(
          signedMessageCalldataOffset,
          signedMessageBytesCount
        )

        // Hashing the signed message
        signedHash := keccak256(add(signedMessage, BYTES_ARR_LEN_VAR_BS), signedMessageBytesCount)

        // Extracting timestamp
        extractedTimestamp := calldataload(timestampCalldataOffset)

        function initByteArray(bytesCount) -> ptr {
          ptr := mload(FREE_MEMORY_PTR)
          mstore(ptr, bytesCount)
          ptr := add(ptr, BYTES_ARR_LEN_VAR_BS)
          mstore(FREE_MEMORY_PTR, add(ptr, bytesCount))
        }

        function extractBytesFromCalldata(offset, bytesCount) -> extractedBytes {
          let extractedBytesStartPtr := initByteArray(bytesCount)
          calldatacopy(
            extractedBytesStartPtr,
            offset,
            bytesCount
          )
          extractedBytes := sub(extractedBytesStartPtr, BYTES_ARR_LEN_VAR_BS)
        }
      }

      dataPackageTimestamp = extractedTimestamp;

      // Verifying the off-chain signature against on-chain hashed data
      signerAddress = SignatureLib.recoverSignerAddress(
        signedHash,
        calldataNegativeOffset + SIG_BS
      );
      signerIndex = getAuthorisedSignerIndex(signerAddress);
    }

    // Updating helpful arrays
    {
      calldataNegativeOffset = calldataNegativeOffset + DATA_PACKAGE_WITHOUT_DATA_POINTS_BS;
      bytes32 dataPointDataFeedId;
      uint256 dataPointValue;
      for (uint256 dataPointIndex = 0; dataPointIndex < dataPointsCount;) {
        calldataNegativeOffset = calldataNegativeOffset + eachDataPointValueByteSize + DATA_POINT_SYMBOL_BS;
        // Extracting data feed id and value for the current data point
        (dataPointDataFeedId, dataPointValue) = _extractDataPointValueAndDataFeedId(
          calldataNegativeOffset,
          eachDataPointValueByteSize
        );

        for (
          uint256 dataFeedIdIndex = 0;
          dataFeedIdIndex < dataFeedIds.length;
        ) {
          if (dataPointDataFeedId == dataFeedIds[dataFeedIdIndex]) {
            uint256 bitmapSignersForDataFeedId = signersBitmapForDataFeedIds[dataFeedIdIndex];

            if (
              !BitmapLib.getBitFromBitmap(bitmapSignersForDataFeedId, signerIndex) && /* current signer was not counted for current dataFeedId */
              uniqueSignerCountForDataFeedIds[dataFeedIdIndex] < getUniqueSignersThreshold()
            ) {
              // Add new value
              valuesForDataFeeds[dataFeedIdIndex][uniqueSignerCountForDataFeedIds[dataFeedIdIndex]] = dataPointValue;

              // Increase unique signer counter
              uniqueSignerCountForDataFeedIds[dataFeedIdIndex]++;

              // Update signers bitmap
              signersBitmapForDataFeedIds[dataFeedIdIndex] = BitmapLib.setBitInBitmap(
                bitmapSignersForDataFeedId,
                signerIndex
              );
            }

            // Breaking, as there couldn't be several indexes for the same feed ID
            break;
          }
          unchecked {
            dataFeedIdIndex++;
          }
        }
        unchecked {
           dataPointIndex++;
        }
      }
    }

    return (calldataNegativeOffset, dataPackageTimestamp);
  }

  /**
   * @dev This is a private helpful function, which aggregates values from different
   * authorised signers for the given arrays of values for each data feed
   *
   * @param valuesForDataFeeds 2-dimensional array, valuesForDataFeeds[i][j] contains
   * j-th value for the i-th data feed
   * @param uniqueSignerCountForDataFeedIds an array with the numbers of unique signers
   * for each data feed
   *
   * @return An array of the aggregated values
   */
  function _getAggregatedValues(
    uint256[][] memory valuesForDataFeeds,
    uint256[] memory uniqueSignerCountForDataFeedIds
  ) private view returns (uint256[] memory) {
    uint256[] memory aggregatedValues = new uint256[](valuesForDataFeeds.length);
    uint256 uniqueSignersThreshold = getUniqueSignersThreshold();

    for (uint256 dataFeedIndex = 0; dataFeedIndex < valuesForDataFeeds.length; dataFeedIndex++) {
      if (uniqueSignerCountForDataFeedIds[dataFeedIndex] < uniqueSignersThreshold) {
        revert InsufficientNumberOfUniqueSigners(
          uniqueSignerCountForDataFeedIds[dataFeedIndex],
          uniqueSignersThreshold);
      }
      uint256 aggregatedValueForDataFeedId = aggregateValues(valuesForDataFeeds[dataFeedIndex]);
      aggregatedValues[dataFeedIndex] = aggregatedValueForDataFeedId;
    }

    return aggregatedValues;
  }
}

// lib/redstone-oracles-monorepo/packages/on-chain-relayer/contracts/price-feeds/without-rounds/PriceFeedWithoutRounds.sol

/**
 * @title Implementation of a price feed contract without rounds support
 * @author The Redstone Oracles team
 * @dev This contract is abstract. The actual contract instance
 * must implement the following functions:
 * - getDataFeedId
 * - getPriceFeedAdapter
 */
abstract contract PriceFeedWithoutRounds is PriceFeedBase {
  uint80 constant DEFAULT_ROUND = 1;

  error GetRoundDataCanBeOnlyCalledWithLatestRound(uint80 requestedRoundId);

  /**
   * @dev We always return 1, since we do not support rounds in this contract
   */
  function latestRound() public pure override returns (uint80) {
    return DEFAULT_ROUND;
  }
  
  /**
   * @dev There are possible use cases that some contracts don't need values from old rounds
   * but still rely on `getRoundData` or `latestRounud` functions
   */
  function getRoundData(uint80 requestedRoundId) public view override returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) {
    if (requestedRoundId != latestRound()) {
      revert GetRoundDataCanBeOnlyCalledWithLatestRound(requestedRoundId);
    }
    return latestRoundData();
  }
}

// src/contracts/interfaces/IAtlasVerification.sol

interface IAtlasVerification {
    // AtlasVerification.sol
    function validateCalls(
        DAppConfig calldata dConfig,
        UserOperation calldata userOp,
        SolverOperation[] calldata solverOps,
        DAppOperation calldata dAppOp,
        uint256 msgValue,
        address msgSender,
        bool isSimulation
    )
        external
        returns (ValidCallsResult);
    function verifySolverOp(
        SolverOperation calldata solverOp,
        bytes32 userOpHash,
        uint256 userMaxFeePerGas,
        address bundler,
        bool allowsTrustedOpHash
    )
        external
        view
        returns (uint256 result);
    function verifyCallConfig(uint32 callConfig) external view returns (ValidCallsResult);
    function getUserOperationHash(UserOperation calldata userOp) external view returns (bytes32 hash);
    function getUserOperationPayload(UserOperation calldata userOp) external view returns (bytes32 payload);
    function getSolverPayload(SolverOperation calldata solverOp) external view returns (bytes32 payload);
    function getDAppOperationPayload(DAppOperation calldata dAppOp) external view returns (bytes32 payload);
    function getDomainSeparator() external view returns (bytes32 domainSeparator);

    // NonceManager.sol
    function getUserNextNonce(address user, bool sequential) external view returns (uint256 nextNonce);
    function getUserNextNonSeqNonceAfter(address user, uint256 refNonce) external view returns (uint256);
    function getDAppNextNonce(address dApp) external view returns (uint256 nextNonce);
    function userSequentialNonceTrackers(address account) external view returns (uint256 lastUsedSeqNonce);
    function dAppSequentialNonceTrackers(address account) external view returns (uint256 lastUsedSeqNonce);
    function userNonSequentialNonceTrackers(
        address account,
        uint248 wordIndex
    )
        external
        view
        returns (uint256 bitmap);

    // DAppIntegration.sol
    function initializeGovernance(address control) external;
    function addSignatory(address control, address signatory) external;
    function removeSignatory(address control, address signatory) external;
    function changeDAppGovernance(address oldGovernance, address newGovernance) external;
    function disableDApp(address control) external;
    function getGovFromControl(address control) external view returns (address);
    function isDAppSignatory(address control, address signatory) external view returns (bool);
    function signatories(bytes32 key) external view returns (bool);
    function dAppSignatories(address control) external view returns (address[] memory);
}

// lib/redstone-oracles-monorepo/packages/evm-connector/contracts/core/RedstoneConsumerNumericBase.sol

/**
 * @title The base contract for Redstone consumers' contracts that allows to
 * securely calculate numeric redstone oracle values
 * @author The Redstone Oracles team
 * @dev This contract can extend other contracts to allow them
 * securely fetch Redstone oracle data from transactions calldata
 */
abstract contract RedstoneConsumerNumericBase is RedstoneConsumerBase {
  /**
   * @dev This function can be used in a consumer contract to securely extract an
   * oracle value for a given data feed id. Security is achieved by
   * signatures verification, timestamp validation, and aggregating values
   * from different authorised signers into a single numeric value. If any of the
   * required conditions do not match, the function will revert.
   * Note! This function expects that tx calldata contains redstone payload in the end
   * Learn more about redstone payload here: https://github.com/redstone-finance/redstone-oracles-monorepo/tree/main/packages/evm-connector#readme
   * @param dataFeedId bytes32 value that uniquely identifies the data feed
   * @return Extracted and verified numeric oracle value for the given data feed id
   */
  function getOracleNumericValueFromTxMsg(bytes32 dataFeedId)
    internal
    view
    virtual
    returns (uint256)
  {
    bytes32[] memory dataFeedIds = new bytes32[](1);
    dataFeedIds[0] = dataFeedId;
    return getOracleNumericValuesFromTxMsg(dataFeedIds)[0];
  }

  /**
   * @dev This function can be used in a consumer contract to securely extract several
   * numeric oracle values for a given array of data feed ids. Security is achieved by
   * signatures verification, timestamp validation, and aggregating values
   * from different authorised signers into a single numeric value. If any of the
   * required conditions do not match, the function will revert.
   * Note! This function expects that tx calldata contains redstone payload in the end
   * Learn more about redstone payload here: https://github.com/redstone-finance/redstone-oracles-monorepo/tree/main/packages/evm-connector#readme
   * @param dataFeedIds An array of unique data feed identifiers
   * @return An array of the extracted and verified oracle values in the same order
   * as they are requested in the dataFeedIds array
   */
  function getOracleNumericValuesFromTxMsg(bytes32[] memory dataFeedIds)
    internal
    view
    virtual
    returns (uint256[] memory)
  {
    (uint256[] memory values, uint256 timestamp) = _securelyExtractOracleValuesAndTimestampFromTxMsg(dataFeedIds);
    validateTimestamp(timestamp);
    return values;
  }

  /**
   * @dev This function can be used in a consumer contract to securely extract several
   * numeric oracle values for a given array of data feed ids. Security is achieved by
   * signatures verification and aggregating values from different authorised signers 
   * into a single numeric value. If any of the required conditions do not match, 
   * the function will revert.
   * Note! This function returns the timestamp of the packages (it requires it to be 
   * the same for all), but does not validate this timestamp.
   * Note! This function expects that tx calldata contains redstone payload in the end
   * Learn more about redstone payload here: https://github.com/redstone-finance/redstone-oracles-monorepo/tree/main/packages/evm-connector#readme
   * @param dataFeedIds An array of unique data feed identifiers
   * @return An array of the extracted and verified oracle values in the same order
   * as they are requested in the dataFeedIds array and data packages timestamp
   */
   function getOracleNumericValuesAndTimestampFromTxMsg(bytes32[] memory dataFeedIds)
    internal
    view
    virtual
    returns (uint256[] memory, uint256)
  {
    return _securelyExtractOracleValuesAndTimestampFromTxMsg(dataFeedIds);
  }

  /**
   * @dev This function works similarly to the `getOracleNumericValuesFromTxMsg` with the
   * only difference that it allows to request oracle data for an array of data feeds
   * that may contain duplicates
   * 
   * @param dataFeedIdsWithDuplicates An array of data feed identifiers (duplicates are allowed)
   * @return An array of the extracted and verified oracle values in the same order
   * as they are requested in the dataFeedIdsWithDuplicates array
   */
  function getOracleNumericValuesWithDuplicatesFromTxMsg(bytes32[] memory dataFeedIdsWithDuplicates) internal view returns (uint256[] memory) {
    // Building an array without duplicates
    bytes32[] memory dataFeedIdsWithoutDuplicates = new bytes32[](dataFeedIdsWithDuplicates.length);
    bool alreadyIncluded;
    uint256 uniqueDataFeedIdsCount = 0;

    for (uint256 indexWithDup = 0; indexWithDup < dataFeedIdsWithDuplicates.length; indexWithDup++) {
      // Checking if current element is already included in `dataFeedIdsWithoutDuplicates`
      alreadyIncluded = false;
      for (uint256 indexWithoutDup = 0; indexWithoutDup < uniqueDataFeedIdsCount; indexWithoutDup++) {
        if (dataFeedIdsWithoutDuplicates[indexWithoutDup] == dataFeedIdsWithDuplicates[indexWithDup]) {
          alreadyIncluded = true;
          break;
        }
      }

      // Adding if not included
      if (!alreadyIncluded) {
        dataFeedIdsWithoutDuplicates[uniqueDataFeedIdsCount] = dataFeedIdsWithDuplicates[indexWithDup];
        uniqueDataFeedIdsCount++;
      }
    }

    // Overriding dataFeedIdsWithoutDuplicates.length
    // Equivalent to: dataFeedIdsWithoutDuplicates.length = uniqueDataFeedIdsCount;
    assembly {
      mstore(dataFeedIdsWithoutDuplicates, uniqueDataFeedIdsCount)
    }

    // Requesting oracle values (without duplicates)
    (uint256[] memory valuesWithoutDuplicates, uint256 timestamp) = _securelyExtractOracleValuesAndTimestampFromTxMsg(dataFeedIdsWithoutDuplicates);
    validateTimestamp(timestamp);

    // Preparing result values array
    uint256[] memory valuesWithDuplicates = new uint256[](dataFeedIdsWithDuplicates.length);
    for (uint256 indexWithDup = 0; indexWithDup < dataFeedIdsWithDuplicates.length; indexWithDup++) {
      for (uint256 indexWithoutDup = 0; indexWithoutDup < dataFeedIdsWithoutDuplicates.length; indexWithoutDup++) {
        if (dataFeedIdsWithDuplicates[indexWithDup] == dataFeedIdsWithoutDuplicates[indexWithoutDup]) {
          valuesWithDuplicates[indexWithDup] = valuesWithoutDuplicates[indexWithoutDup];
          break;
        }
      }
    }

    return valuesWithDuplicates;
  }
}

// lib/redstone-oracles-monorepo/packages/on-chain-relayer/contracts/core/RedstoneAdapterBase.sol

/**
 * @title Core logic of Redstone Adapter Contract
 * @author The Redstone Oracles team
 * @dev This contract is used to repeatedly push Redstone data to blockchain storage
 * More details here: https://docs.redstone.finance/docs/smart-contract-devs/get-started/redstone-classic
 *
 * Key details about the contract:
 * - Values for data feeds can be updated using the `updateDataFeedsValues` function
 * - All data feeds must be updated within a single call, partial updates are not allowed
 * - There is a configurable minimum interval between updates
 * - Updaters can be restricted by overriding `requireAuthorisedUpdater` function
 * - The contract is designed to force values validation, by default it prevents returning zero values
 * - All data packages in redstone payload must have the same timestamp,
 *    equal to `dataPackagesTimestamp` argument of the `updateDataFeedsValues` function
 * - Block timestamp abstraction - even though we call it blockTimestamp in many places,
 *    it's possible to have a custom logic here, e.g. use block number instead of a timestamp
 */
abstract contract RedstoneAdapterBase is RedstoneConsumerNumericBase, IRedstoneAdapter {
  // We don't use storage variables to avoid potential problems with upgradable contracts
  bytes32 internal constant LATEST_UPDATE_TIMESTAMPS_STORAGE_LOCATION = 0x3d01e4d77237ea0f771f1786da4d4ff757fcba6a92933aa53b1dcef2d6bd6fe2; // keccak256("RedStone.lastUpdateTimestamp");
  uint256 internal constant MIN_INTERVAL_BETWEEN_UPDATES = 3 seconds;
  uint256 internal constant BITS_COUNT_IN_16_BYTES = 128;
  uint256 internal constant MAX_NUMBER_FOR_128_BITS = 0x00000000000000000000000000000000ffffffffffffffffffffffffffffffff;

  error DataTimestampShouldBeNewerThanBefore(
    uint256 receivedDataTimestampMilliseconds,
    uint256 lastDataTimestampMilliseconds
  );

  error MinIntervalBetweenUpdatesHasNotPassedYet(
    uint256 currentBlockTimestamp,
    uint256 lastUpdateTimestamp,
    uint256 minIntervalBetweenUpdates
  );

  error DataPackageTimestampMismatch(uint256 expectedDataTimestamp, uint256 dataPackageTimestamp);

  error DataFeedValueCannotBeZero(bytes32 dataFeedId);

  error DataFeedIdNotFound(bytes32 dataFeedId);

  error DataTimestampIsTooBig(uint256 dataTimestamp);

  error BlockTimestampIsTooBig(uint256 blockTimestamp);

  /**
   * @notice Reverts if the updater is not authorised
   * @dev This function should revert if msg.sender is not allowed to update data feed values
   * @param updater The address of the proposed updater
   */
  function requireAuthorisedUpdater(address updater) public view virtual {
    // By default, anyone can update data feed values, but it can be overridden
  }

  /**
   * @notice Returns identifiers of all data feeds supported by the Adapter contract
   * @dev this function must be implemented in derived contracts
   * @return An array of data feed identifiers
   */
  function getDataFeedIds() public view virtual returns (bytes32[] memory);

  /**
   * @notice Returns the unique index of the given data feed
   * @dev This function can (and should) be overriden to reduce gas
   * costs of other functions
   * @param dataFeedId The data feed identifier
   * @return index The index of the data feed
   */
  function getDataFeedIndex(bytes32 dataFeedId) public view virtual returns (uint256) {
    bytes32[] memory dataFeedIds = getDataFeedIds();
    for (uint256 i = 0; i < dataFeedIds.length;) {
      if (dataFeedIds[i] == dataFeedId) {
        return i;
      }
      unchecked { i++; } // reduces gas costs
    }
    revert DataFeedIdNotFound(dataFeedId);
  }

  /**
   * @notice Updates values of all data feeds supported by the Adapter contract
   * @dev This function requires an attached redstone payload to the transaction calldata.
   * It also requires each data package to have exactly the same timestamp
   * @param dataPackagesTimestamp Timestamp of each signed data package in the redstone payload
   */
  function updateDataFeedsValues(uint256 dataPackagesTimestamp) public virtual {
    requireAuthorisedUpdater(msg.sender);
    _assertMinIntervalBetweenUpdatesPassed();
    validateProposedDataPackagesTimestamp(dataPackagesTimestamp);
    _saveTimestampsOfCurrentUpdate(dataPackagesTimestamp);

    bytes32[] memory dataFeedsIdsArray = getDataFeedIds();

    // It will trigger timestamp validation for each data package
    uint256[] memory oracleValues = getOracleNumericValuesFromTxMsg(dataFeedsIdsArray);

    _validateAndUpdateDataFeedsValues(dataFeedsIdsArray, oracleValues);
  }

  /**
   * @dev Note! This function is not called directly, it's called for each data package    .
   * in redstone payload and just verifies if each data package has the same timestamp
   * as the one that was saved in the storage
   * @param receivedTimestampMilliseconds Timestamp from a data package
   */
  function validateTimestamp(uint256 receivedTimestampMilliseconds) public view virtual override {
    // It means that we are in the special view context and we can skip validation of the
    // timestamp. It can be useful for calling view functions, as they can not modify the contract
    // state to pass the timestamp validation below
    if (msg.sender == address(0)) {
      return;
    }

    uint256 expectedDataPackageTimestamp = getDataTimestampFromLatestUpdate();
    if (receivedTimestampMilliseconds != expectedDataPackageTimestamp) {
      revert DataPackageTimestampMismatch(
        expectedDataPackageTimestamp,
        receivedTimestampMilliseconds
      );
    }
  }

  /**
   * @dev This function should be implemented by the actual contract
   * and should contain the logic of values validation and reporting.
   * Usually, values reporting is based on saving them to the contract storage,
   * e.g. in PriceFeedsAdapter, but some custom implementations (e.g. GMX keeper adapter
   * or Mento Sorted Oracles adapter) may handle values updating in a different way
   * @param dataFeedIdsArray Array of the data feeds identifiers (it will always be all data feed ids)
   * @param values The reported values that should be validated and reported
   */
  function _validateAndUpdateDataFeedsValues(bytes32[] memory dataFeedIdsArray, uint256[] memory values) internal virtual;

  /**
   * @dev This function reverts if not enough time passed since the latest update
   */
  function _assertMinIntervalBetweenUpdatesPassed() private view {
    uint256 currentBlockTimestamp = getBlockTimestamp();
    uint256 blockTimestampFromLatestUpdate = getBlockTimestampFromLatestUpdate();
    uint256 minIntervalBetweenUpdates = getMinIntervalBetweenUpdates();
    if (currentBlockTimestamp < blockTimestampFromLatestUpdate + minIntervalBetweenUpdates) {
      revert MinIntervalBetweenUpdatesHasNotPassedYet(
        currentBlockTimestamp,
        blockTimestampFromLatestUpdate,
        minIntervalBetweenUpdates
      );
    }
  }

  /**
   * @notice Returns minimal required interval (usually in seconds) between subsequent updates
   * @dev You can override this function to change the required interval between udpates.
   * Please do not set it to 0, as it may open many attack vectors
   * @return interval The required interval between updates
   */
  function getMinIntervalBetweenUpdates() public view virtual returns (uint256) {
    return MIN_INTERVAL_BETWEEN_UPDATES;
  }

  /**
   * @notice Reverts if the proposed timestamp of data packages it too old or too new
   * comparing to the block.timestamp. It also ensures that the proposed timestamp is newer
   * Then the one from the previous update
   * @param dataPackagesTimestamp The proposed timestamp (usually in milliseconds)
   */
  function validateProposedDataPackagesTimestamp(uint256 dataPackagesTimestamp) public view {
    _preventUpdateWithOlderDataPackages(dataPackagesTimestamp);
    validateDataPackagesTimestampOnce(dataPackagesTimestamp);
  }

  /**
   * @notice Reverts if the proposed timestamp of data packages it too old or too new
   * comparing to the current block timestamp
   * @param dataPackagesTimestamp The proposed timestamp (usually in milliseconds)
   */
  function validateDataPackagesTimestampOnce(uint256 dataPackagesTimestamp) public view virtual {
    uint256 receivedTimestampSeconds = dataPackagesTimestamp / 1000;

    (uint256 maxDataAheadSeconds, uint256 maxDataDelaySeconds) = getAllowedTimestampDiffsInSeconds();

    uint256 blockTimestamp = getBlockTimestamp();

    if (blockTimestamp < receivedTimestampSeconds) {
      if ((receivedTimestampSeconds - blockTimestamp) > maxDataAheadSeconds) {
        revert RedstoneDefaultsLib.TimestampFromTooLongFuture(receivedTimestampSeconds, blockTimestamp);
      }
    } else if ((blockTimestamp - receivedTimestampSeconds) > maxDataDelaySeconds) {
      revert RedstoneDefaultsLib.TimestampIsTooOld(receivedTimestampSeconds, blockTimestamp);
    }
  }

  /**
   * @dev This function can be overriden, e.g. to use block.number instead of block.timestamp
   * It can be useful in some L2 chains, as sometimes their different blocks can have the same timestamp
   * @return timestamp Timestamp or Block number or any other number that can identify time in the context
   * of the given blockchain
   */
  function getBlockTimestamp() public view virtual returns (uint256) {
    return block.timestamp;
  }

  /**
   * @dev Helpful function for getting values for timestamp validation
   * @return  maxDataAheadSeconds Max allowed number of seconds ahead of block.timrstamp
   * @return  maxDataDelaySeconds Max allowed number of seconds for data delay
   */
  function getAllowedTimestampDiffsInSeconds() public view virtual returns (uint256 maxDataAheadSeconds, uint256 maxDataDelaySeconds) {
    maxDataAheadSeconds = RedstoneDefaultsLib.DEFAULT_MAX_DATA_TIMESTAMP_AHEAD_SECONDS;
    maxDataDelaySeconds = RedstoneDefaultsLib.DEFAULT_MAX_DATA_TIMESTAMP_DELAY_SECONDS;
  }

  /**
   * @dev Reverts if proposed data packages are not newer than the ones used previously
   * @param dataPackagesTimestamp Timestamp od the data packages (usually in milliseconds)
   */
  function _preventUpdateWithOlderDataPackages(uint256 dataPackagesTimestamp) internal view {
    uint256 dataTimestampFromLatestUpdate = getDataTimestampFromLatestUpdate();

    if (dataPackagesTimestamp <= dataTimestampFromLatestUpdate) {
      revert DataTimestampShouldBeNewerThanBefore(
        dataPackagesTimestamp,
        dataTimestampFromLatestUpdate
      );
    }
  }

  /**
   * @notice Returns data timestamp from the latest update
   * @dev It's virtual, because its implementation can sometimes be different
   * (e.g. SinglePriceFeedAdapterWithClearing)
   * @return lastDataTimestamp Timestamp of the latest reported data packages
   */
  function getDataTimestampFromLatestUpdate() public view virtual returns (uint256 lastDataTimestamp) {
    (lastDataTimestamp, ) = getTimestampsFromLatestUpdate();
  }

  /**
   * @notice Returns block timestamp of the latest successful update
   * @return blockTimestamp The block timestamp of the latest successful update
   */
  function getBlockTimestampFromLatestUpdate() public view returns (uint256 blockTimestamp) {
    (, blockTimestamp) = getTimestampsFromLatestUpdate();
  }

  /**
   * @dev Returns 2 timestamps packed into a single uint256 number
   * @return packedTimestamps a single uin256 number with 2 timestamps
   */
  function getPackedTimestampsFromLatestUpdate() public view returns (uint256 packedTimestamps) {
    assembly {
      packedTimestamps := sload(LATEST_UPDATE_TIMESTAMPS_STORAGE_LOCATION)
    }
  }

  /**
   * @notice Returns timestamps of the latest successful update
   * @return dataTimestamp timestamp (usually in milliseconds) from the signed data packages
   * @return blockTimestamp timestamp of the block when the update has happened
   */
  function getTimestampsFromLatestUpdate() public view virtual returns (uint128 dataTimestamp, uint128 blockTimestamp) {
    return _unpackTimestamps(getPackedTimestampsFromLatestUpdate());
  }

  /**
   * @dev A helpful function to unpack 2 timestamps from one uin256 number
   * @param packedTimestamps a single uin256 number
   * @return dataTimestamp fetched from left 128 bits
   * @return blockTimestamp fetched from right 128 bits
   */
  function _unpackTimestamps(uint256 packedTimestamps) internal pure returns (uint128 dataTimestamp, uint128 blockTimestamp) {
    dataTimestamp = uint128(packedTimestamps >> 128); // left 128 bits
    blockTimestamp = uint128(packedTimestamps); // right 128 bits
  }

  /**
   * @dev Logic of saving timestamps of the current update
   * By default, it stores packed timestamps in one storage slot (32 bytes)
   * to minimise gas costs
   * But it can be overriden (e.g. in SinglePriceFeedAdapter)
   * @param   dataPackagesTimestamp  .
   */
  function _saveTimestampsOfCurrentUpdate(uint256 dataPackagesTimestamp) internal virtual {
    uint256 blockTimestamp = getBlockTimestamp();

    if (blockTimestamp > MAX_NUMBER_FOR_128_BITS) {
      revert BlockTimestampIsTooBig(blockTimestamp);
    }

    if (dataPackagesTimestamp > MAX_NUMBER_FOR_128_BITS) {
      revert DataTimestampIsTooBig(dataPackagesTimestamp);
    }

    assembly {
      let timestamps := or(shl(BITS_COUNT_IN_16_BYTES, dataPackagesTimestamp), blockTimestamp)
      sstore(LATEST_UPDATE_TIMESTAMPS_STORAGE_LOCATION, timestamps)
    }
  }

  /**
   * @notice Returns the latest properly reported value of the data feed
   * @param dataFeedId The identifier of the requested data feed
   * @return value The latest value of the given data feed
   */
  function getValueForDataFeed(bytes32 dataFeedId) public view returns (uint256) {
    getDataFeedIndex(dataFeedId); // will revert if data feed id is not supported

    // "unsafe" here means "without validation"
    uint256 valueForDataFeed = getValueForDataFeedUnsafe(dataFeedId);

    validateDataFeedValueOnRead(dataFeedId, valueForDataFeed);
    return valueForDataFeed;
  }

  /**
   * @notice Returns the latest properly reported values for several data feeds
   * @param dataFeedIds The array of identifiers for the requested feeds
   * @return values Values of the requested data feeds in the corresponding order
   */
  function getValuesForDataFeeds(bytes32[] memory dataFeedIds) public view returns (uint256[] memory) {
    uint256[] memory values = getValuesForDataFeedsUnsafe(dataFeedIds);
    for (uint256 i = 0; i < dataFeedIds.length;) {
      bytes32 dataFeedId = dataFeedIds[i];
      getDataFeedIndex(dataFeedId); // will revert if data feed id is not supported
      validateDataFeedValueOnRead(dataFeedId, values[i]);
      unchecked { i++; } // reduces gas costs
    }
    return values;
  }

  /**
   * @dev Reverts if proposed value for the proposed data feed id is invalid
   * Is called on every NOT *unsafe method which reads dataFeed
   * By default, it just checks if the value is not equal to 0, but it can be extended
   * @param dataFeedId The data feed identifier
   * @param valueForDataFeed Proposed value for the data feed
   */
  function validateDataFeedValueOnRead(bytes32 dataFeedId, uint256 valueForDataFeed) public view virtual {
    if (valueForDataFeed == 0) {
      revert DataFeedValueCannotBeZero(dataFeedId);
    }
  }

  /**
   * @dev Reverts if proposed value for the proposed data feed id is invalid
   * Is called on every NOT *unsafe method which writes dataFeed
   * By default, it does nothing
   * @param dataFeedId The data feed identifier
   * @param valueForDataFeed Proposed value for the data feed
   */
  function validateDataFeedValueOnWrite(bytes32 dataFeedId, uint256 valueForDataFeed) public view virtual {
    if (valueForDataFeed == 0) {
      revert DataFeedValueCannotBeZero(dataFeedId);
    }
  }

  /**
   * @dev [HIGH RISK] Returns the latest value for a given data feed without validation
   * Important! Using this function instead of `getValueForDataFeed` may cause
   * significant risk for your smart contracts
   * @param dataFeedId The data feed identifier
   * @return dataFeedValue Unvalidated value of the latest successful update
   */
  function getValueForDataFeedUnsafe(bytes32 dataFeedId) public view virtual returns (uint256);

  /**
   * @notice [HIGH RISK] Returns the latest properly reported values for several data feeds without validation
   * Important! Using this function instead of `getValuesForDataFeeds` may cause
   * significant risk for your smart contracts
   * @param requestedDataFeedIds The array of identifiers for the requested feeds
   * @return values Unvalidated values of the requested data feeds in the corresponding order
   */
  function getValuesForDataFeedsUnsafe(bytes32[] memory requestedDataFeedIds) public view virtual returns (uint256[] memory values) {
    values = new uint256[](requestedDataFeedIds.length);
    for (uint256 i = 0; i < requestedDataFeedIds.length;) {
      values[i] = getValueForDataFeedUnsafe(requestedDataFeedIds[i]);
      unchecked { i++; } // reduces gas costs
    }
    return values;
  }
}

// src/contracts/common/ExecutionBase.sol

contract Base {
    address public immutable ATLAS;
    address public immutable SOURCE;

    constructor(address atlas) {
        ATLAS = atlas;
        SOURCE = address(this);
    }

    // These functions only work inside of the ExecutionEnvironment (mimic)
    // via delegatecall, but can be added to DAppControl as funcs that
    // can be used during DAppControl's delegated funcs

    modifier onlyAtlasEnvironment() {
        _onlyAtlasEnvironment();
        _;
    }

    modifier validSolver(SolverOperation calldata solverOp) {
        address solverContract = solverOp.solver;
        if (solverContract == ATLAS || solverContract == _control() || solverContract == address(this)) {
            revert AtlasErrors.InvalidSolver();
        }
        // Verify that the dAppControl contract matches the solver's expectations
        if (solverOp.control != _control()) {
            revert AtlasErrors.AlteredControl();
        }
        _;
    }

    function _onlyAtlasEnvironment() internal view {
        if (address(this) == SOURCE) {
            revert AtlasErrors.MustBeDelegatecalled();
        }
        if (msg.sender != ATLAS) {
            revert AtlasErrors.OnlyAtlas();
        }
    }

    function _forward(bytes memory data) internal pure returns (bytes memory) {
        return bytes.concat(data, _firstSet(), _secondSet());
    }

    function _firstSet() internal pure returns (bytes memory data) {
        data = abi.encodePacked(
            _bundler(),
            _solverSuccessful(),
            _paymentsSuccessful(),
            _solverIndex(),
            _solverCount(),
            _phase(),
            _solverOutcome(),
            _bidFind(),
            _simulation(),
            _depth() + 1
        );
    }

    function _secondSet() internal pure returns (bytes memory data) {
        data = abi.encodePacked(_user(), _control(), _config());
    }

    /// @notice Extracts and returns the CallConfig of the current DAppControl contract, from calldata.
    /// @return config The CallConfig of the current DAppControl contract, in uint32 form.
    function _config() internal pure returns (uint32 config) {
        assembly {
            config := shr(224, calldataload(sub(calldatasize(), 4)))
        }
    }

    /// @notice Extracts and returns the address of the current DAppControl contract, from calldata.
    /// @return control The address of the current DAppControl contract.
    function _control() internal pure returns (address control) {
        assembly {
            control := shr(96, calldataload(sub(calldatasize(), 24)))
        }
    }

    /// @notice Extracts and returns the address of the user of the current metacall tx, from calldata.
    /// @return user The address of the user of the current metacall tx.
    function _user() internal pure returns (address user) {
        assembly {
            user := shr(96, calldataload(sub(calldatasize(), 44)))
        }
    }

    /// @notice Extracts and returns the call depth within the current metacall tx, from calldata.
    /// @dev The call depth starts at 1 with the first call of each step in the metacall, from Atlas to the Execution
    /// Environment, and is incremented with each call/delegatecall within that step.
    /// @return callDepth The call depth of the current step in the current metacall tx.
    function _depth() internal pure returns (uint8 callDepth) {
        assembly {
            callDepth := shr(248, calldataload(sub(calldatasize(), 45)))
        }
    }

    /// @notice Extracts and returns the boolean indicating whether the current metacall tx is a simulation or not, from
    /// calldata.
    /// @return simulation The boolean indicating whether the current metacall tx is a simulation or not.
    function _simulation() internal pure returns (bool simulation) {
        assembly {
            simulation := shr(248, calldataload(sub(calldatasize(), 46)))
        }
    }

    /// @notice Extracts and returns the boolean indicating whether the current metacall tx uses on-chain bid-finding,
    /// or not, from calldata.
    /// @return bidFind The boolean indicating whether the current metacall tx uses on-chain bid-finding, or not.
    function _bidFind() internal pure returns (bool bidFind) {
        assembly {
            bidFind := shr(248, calldataload(sub(calldatasize(), 47)))
        }
    }

    /// @notice Extracts and returns the solver outcome bitmap in its current status during a metacall tx, from
    /// calldata.
    /// @return solverOutcome The solver outcome bitmap in its current status, in uint24 form.
    function _solverOutcome() internal pure returns (uint24 solverOutcome) {
        assembly {
            solverOutcome := shr(232, calldataload(sub(calldatasize(), 50)))
        }
    }

    /// @notice Extracts and returns the lock state bitmap of the current metacall tx, from calldata.
    /// @return phase The lock state bitmap of the current metacall tx, in uint8 form.
    function _phase() internal pure returns (uint8 phase) {
        assembly {
            phase := shr(248, calldataload(sub(calldatasize(), 51)))
        }
    }

    /// @notice Extracts and returns the number of solverOps in the current metacall tx, from calldata.
    /// @return solverCount The number of solverOps in the current metacall tx.
    function _solverCount() internal pure returns (uint8 solverCount) {
        assembly {
            solverCount := shr(248, calldataload(sub(calldatasize(), 52)))
        }
    }

    /// @notice Extracts and returns the number of executed solverOps in the current metacall tx, from calldata.
    /// @dev Solver index is incremented as Atlas iterates through the solverOps array during execution.
    /// @return solverIndex The count of executed solverOps in the current metacall tx.
    function _solverIndex() internal pure returns (uint8 solverIndex) {
        assembly {
            solverIndex := shr(248, calldataload(sub(calldatasize(), 53)))
        }
    }

    /// @notice Extracts and returns the boolean indicating whether the payments were successful after the allocateValue
    /// step in the current metacall tx, from calldata.
    /// @return paymentsSuccessful The boolean indicating whether the payments were successful after the allocateValue
    /// step in the current metacall tx.
    function _paymentsSuccessful() internal pure returns (bool paymentsSuccessful) {
        assembly {
            paymentsSuccessful := shr(248, calldataload(sub(calldatasize(), 54)))
        }
    }

    /// @notice Extracts and returns the boolean indicating whether the winning solverOp was executed successfully in
    /// the current metacall tx, from calldata.
    /// @return solverSuccessful The boolean indicating whether the winning solverOp was executed successfully in the
    /// current metacall tx.
    function _solverSuccessful() internal pure returns (bool solverSuccessful) {
        assembly {
            solverSuccessful := shr(248, calldataload(sub(calldatasize(), 55)))
        }
    }

    /// @notice Extracts and returns the current value of the bundler of the current metacall tx, from calldata.
    /// @dev The bundler is either the address of the current DAppControl contract (in preOps and userOp steps),
    /// the current solverOp.solver address (during solverOps steps), or the winning solverOp.from address (during
    /// allocateValue step).
    /// @return bundler The current value of the bundler of the current metacall tx.
    function _bundler() internal pure returns (address bundler) {
        assembly {
            bundler := shr(96, calldataload(sub(calldatasize(), 75)))
        }
    }

    /// @notice Returns the address of the currently active Execution Environment, if any.
    /// @return activeEnvironment The address of the currently active Execution Environment.
    function _activeEnvironment() internal view returns (address activeEnvironment) {
        (activeEnvironment,,) = IAtlas(ATLAS).lock();
    }
}

// ExecutionBase is inherited by DAppControl. It inherits Base to as a common root contract shared between
// ExecutionEnvironment and DAppControl. ExecutionBase then adds utility functions which make it easier for custom
// DAppControls to interact with Atlas.
contract ExecutionBase is Base {
    constructor(address atlas) Base(atlas) { }

    /// @notice Deposits local funds from this Execution Environment, to the transient Atlas balance. These funds go
    /// towards the bundler, with any surplus going to the Solver.
    /// @param amt The amount of funds to deposit.
    function _contribute(uint256 amt) internal {
        if (amt > address(this).balance) revert AtlasErrors.InsufficientLocalFunds();

        IAtlas(ATLAS).contribute{ value: amt }();
    }

    /// @notice Borrows funds from the transient Atlas balance that will be repaid by the Solver or this Execution
    /// Environment via `_contribute()`
    /// @param amt The amount of funds to borrow.
    function _borrow(uint256 amt) internal {
        IAtlas(ATLAS).borrow(amt);
    }

    /// @notice Transfers ERC20 tokens from the user of the current metacall tx, via Atlas, to a specified destination.
    /// @dev This will only succeed if Atlas is in a phase included in `SAFE_USER_TRANSFER`. See SafetyBits.sol.
    /// @param token The address of the ERC20 token contract.
    /// @param destination The address to which the tokens will be transferred.
    /// @param amount The amount of tokens to transfer.
    function _transferUserERC20(address token, address destination, uint256 amount) internal {
        IAtlas(ATLAS).transferUserERC20(token, destination, amount, _user(), _control());
    }

    /// @notice Transfers ERC20 tokens from the DApp of the current metacall tx, via Atlas, to a specified destination.
    /// @dev This will only succeed if Atlas is in a phase included in `SAFE_DAPP_TRANSFER`. See SafetyBits.sol.
    /// @param token The address of the ERC20 token contract.
    /// @param destination The address to which the tokens will be transferred.
    /// @param amount The amount of tokens to transfer.
    function _transferDAppERC20(address token, address destination, uint256 amount) internal {
        IAtlas(ATLAS).transferDAppERC20(token, destination, amount, _user(), _control());
    }

    /// @notice Returns a bool indicating whether a source address has approved the Atlas contract to transfer a certain
    /// amount of a certain token, and whether Atlas is in the correct phase to transfer the token. Note: this is just
    /// for convenience - transfers via `_transferDAppERC20()` and `_transferUserERC20()` will independently ensure all
    /// necessary checks are made.
    /// @param token The address of the ERC20 token contract.
    /// @param source The address of the source of the tokens.
    /// @param amount The amount of tokens to transfer.
    /// @param phase The phase of the current metacall tx.
    /// @return available A bool indicating whether a transfer from the source, via Atlas, of the specified amount of
    /// the specified token, will succeed.
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
        uint256 _balance = IERC20(token).balanceOf(source);
        if (_balance < amount) {
            return false;
        }

        uint8 _phase_bitwise = uint8(1 << uint8(phase));
        address _user = _user();
        address _dapp = _control();

        if (source == _user) {
            if (_phase_bitwise & SAFE_USER_TRANSFER == 0) {
                return false;
            }
            if (IERC20(token).allowance(_user, ATLAS) < amount) {
                return false;
            }
            return true;
        }

        if (source == _dapp) {
            if (_phase_bitwise & SAFE_DAPP_TRANSFER == 0) {
                return false;
            }
            if (IERC20(token).allowance(_dapp, ATLAS) < amount) {
                return false;
            }
            return true;
        }

        return false;
    }

    /// @notice Transfers ERC20 tokens from the user of the current metacall tx, via Atlas, to the current
    /// ExecutionEnvironment, and approves the destination address to spend the tokens from the ExecutionEnvironment.
    /// @param token The address of the ERC20 token contract.
    /// @param amount The amount of tokens to transfer and approve.
    /// @param destination The address approved to spend the tokens from the ExecutionEnvironment.
    function _getAndApproveUserERC20(address token, uint256 amount, address destination) internal {
        if (token == address(0) || amount == 0) return;

        // Pull tokens from user to ExecutionEnvironment
        _transferUserERC20(token, address(this), amount);

        // Approve destination to spend the tokens from ExecutionEnvironment
        SafeTransferLib.safeApprove(token, destination, amount);
    }
}

// lib/redstone-oracles-monorepo/packages/on-chain-relayer/contracts/price-feeds/PriceFeedsAdapterBase.sol

/**
 * @title Common logic of the price feeds adapter contracts
 * @author The Redstone Oracles team
 */
abstract contract PriceFeedsAdapterBase is RedstoneAdapterBase, Initializable {

  /**
   * @dev Helpful function for upgradable contracts
   */
  function initialize() public virtual initializer {
    // We don't have storage variables, but we keep this function
    // Because it is used for contract setup in upgradable contracts
  }

  /**
   * @dev This function is virtual and may contain additional logic in the derived contract
   * E.g. it can check if the updating conditions are met (e.g. if at least one
   * value is deviated enough)
   * @param dataFeedIdsArray Array of all data feeds identifiers
   * @param values The reported values that are validated and reported
   */
  function _validateAndUpdateDataFeedsValues(
    bytes32[] memory dataFeedIdsArray,
    uint256[] memory values
  ) internal virtual override {
    for (uint256 i = 0; i < dataFeedIdsArray.length;) {
      _validateAndUpdateDataFeedValue(dataFeedIdsArray[i], values[i]);
      unchecked { i++; } // reduces gas costs
    }
  }

  /**
   * @dev Helpful virtual function for handling value validation and saving in derived
   * Price Feed Adapters contracts 
   * @param dataFeedId The data feed identifier
   * @param dataFeedValue Proposed value for the data feed
   */
  function _validateAndUpdateDataFeedValue(bytes32 dataFeedId, uint256 dataFeedValue) internal virtual;
}

// lib/redstone-oracles-monorepo/packages/on-chain-relayer/contracts/price-feeds/without-rounds/PriceFeedsAdapterWithoutRounds.sol

/**
 * @title Implementation of a price feeds adapter without rounds support
 * @author The Redstone Oracles team
 * @dev This contract is abstract, the following functions should be
 * implemented in the actual contract before deployment:
 * - getDataFeedIds
 * - getUniqueSignersThreshold
 * - getAuthorisedSignerIndex
 * 
 * We also recommend to override `getDataFeedIndex` function with hardcoded
 * values, as it can significantly reduce gas usage
 */
abstract contract PriceFeedsAdapterWithoutRounds is PriceFeedsAdapterBase {
  bytes32 constant VALUES_MAPPING_STORAGE_LOCATION = 0x4dd0c77efa6f6d590c97573d8c70b714546e7311202ff7c11c484cc841d91bfc; // keccak256("RedStone.oracleValuesMapping");

  /**
   * @dev Helpful virtual function for handling value validation and saving
   * @param dataFeedId The data feed identifier
   * @param dataFeedValue Proposed value for the data feed
   */
  function _validateAndUpdateDataFeedValue(bytes32 dataFeedId, uint256 dataFeedValue) internal override virtual {
    validateDataFeedValueOnWrite(dataFeedId, dataFeedValue);
    bytes32 locationInStorage = _getValueLocationInStorage(dataFeedId);
    assembly {
      sstore(locationInStorage, dataFeedValue)
    }
  }

  /**
   * @dev [HIGH RISK] Returns the latest value for a given data feed without validation
   * Important! Using this function instead of `getValueForDataFeed` may cause
   * significant risk for your smart contracts
   * @param dataFeedId The data feed identifier
   * @return dataFeedValue Unvalidated value of the latest successful update
   */
  function getValueForDataFeedUnsafe(bytes32 dataFeedId) public view  virtual override returns (uint256 dataFeedValue) {
    bytes32 locationInStorage = _getValueLocationInStorage(dataFeedId);
    assembly {
      dataFeedValue := sload(locationInStorage)
    }
  }

  /**
   * @dev Helpful function for getting storage location for the requested data feed
   * @param dataFeedId Requested data feed identifier
   * @return locationInStorage
   */
  function _getValueLocationInStorage(bytes32 dataFeedId) private pure returns (bytes32) {
    return keccak256(abi.encode(dataFeedId, VALUES_MAPPING_STORAGE_LOCATION));
  }
}

// lib/redstone-oracles-monorepo/packages/on-chain-relayer/contracts/price-feeds/without-rounds/SinglePriceFeedAdapter.sol

/**
 * @title Price feed adapter for one specific data feed without rounds support
 * @author The Redstone Oracles team
 * @dev This version works only with a single data feed. It's abstract and
 * the following functions should be implemented in the actual contract
 * before deployment:
 * - getDataFeedId
 * - getUniqueSignersThreshold
 * - getAuthorisedSignerIndex
 * 
 * This contract stores the value along with timestamps in a single storage slot
 * 32 bytes = 6 bytes (Data timestamp ) + 6 bytes (Block timestamp) + 20 bytes (Value)
 */
abstract contract SinglePriceFeedAdapter is PriceFeedsAdapterBase {

  bytes32 internal constant DATA_FROM_LATEST_UPDATE_STORAGE_LOCATION = 0x632f4a585e47073d66129e9ebce395c9b39d8a1fc5b15d4d7df2e462fb1fccfa; // keccak256("RedStone.singlePriceFeedAdapter");
  uint256 internal constant MAX_VALUE_WITH_20_BYTES = 0x000000000000000000000000ffffffffffffffffffffffffffffffffffffffff;
  uint256 internal constant BIT_MASK_TO_CLEAR_LAST_20_BYTES = 0xffffffffffffffffffffffff0000000000000000000000000000000000000000;
  uint256 internal constant MAX_NUMBER_FOR_48_BITS = 0x0000000000000000000000000000000000000000000000000000ffffffffffff;

  error DataFeedValueTooBig(uint256 valueForDataFeed);

  /**
   * @notice Returns the only data feed identifer supported by the adapter
   * @dev This function should be overriden in the derived contracts,
   * but `getDataFeedIds` and `getDataFeedIndex` should not (and can not)
   * @return dataFeedId The only data feed identifer supported by the adapter
   */
  function getDataFeedId() public view virtual returns (bytes32);

  /**
   * @notice Returns identifiers of all data feeds supported by the Adapter contract
   * In this case - an array with only one element
   * @return dataFeedIds
   */
  function getDataFeedIds() public view virtual override returns (bytes32[] memory dataFeedIds) {
    dataFeedIds = new bytes32[](1);
    dataFeedIds[0] = getDataFeedId();
  }

  /**
   * @dev Returns 0 if dataFeedId is the one, otherwise reverts
   * @param dataFeedId The identifier of the requested data feed
   */
  function getDataFeedIndex(bytes32 dataFeedId) public virtual view override returns(uint256) {
    if (dataFeedId == getDataFeedId()) {
      return 0;
    } else {
      revert DataFeedIdNotFound(dataFeedId);
    }
  }

  /**
   * @dev Reverts if proposed value for the proposed data feed id is invalid
   * By default, it checks if the value is not equal to 0 and if it fits to 20 bytes
   * Because other 12 bytes are used for storing the packed timestamps
   * @param dataFeedId The data feed identifier
   * @param valueForDataFeed Proposed value for the data feed
   */
  function validateDataFeedValueOnWrite(bytes32 dataFeedId, uint256 valueForDataFeed) public view virtual override {
    super.validateDataFeedValueOnWrite(dataFeedId, valueForDataFeed);
    if (valueForDataFeed > MAX_VALUE_WITH_20_BYTES) {
      revert DataFeedValueTooBig(valueForDataFeed);
    }
  }

  /**
   * @dev [HIGH RISK] Returns the latest value for a given data feed without validation
   * Important! Using this function instead of `getValueForDataFeed` may cause
   * significant risk for your smart contracts
   * @return dataFeedValue Unvalidated value of the latest successful update
   */
  function getValueForDataFeedUnsafe(bytes32) public view virtual override returns (uint256 dataFeedValue) {
    uint160 dataFeedValueCompressed;
    assembly {
      dataFeedValueCompressed := sload(DATA_FROM_LATEST_UPDATE_STORAGE_LOCATION)
    }
    return dataFeedValueCompressed;
  }

  /**
   * @notice Returns timestamps of the latest successful update
   * @dev Timestamps here use only 6 bytes each and are packed together with the value
   * @return dataTimestamp timestamp (usually in milliseconds) from the signed data packages
   * @return blockTimestamp timestamp of the block when the update has happened
   */
  function getTimestampsFromLatestUpdate() public view virtual override returns (uint128 dataTimestamp, uint128 blockTimestamp) {
    uint256 latestUpdateDetails;
    assembly {
      latestUpdateDetails := sload(DATA_FROM_LATEST_UPDATE_STORAGE_LOCATION)
    }
    dataTimestamp = uint128(latestUpdateDetails >> 208); // first 48 bits
    blockTimestamp = uint128((latestUpdateDetails << 48) >> 208); // next 48 bits
  }

  /**
   * @dev Validates and saves the value in the contract storage
   * It uses only 20 right bytes of the corresponding storage slot
   * @param dataFeedId The data feed identifier
   * @param dataFeedValue Proposed value for the data feed
   */
  function _validateAndUpdateDataFeedValue(bytes32 dataFeedId, uint256 dataFeedValue) internal virtual override {
    validateDataFeedValueOnWrite(dataFeedId, dataFeedValue);
    assembly {
      let curValueFromStorage := sload(DATA_FROM_LATEST_UPDATE_STORAGE_LOCATION)
      curValueFromStorage := and(curValueFromStorage, BIT_MASK_TO_CLEAR_LAST_20_BYTES) // clear dataFeedValue bits
      curValueFromStorage := or(curValueFromStorage, dataFeedValue)
      sstore(DATA_FROM_LATEST_UPDATE_STORAGE_LOCATION, curValueFromStorage)
    }
  }

  /**
   * @dev Helpful function that packs and saves timestamps in the 12 left bytes of the
   * storage slot reserved for storing details about the latest update
   * @param dataPackagesTimestamp Timestamp from the signed data packages,
   * extracted from the RedStone payload in calldata
   */
  function _saveTimestampsOfCurrentUpdate(uint256 dataPackagesTimestamp) internal virtual override {
    uint256 blockTimestamp = getBlockTimestamp();

    if (dataPackagesTimestamp > MAX_NUMBER_FOR_48_BITS) {
      revert DataTimestampIsTooBig(dataPackagesTimestamp);
    }

    if (blockTimestamp > MAX_NUMBER_FOR_48_BITS) {
      revert BlockTimestampIsTooBig(blockTimestamp);
    }

    uint256 timestampsPacked = dataPackagesTimestamp << 208; // 48 first bits for dataPackagesTimestamp
    timestampsPacked |= (blockTimestamp << 160); // 48 next bits for blockTimestamp
    assembly {
      let latestUpdateDetails := sload(DATA_FROM_LATEST_UPDATE_STORAGE_LOCATION)
      latestUpdateDetails := and(latestUpdateDetails, MAX_VALUE_WITH_20_BYTES) // clear timestamp bits
      sstore(DATA_FROM_LATEST_UPDATE_STORAGE_LOCATION, or(latestUpdateDetails, timestampsPacked))
    }
  }
}

// src/contracts/dapp/DAppControl.sol

/// @title DAppControl
/// @author FastLane Labs
/// @notice DAppControl is the base contract which should be inherited by any Atlas dApps.
/// @notice Storage variables (except immutable) will be defaulted if accessed by delegatecalls.
/// @notice If an extension DAppControl uses storage variables, those should not be accessed by delegatecalls.
abstract contract DAppControl is DAppControlTemplate, ExecutionBase {
    using CallBits for uint32;

    uint32 public immutable CALL_CONFIG;
    address public immutable CONTROL;
    address public immutable ATLAS_VERIFICATION;

    address public governance;
    address public pendingGovernance;

    constructor(address atlas, address initialGovernance, CallConfig memory callConfig) ExecutionBase(atlas) {
        ATLAS_VERIFICATION = IAtlas(atlas).VERIFICATION();
        CALL_CONFIG = CallBits.encodeCallConfig(callConfig);
        _validateCallConfig(CALL_CONFIG);
        CONTROL = address(this);

        governance = initialGovernance;
    }

    // Safety and support functions and modifiers that make the relationship between dApp
    // and FastLane's backend trustless.

    // Modifiers
    modifier validControl() {
        if (CONTROL != _control()) revert AtlasErrors.InvalidControl();
        _;
    }

    // Reverts if phase in Atlas is not the specified phase.
    // This is required to prevent reentrancy in hooks from other hooks in different phases.
    modifier onlyPhase(ExecutionPhase phase) {
        (,, uint8 atlasPhase) = IAtlas(ATLAS).lock();
        if (atlasPhase != uint8(phase)) revert AtlasErrors.WrongPhase();
        _;
    }

    modifier mustBeCalled() {
        if (address(this) != CONTROL) revert AtlasErrors.NoDelegatecall();
        _;
    }

    /// @notice The preOpsCall hook which may be called before the UserOperation is executed.
    /// @param userOp The UserOperation struct.
    /// @return data Data to be passed to the next call phase.
    function preOpsCall(
        UserOperation calldata userOp
    )
        external
        payable
        validControl
        onlyAtlasEnvironment
        onlyPhase(ExecutionPhase.PreOps)
        returns (bytes memory)
    {
        // check if dapps using this DApontrol can handle the userOp
        _checkUserOperation(userOp);

        return _preOpsCall(userOp);
    }

    /// @notice The preSolverCall hook which may be called before the SolverOperation is executed.
    /// @dev Should revert if any DApp-specific checks fail to indicate non-fulfillment.
    /// @param solverOp The SolverOperation to be executed after this hook has been called.
    /// @param returnData Data returned from the previous call phase.
    function preSolverCall(
        SolverOperation calldata solverOp,
        bytes calldata returnData
    )
        external
        payable
        validControl
        validSolver(solverOp)
        onlyAtlasEnvironment
        onlyPhase(ExecutionPhase.PreSolver)
    {
        _preSolverCall(solverOp, returnData);
    }

    /// @notice The postSolverCall hook which may be called after the SolverOperation has been executed.
    /// @dev Should revert if any DApp-specific checks fail to indicate non-fulfillment.
    /// @param solverOp The SolverOperation struct that was executed just before this hook was called.
    /// @param returnData Data returned from the previous call phase.
    function postSolverCall(
        SolverOperation calldata solverOp,
        bytes calldata returnData
    )
        external
        payable
        validControl
        validSolver(solverOp)
        onlyAtlasEnvironment
        onlyPhase(ExecutionPhase.PostSolver)
    {
        _postSolverCall(solverOp, returnData);
    }

    /// @notice The allocateValueCall hook which is called after a successful SolverOperation.
    /// @param bidToken The address of the token used for the winning SolverOperation's bid.
    /// @param bidAmount The winning bid amount.
    /// @param data Data returned from the previous call phase.
    function allocateValueCall(
        address bidToken,
        uint256 bidAmount,
        bytes calldata data
    )
        external
        validControl
        onlyAtlasEnvironment
        onlyPhase(ExecutionPhase.AllocateValue)
    {
        _allocateValueCall(bidToken, bidAmount, data);
    }

    /// @notice The postOpsCall hook which may be called as the last phase of a `metacall` transaction.
    /// @dev Should revert if any DApp-specific checks fail.
    /// @param solved Boolean indicating whether a winning SolverOperation was executed successfully.
    /// @param data Data returned from the previous call phase.
    function postOpsCall(
        bool solved,
        bytes calldata data
    )
        external
        payable
        validControl
        onlyAtlasEnvironment
        onlyPhase(ExecutionPhase.PostOps)
    {
        _postOpsCall(solved, data);
    }

    function userDelegated() external view returns (bool delegated) {
        delegated = CALL_CONFIG.needsDelegateUser();
    }

    function requireSequentialUserNonces() external view returns (bool isSequential) {
        isSequential = CALL_CONFIG.needsSequentialUserNonces();
    }

    function requireSequentialDAppNonces() external view returns (bool isSequential) {
        isSequential = CALL_CONFIG.needsSequentialDAppNonces();
    }

    /// @notice Returns the DAppConfig struct of this DAppControl contract.
    /// @param userOp The UserOperation struct.
    /// @return dConfig The DAppConfig struct of this DAppControl contract.
    function getDAppConfig(
        UserOperation calldata userOp
    )
        external
        view
        mustBeCalled
        returns (DAppConfig memory dConfig)
    {
        dConfig = DAppConfig({
            to: address(this),
            callConfig: CALL_CONFIG,
            bidToken: getBidFormat(userOp),
            solverGasLimit: getSolverGasLimit()
        });
    }

    /// @notice Returns the CallConfig struct of this DAppControl contract.
    /// @return The CallConfig struct of this DAppControl contract.
    function getCallConfig() external view returns (CallConfig memory) {
        return _getCallConfig();
    }

    function _getCallConfig() internal view returns (CallConfig memory) {
        return CALL_CONFIG.decodeCallConfig();
    }

    /// @notice Returns the current governance address of this DAppControl contract.
    /// @return The address of the current governance account of this DAppControl contract.
    function getDAppSignatory() external view mustBeCalled returns (address) {
        return governance;
    }

    function _validateCallConfig(uint32 callConfig) internal view {
        ValidCallsResult result = IAtlasVerification(ATLAS_VERIFICATION).verifyCallConfig(callConfig);

        if (result == ValidCallsResult.InvalidCallConfig) {
            revert AtlasErrors.BothPreOpsAndUserReturnDataCannotBeTracked();
        }
        if (result == ValidCallsResult.BothUserAndDAppNoncesCannotBeSequential) {
            revert AtlasErrors.BothUserAndDAppNoncesCannotBeSequential();
        }
        if (result == ValidCallsResult.InvertBidValueCannotBeExPostBids) {
            revert AtlasErrors.InvertBidValueCannotBeExPostBids();
        }
    }

    /// @notice Starts the transfer of governance to a new address. Only callable by the current governance address.
    /// @param newGovernance The address of the new governance.
    function transferGovernance(address newGovernance) external mustBeCalled {
        if (msg.sender != governance) {
            revert AtlasErrors.OnlyGovernance();
        }
        pendingGovernance = newGovernance;
        emit AtlasEvents.GovernanceTransferStarted(governance, newGovernance);
    }

    /// @notice Accepts the transfer of governance to a new address. Only callable by the new governance address.
    function acceptGovernance() external mustBeCalled {
        address newGovernance = pendingGovernance;
        if (msg.sender != newGovernance) {
            revert AtlasErrors.Unauthorized();
        }

        address prevGovernance = governance;
        governance = newGovernance;
        delete pendingGovernance;

        IAtlasVerification(ATLAS_VERIFICATION).changeDAppGovernance(prevGovernance, newGovernance);

        emit AtlasEvents.GovernanceTransferred(prevGovernance, newGovernance);
    }
}

// lib/redstone-oracles-monorepo/packages/on-chain-relayer/contracts/price-feeds/without-rounds/MergedSinglePriceFeedAdapterWithoutRounds.sol

abstract contract MergedSinglePriceFeedAdapterWithoutRounds is
  MergedPriceFeedAdapterCommon,
  SinglePriceFeedAdapter,
  PriceFeedWithoutRounds
{

  function getDataFeedId() public view virtual override(SinglePriceFeedAdapter, PriceFeedBase) returns (bytes32);

  function initialize() public override(PriceFeedBase, PriceFeedsAdapterBase) initializer {
    // We don't have storage variables, but we keep this function
    // Because it is used for contract setup in upgradable contracts
  }

  function getPriceFeedAdapter() public view virtual override(MergedPriceFeedAdapterCommon, PriceFeedBase) returns (IRedstoneAdapter) {
    return super.getPriceFeedAdapter();
  }

  function _emitEventAfterSingleValueUpdate(uint256 newValue) internal virtual {
    emit AnswerUpdated(SafeCast.toInt256(newValue), latestRound(), block.timestamp);
  }

  function _validateAndUpdateDataFeedsValues(
    bytes32[] memory dataFeedIdsArray,
    uint256[] memory values
  ) internal virtual override {
    if (dataFeedIdsArray.length != 1 || values.length != 1) {
      revert CannotUpdateMoreThanOneDataFeed();
    }
    _validateAndUpdateDataFeedValue(dataFeedIdsArray[0], values[0]);
    _emitEventAfterSingleValueUpdate(values[0]);
  }
}

// src/contracts/examples/redstone-oev/RedstoneDAppControl.sol

contract RedstoneDAppControl is DAppControl {
    error InvalidBaseFeed();
    error InvalidRedstoneAdapter();
    error FailedToAllocateOEV();
    error OnlyGovernance();

    uint256 private bundlerOEVPercent = 5;

    event NewRedstoneAtlasAdapterCreated(address indexed wrapper, address indexed owner, address indexed baseFeed);

    mapping(address redstoneAtlasAdapter => bool isAdapter) public isRedstoneAdapter;

    constructor(
        address _atlas
    )
        DAppControl(
            _atlas,
            msg.sender,
            CallConfig({
                userNoncesSequential: false,
                dappNoncesSequential: false,
                requirePreOps: false,
                trackPreOpsReturnData: false,
                trackUserReturnData: true,
                delegateUser: false,
                requirePreSolver: false,
                requirePostSolver: false,
                requirePostOps: false,
                zeroSolvers: true, // oracle updates can be made without solvers and no OEV
                reuseUserOp: false,
                userAuctioneer: true,
                solverAuctioneer: false,
                unknownAuctioneer: false,
                verifyCallChainHash: true,
                forwardReturnData: false,
                requireFulfillment: false, // Update oracle even if all solvers fail
                trustedOpHash: false,
                invertBidValue: false,
                exPostBids: false,
                allowAllocateValueFailure: true // oracle updates should go through even if OEV allocation fails
             })
        )
    { }

    function setBundlerOEVPercent(uint256 _percent) external onlyGov {
        bundlerOEVPercent = _percent;
    }

    function _onlyGov() internal view {
        if (msg.sender != governance) revert OnlyGovernance();
    }

    modifier onlyGov() {
        _onlyGov();
        _;
    }

    // ---------------------------------------------------- //
    //                  Atlas Hook Overrides                //
    // ---------------------------------------------------- //

    function _allocateValueCall(address, uint256 bidAmount, bytes calldata data) internal virtual override {
        uint256 oevForBundler = bidAmount * bundlerOEVPercent / 100;
        uint256 oevForSolver = bidAmount - oevForBundler;

        address adapter = abi.decode(data, (address));
        if (!RedstoneDAppControl(_control()).isRedstoneAdapter(adapter)) {
            revert InvalidRedstoneAdapter();
        }
        (bool success,) = adapter.call{ value: oevForSolver }("");
        if (!success) revert FailedToAllocateOEV();

        SafeTransferLib.safeTransferETH(_bundler(), oevForBundler);
    }

    // NOTE: Functions below are not delegatecalled

    // ---------------------------------------------------- //
    //                    View Functions                    //
    // ---------------------------------------------------- //

    function getBidFormat(UserOperation calldata) public pure override returns (address bidToken) {
        return address(0); // ETH is bid token
    }

    function getBidValue(SolverOperation calldata solverOp) public pure override returns (uint256) {
        return solverOp.bidAmount;
    }

    // ---------------------------------------------------- //
    //                   AtlasAdapterFactory                //
    // ---------------------------------------------------- //
    function createNewAtlasAdapter(address baseFeed) external returns (address) {
        if (IFeed(baseFeed).latestAnswer() == 0) revert InvalidBaseFeed();
        address adapter = address(new RedstoneAdapterAtlasWrapper(ATLAS, msg.sender, baseFeed));
        isRedstoneAdapter[adapter] = true;
        emit NewRedstoneAtlasAdapterCreated(adapter, msg.sender, baseFeed);
        return adapter;
    }
}

// src/contracts/examples/redstone-oev/RedstoneAdapterAtlasWrapper.sol

interface IAdapterWithRounds {
    function getDataFeedIds() external view returns (bytes32[] memory);
    function getValueForDataFeed(bytes32 dataFeedId) external view returns (uint256);
    function getTimestampsFromLatestUpdate() external view returns (uint128 dataTimestamp, uint128 blockTimestamp);
    function getRoundDataFromAdapter(bytes32, uint256) external view returns (uint256, uint128, uint128);
}

interface IFeed {
    function getPriceFeedAdapter() external view returns (IRedstoneAdapter);
    function getDataFeedId() external view returns (bytes32);
    function latestAnswer() external view returns (int256);
    function latestRoundData() external view returns (uint80, int256, uint256, uint256, uint80);
    function latestRound() external view returns (uint80);
    function getRoundData(uint80) external view returns (uint80, int256, uint256, uint256, uint80);
}

contract RedstoneAdapterAtlasWrapper is Ownable, MergedSinglePriceFeedAdapterWithoutRounds {
    address public immutable ATLAS;
    address public immutable DAPP_CONTROL;

    address public immutable BASE_ADAPTER;
    address public immutable BASE_FEED;

    uint256 public constant MAX_HISTORICAL_FETCH_ITERATIONS = 5;

    address[] public authorisedSigners;
    address[] public authorisedUpdaters;

    uint256 public BASE_FEED_DELAY = 4; //seconds

    error BaseAdapterHasNoDataFeed();
    error InvalidAuthorisedSigner();
    error InvalidUpdater();
    error BaseAdapterDoesNotSupportHistoricalData();
    error CannotFetchHistoricalData();

    constructor(address atlas, address _owner, address _baseFeed) {
        uint80 latestRound = IFeed(_baseFeed).latestRound();
        // check to see if earlier rounds are supported
        // this will revert if the base adapter does not support earlier rounds(historical data)
        IFeed(_baseFeed).getRoundData(latestRound - 1);

        ATLAS = atlas;
        DAPP_CONTROL = msg.sender;
        BASE_FEED = _baseFeed;
        BASE_ADAPTER = address(IFeed(_baseFeed).getPriceFeedAdapter());
        _transferOwnership(_owner);
    }

    function setBaseFeedDelay(uint256 _delay) external onlyOwner {
        BASE_FEED_DELAY = _delay;
    }

    function getAuthorisedSignerIndex(address _receivedSigner) public view virtual override returns (uint8) {
        if (authorisedSigners.length == 0) {
            return 0;
        }
        for (uint8 i = 0; i < authorisedSigners.length; i++) {
            if (authorisedSigners[i] == _receivedSigner) {
                return i;
            }
        }
        revert InvalidAuthorisedSigner();
    }

    function requireAuthorisedUpdater(address updater) public view virtual override {
        if (authorisedUpdaters.length == 0) {
            return;
        }
        for (uint256 i = 0; i < authorisedUpdaters.length; i++) {
            if (authorisedUpdaters[i] == updater) {
                return;
            }
        }
        revert InvalidUpdater();
    }

    function getDataFeedId() public view virtual override returns (bytes32 dataFeedId) {
        return IFeed(BASE_FEED).getDataFeedId();
    }

    function addAuthorisedSigner(address _signer) external onlyOwner {
        authorisedSigners.push(_signer);
    }

    function addUpdater(address updater) external onlyOwner {
        authorisedUpdaters.push(updater);
    }

    function removeUpdater(address updater) external onlyOwner {
        for (uint256 i = 0; i < authorisedUpdaters.length; i++) {
            if (authorisedUpdaters[i] == updater) {
                authorisedUpdaters[i] = authorisedUpdaters[authorisedUpdaters.length - 1];
                authorisedUpdaters.pop();
                break;
            }
        }
    }

    function removeAuthorisedSigner(address _signer) external onlyOwner {
        for (uint256 i = 0; i < authorisedSigners.length; i++) {
            if (authorisedSigners[i] == _signer) {
                authorisedSigners[i] = authorisedSigners[authorisedSigners.length - 1];
                authorisedSigners.pop();
                break;
            }
        }
    }

    function requireMinIntervalBetweenUpdatesPassed() private view {
        uint256 currentBlockTimestamp = getBlockTimestamp();
        uint256 blockTimestampFromLatestUpdate = getBlockTimestampFromLatestUpdate();
        uint256 minIntervalBetweenUpdates = getMinIntervalBetweenUpdates();
        if (currentBlockTimestamp < blockTimestampFromLatestUpdate + minIntervalBetweenUpdates) {
            revert MinIntervalBetweenUpdatesHasNotPassedYet(
                currentBlockTimestamp, blockTimestampFromLatestUpdate, minIntervalBetweenUpdates
            );
        }
    }

    function latestAnswerAndTimestamp() internal view virtual returns (int256, uint256) {
        bytes32 dataFeedId = getDataFeedId();
        (, uint256 atlasLatestBlockTimestamp) = getTimestampsFromLatestUpdate();

        if (atlasLatestBlockTimestamp >= block.timestamp - BASE_FEED_DELAY) {
            uint256 atlasAnswer = getValueForDataFeed(dataFeedId);
            return (int256(atlasAnswer), atlasLatestBlockTimestamp);
        }

        // return the latest base value which was recorded before or = block.timestamp - BASE_FEED_DELAY
        uint80 roundId = IFeed(BASE_FEED).latestRound();
        uint256 numIter;
        for (;;) {
            (uint256 baseValue,, uint128 baseBlockTimestamp) =
                IAdapterWithRounds(BASE_ADAPTER).getRoundDataFromAdapter(dataFeedId, roundId);

            if (baseBlockTimestamp <= block.timestamp - BASE_FEED_DELAY) {
                return (int256(baseValue), uint256(baseBlockTimestamp));
            }

            unchecked {
                numIter++;
                roundId--;
            }

            if (numIter > MAX_HISTORICAL_FETCH_ITERATIONS) {
                break;
            }
        }
        // fallback to base
        (, int256 baseAns,, uint256 baseTimestamp,) = IFeed(BASE_FEED).latestRoundData();
        return (baseAns, baseTimestamp);
    }

    function latestAnswer() public view virtual override returns (int256) {
        (int256 answer,) = latestAnswerAndTimestamp();
        return answer;
    }

    function latestTimestamp() public view virtual returns (uint256) {
        (, uint256 timestamp) = latestAnswerAndTimestamp();
        return timestamp;
    }

    function latestRoundData()
        public
        view
        virtual
        override
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        roundId = latestRound();
        (answer, startedAt) = latestAnswerAndTimestamp();

        // These values are equal after chainlink’s OCR update
        updatedAt = startedAt;

        answeredInRound = roundId;
    }
}

