// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title IERC20Minimal
/// @notice Minimal ERC20 interface used for treasury migration.
interface IERC20Minimal {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
}
