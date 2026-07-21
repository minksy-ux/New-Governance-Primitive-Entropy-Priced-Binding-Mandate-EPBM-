// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IVotes} from "./interfaces/IVotes.sol";

/// @title GovernanceToken
/// @notice Transferable token with checkpointed balances for governance snapshots.
contract GovernanceToken is IVotes {
    string public name;
    string public symbol;
    uint8 public constant decimals = 18;

    address public owner;
    address public pendingOwner;

    mapping(address => uint256) private _balances;
    mapping(address => Checkpoint[]) private _accountCheckpoints;
    Checkpoint[] private _totalSupplyCheckpoints;
    uint256 private _totalSupply;

    struct Checkpoint {
        uint32 blockNumber;
        uint224 value;
    }

    event Transfer(address indexed from, address indexed to, uint256 value);
    event OwnershipTransferInitiated(address indexed newOwner);
    event OwnershipTransferred(address indexed newOwner);

    error Unauthorized();
    error ZeroAddress();
    error InsufficientBalance();
    error NoPendingOwner();

    constructor(string memory _name, string memory _symbol, address _owner) {
        if (_owner == address(0)) revert ZeroAddress();
        name = _name;
        symbol = _symbol;
        owner = _owner;
    }

    modifier onlyOwner() {
        if (msg.sender != owner) revert Unauthorized();
        _;
    }

    function initiateOwnershipTransfer(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert ZeroAddress();
        pendingOwner = newOwner;
        emit OwnershipTransferInitiated(newOwner);
    }

    function acceptOwnership() external {
        if (msg.sender != pendingOwner) revert NoPendingOwner();
        owner = pendingOwner;
        pendingOwner = address(0);
        emit OwnershipTransferred(owner);
    }

    function mint(address to, uint256 amount) external onlyOwner {
        if (to == address(0)) revert ZeroAddress();
        _balances[to] += amount;
        _totalSupply += amount;
        _writeCheckpoint(_accountCheckpoints[to], _balances[to]);
        _writeCheckpoint(_totalSupplyCheckpoints, _totalSupply);
        emit Transfer(address(0), to, amount);
    }

    function burn(address from, uint256 amount) external onlyOwner {
        if (_balances[from] < amount) revert InsufficientBalance();
        _balances[from] -= amount;
        _totalSupply -= amount;
        _writeCheckpoint(_accountCheckpoints[from], _balances[from]);
        _writeCheckpoint(_totalSupplyCheckpoints, _totalSupply);
        emit Transfer(from, address(0), amount);
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        if (to == address(0)) revert ZeroAddress();
        if (_balances[msg.sender] < amount) revert InsufficientBalance();

        _balances[msg.sender] -= amount;
        _balances[to] += amount;

        _writeCheckpoint(_accountCheckpoints[msg.sender], _balances[msg.sender]);
        _writeCheckpoint(_accountCheckpoints[to], _balances[to]);
        emit Transfer(msg.sender, to, amount);
        return true;
    }

    function balanceOf(address account) external view returns (uint256) {
        return _balances[account];
    }

    function totalSupply() external view returns (uint256) {
        return _totalSupply;
    }

    function getPastVotes(address account, uint256 blockNumber) external view returns (uint256) {
        return _getPastValue(_accountCheckpoints[account], blockNumber);
    }

    function getPastTotalSupply(uint256 blockNumber) external view returns (uint256) {
        return _getPastValue(_totalSupplyCheckpoints, blockNumber);
    }

    function _writeCheckpoint(Checkpoint[] storage checkpoints, uint256 value) internal {
        uint256 length = checkpoints.length;
        uint32 currentBlock = uint32(block.number);

        if (length > 0 && checkpoints[length - 1].blockNumber == currentBlock) {
            checkpoints[length - 1].value = uint224(value);
        } else {
            checkpoints.push(Checkpoint({blockNumber: currentBlock, value: uint224(value)}));
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