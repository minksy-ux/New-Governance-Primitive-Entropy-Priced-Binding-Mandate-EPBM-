// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IVotes} from "../interfaces/IVotes.sol";

/// @title MockVotes
/// @notice Lightweight IVotes mock for testing with block-based checkpoints.
contract MockVotes is IVotes {
    struct Checkpoint {
        uint256 blockNumber;
        uint256 value;
    }

    mapping(address => uint256) private _balances;
    mapping(address => Checkpoint[]) private _accountCheckpoints;
    Checkpoint[] private _totalSupplyCheckpoints;
    uint256 private _totalSupply;

    function mint(address to, uint256 amount) external {
        _balances[to] += amount;
        _totalSupply  += amount;
        _writeCheckpoint(_accountCheckpoints[to], _balances[to]);
        _writeCheckpoint(_totalSupplyCheckpoints, _totalSupply);
    }

    function burn(address from, uint256 amount) external {
        require(_balances[from] >= amount, "Insufficient balance");
        _balances[from] -= amount;
        _totalSupply    -= amount;
        _writeCheckpoint(_accountCheckpoints[from], _balances[from]);
        _writeCheckpoint(_totalSupplyCheckpoints, _totalSupply);
    }

    /// @dev Returns the balance checkpoint at or before `blockNumber`.
    function getPastVotes(address account, uint256 blockNumber) external view returns (uint256) {
        return _getPastValue(_accountCheckpoints[account], blockNumber);
    }

    /// @dev Returns the total-supply checkpoint at or before `blockNumber`.
    function getPastTotalSupply(uint256 blockNumber) external view returns (uint256) {
        return _getPastValue(_totalSupplyCheckpoints, blockNumber);
    }

    function balanceOf(address account) external view returns (uint256) {
        return _balances[account];
    }

    function totalSupply() external view returns (uint256) {
        return _totalSupply;
    }

    function _writeCheckpoint(Checkpoint[] storage checkpoints, uint256 value) internal {
        uint256 length = checkpoints.length;
        uint256 currentBlock = block.number;

        if (length > 0 && checkpoints[length - 1].blockNumber == currentBlock) {
            checkpoints[length - 1].value = value;
        } else {
            checkpoints.push(Checkpoint({blockNumber: currentBlock, value: value}));
        }
    }

    function _getPastValue(Checkpoint[] storage checkpoints, uint256 blockNumber) internal view returns (uint256) {
        uint256 length = checkpoints.length;
        if (length == 0) return 0;
        if (blockNumber < checkpoints[0].blockNumber) return 0;

        uint256 low = 0;
        uint256 high = length;
        while (low < high) {
            uint256 mid = (low + high) / 2;
            if (checkpoints[mid].blockNumber <= blockNumber) {
                low = mid + 1;
            } else {
                high = mid;
            }
        }

        return checkpoints[low - 1].value;
    }
}
