// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {EntropyLib} from "../libraries/EntropyLib.sol";

/// @title EntropyLibHarness
/// @notice Exposes EntropyLib internal functions for testing.
contract EntropyLibHarness {
    function normalizedEntropy(
        uint256 yes,
        uint256 no,
        uint256 abstain
    ) external pure returns (uint256) {
        return EntropyLib.normalizedEntropy(yes, no, abstain);
    }
}
