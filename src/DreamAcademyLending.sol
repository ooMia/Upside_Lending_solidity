// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.27;

import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {ReentrancyGuardTransient} from "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";

import {_Lending} from "./Lending.sol";

import "forge-std/Test.sol";

/// @dev Interface for the PriceOracle contract
/// | Function Name | Sighash    | Function Signature        |
/// | ------------- | ---------- | ------------------------- |
/// | getPrice      | 41976e09   | getPrice(address)         |
/// | setPrice      | 00e4768b   | setPrice(address,uint256) |
interface IPriceOracle {
    function getPrice(address token) external view returns (uint256);
    function setPrice(address token, uint256 price) external;
}

/// @dev Interface for the PriceOracle contract
/// | Function Name             | Sighash    | Function Signature                 |
/// | ------------------------- | ---------- | ---------------------------------- |
/// | initializeLendingProtocol | 8f1e9779   | initializeLendingProtocol(address) |
/// | deposit                   | 47e7ef24   | deposit(address,uint256)           |
/// | withdraw                  | f3fef3a3   | withdraw(address,uint256)          |
/// | borrow                    | 4b8a3529   | borrow(address,uint256)            |
/// | repay                     | 22867d78   | repay(address,uint256)             |
/// | liquidate                 | 26c01303   | liquidate(address,address,uint256) |
/// | getAccruedSupplyAmount    | 53415e44   | getAccruedSupplyAmount(address)    |
contract DreamAcademyLending is _Lending, Initializable, ReentrancyGuardTransient {
    struct Value {
        address token;
        uint256 amount;
        uint256 value;
        uint256 blockNumber;
    }

    struct User {
        Value[] loans;
        Value[] collaterals;
    }

    mapping(address => User) private _USERS;

    constructor(IPriceOracle oracle, address token) _Lending(oracle, token) {}

    function initializeLendingProtocol(address token) external payable initializer {
        uint256 amount = msg.value;
        transferFrom(msg.sender, _THIS, amount, token);
    }

    function getAccruedSupplyAmount(address token) external nonReentrant returns (uint256) {
        // TODO implement
    }

    function deposit(address token, uint256 amount)
        external
        payable
        nonReentrant
        identity(msg.sender, Operation.DEPOSIT)
    {
        if (token == _ETH) {
            require(msg.value >= amount, "deposit|ETH: msg.value < amount");
        } else {
            transferFrom(msg.sender, _THIS, amount);
        }
        _USERS[msg.sender].collaterals.push(createValue(token, amount));
    }

    /// @dev 예금을 인출하는 함수
    function withdraw(address token, uint256 amount) external nonReentrant identity(msg.sender, Operation.WITHDRAW) {
        // use nonReentrant modifier or Check-Effects-Interactions pattern
        if (token == _ETH) {
            transferETH(msg.sender, amount);
        } else {
            transfer(msg.sender, amount, token);
        }
        cancelOutStorage(_USERS[msg.sender].collaterals, getPrice(token) * amount);
    }

    function borrow(address token, uint256 amount) external nonReentrant identity(msg.sender, Operation.BORROW) {
        if (token == _ETH) {
            transferETH(msg.sender, amount);
        } else {
            transfer(msg.sender, amount, token);
        }
        _USERS[msg.sender].loans.push(createValue(token, amount));
    }

    function repay(address token, uint256 amount) external nonReentrant identity(msg.sender, Operation.REPAY) {
        // TODO implement
    }

    function liquidate(address user, address token, uint256 amount)
        external
        nonReentrant
        identity(user, Operation.LIQUIDATE)
    {
        // TODO implement
    }

    // 유저의 대출액을 조회하는 함수
    // 1. deposit 함수를 통해 예금을 예치한 경우, 대출액은 변하지 않아야 한다.
    // 2. withdraw 함수를 통해 예금을 인출한 경우, 대출액은 변하지 않아야 한다.
    // 3. borrow 함수를 통해 대출을 받은 경우, 대출액이 증가되어야 한다.
    // 4. repay 함수를 통해 대출을 상환한 경우, 대출액이 감소되어야 한다.
    // 5. liquidate 함수를 통해 청산된 경우, 대출액이 감소되어야 한다.
    function getTotalBorrowedValue(address user) internal view override returns (uint256) {
        return sumValues(_USERS[user].loans);
    }

    // 유저의 담보액을 조회하는 함수
    // 1. deposit 함수를 통해 예금을 예치한 경우, 담보액이 증가되어야 한다.
    // 2. withdraw 함수를 통해 예금을 인출한 경우, 담보액이 감소되어야 한다.
    // 3. borrow 함수를 통해 대출을 받은 경우, 담보액이 감소되어야 한다.
    // 4. repay 함수를 통해 대출을 상환한 경우, 담보액이 증가되어야 한다.
    // 5. liquidate 함수를 통해 청산된 경우, 담보액이 감소되어야 한다.
    function getTotalCollateralValue(address user) internal view override returns (uint256) {
        return sumValues(_USERS[user].collaterals);
    }

    function getAccruedValue(Value memory v) internal view returns (uint256) {
        // TODO implement interest rate
        return v.amount * getPrice(v.token) * (1 + block.number - v.blockNumber);
    }

    function sumValues(Value[] storage values) internal view returns (uint256 res) {
        for (uint256 i = 0; i < values.length; ++i) {
            res += getAccruedValue(values[i]);
        }
    }

    function createValue(address token, uint256 amount) internal view returns (Value memory) {
        return Value(token, amount, amount * getPrice(token), block.number);
    }

    function cancelOutStorage(Value[] storage targets, uint256 value) internal {
        for (uint256 i = 0; i < targets.length && value > 0; ++i) {
            Value storage t = targets[i];
            uint256 accrued = getAccruedValue(t);
            if (accrued > value) {
                t.amount -= value / getPrice(t.token);
                value = 0;
            } else {
                value -= accrued;
                targets.pop();
            }
        }
    }

    // function popFrom(Value[] storage values) internal returns (Value memory res) {
    //     res = values[values.length - 1];
    //     values.pop();
    // }

    // function subUntil(Value[] storage values, Value memory sub) internal returns (uint256 left) {
    //     left = getAccruedValue(sub);
    //     while (values.length > 0 && left > 0) {
    //         Value storage v = values[values.length - 1];
    //         uint256 accrued = getAccruedValue(v);
    //         if (accrued > left) {
    //             v.amount -= left / getPrice(v.token);
    //             left = 0;
    //         } else {
    //             left -= accrued;
    //             popFrom(values);
    //         }
    //     }
    // }
}
