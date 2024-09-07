// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {IPriceOracle} from "./DreamAcademyLending.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "forge-std/Test.sol";

interface ILending {
    // immutable
    struct TokenSnapshot {
        uint256 blockNumber;
        address token;
        uint256 amount;
        uint256 value; // price * amount
    }

    function deposit(address token, uint256 amount) external payable;
    function withdraw(address token, uint256 amount) external;
    function borrow(address token, uint256 amount) external;
    function repay(address token, uint256 amount) external;
    function liquidate(address borrower, address token, uint256 amount) external;
    function getAccruedSupplyAmount(address token) external view returns (uint256);
}

contract LendCalculator {
    IPriceOracle private _oracle;

    constructor(IPriceOracle _priceOracle) {
        _oracle = _priceOracle;
    }

    function getPrice(address token) internal view returns (uint256) {
        return _oracle.getPrice(token);
    }

    // nominal value = price * amount
    function getValue(address token, uint256 amount) internal view returns (uint256) {
        return _oracle.getPrice(token) * amount;
    }

    function getValue(ILending.TokenSnapshot storage data) internal view returns (uint256) {
        return getValue(data.token, data.amount) + getAccruedValue(data);
    }

    function getAccruedValue(ILending.TokenSnapshot storage data) internal view returns (uint256) {
        // TODO : implement
        return (block.number - data.blockNumber) > 0 ? 1 : 0;
    }

    // function getValue(address token, uint256 amount, uint256 initialBlock) internal view returns (uint256) {
    //     return _oracle.getPrice(token) * amount * (block.number - initialBlock) * (1 + 1e18) / 1;
    // }
}

abstract contract _DreamAcademyLending is LendCalculator {
    address internal constant _ETH = address(0);
    address internal immutable _PAIR;

    constructor(IPriceOracle oracle, address pair) LendCalculator(oracle) {
        _PAIR = pair;
    }

    enum EventType {
        DEPOSIT,
        WITHDRAW,
        BORROW,
        REPAY,
        LIQUIDATE
    }

    event Deposit(address indexed user, uint256 blockNumber, string token, uint256 value);
    event Withdraw(address indexed user, uint256 blockNumber, string token, uint256 value);
    event Borrow(address indexed user, uint256 blockNumber, string token, uint256 value);
    event Repay(address indexed user, uint256 blockNumber, string token, uint256 value);
    event Liquidate(address indexed borrower, uint256 blockNumber, string token, uint256 value);

    function createTokenSnapshot(address token, uint256 amount) internal view returns (ILending.TokenSnapshot memory) {
        return ILending.TokenSnapshot({
            blockNumber: block.number,
            amount: amount,
            token: token,
            value: getValue(token, amount)
        });
    }

    function getTokenName(address token) private view returns (string memory) {
        if (token == _ETH) {
            return "ETH";
        }
        return ERC20(token).name();
    }

    function callWithValueMustSuccess(address _target, uint256 _value, bytes memory _data) internal {
        console.logBytes(_data);
        bool res;
        (res, _data) = _target.call{value: _value}(_data);
        if (!res) {
            console.logBytes(_data);
            require(res, "callWithValue failed");
        }
    }

    modifier emitEvent(EventType _eventType, address token, uint256 amount) {
        uint256 userNumber = uint160(msg.sender) - uint160(address(0x1336));
        console.log("block #%d user%d ", block.number, uint160(msg.sender) - uint160(address(0x1336)));
        _;
        string memory tokenName = getTokenName(token);
        uint256 value = getValue(token, amount);
        if (_eventType == EventType.DEPOSIT) {
            // emit Deposit(msg.sender, block.number, tokenName, value);
            console.log("Deposit: user%d | %s | %d", userNumber, tokenName, value);
        } else if (_eventType == EventType.WITHDRAW) {
            // emit Withdraw(msg.sender, block.number, tokenName, value);
            console.log("Withdraw: user%d | %s | %d", userNumber, tokenName, value);
        } else if (_eventType == EventType.BORROW) {
            // emit Borrow(msg.sender, block.number, tokenName, value);
            console.log("Borrow: user%d | %s | %d", userNumber, tokenName, value);
        } else if (_eventType == EventType.REPAY) {
            // emit Repay(msg.sender, block.number, tokenName, value);
            console.log("Repay: user%d | %s | %d", userNumber, tokenName, value);
        } else if (_eventType == EventType.LIQUIDATE) {
            // emit Liquidate(msg.sender, block.number, tokenName, value);
            console.log("Liquidate: user%d | %s | %d", userNumber, tokenName, value);
        } else {
            revert("invalid event type");
        }
    }
}
