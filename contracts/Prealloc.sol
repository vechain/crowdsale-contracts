pragma solidity ^0.4.11;

/**
 * @title Prealloc
 * @dev Pre-alloc storage vars, to flatten gas usage in future operations.
 */
library Prealloc {
    struct UINT256 {
        uint256 value_;
    }

    function set(UINT256 storage i, uint256 value) internal {
        i.value_ = ~value;
    }

    function get(UINT256 storage i) internal constant returns (uint256) {
        return ~i.value_;
    }
}
