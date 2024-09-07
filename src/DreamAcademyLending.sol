// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ReentrancyGuardTransient} from "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";

import {console} from "forge-std/console.sol";

/// @dev Interface for the PriceOracle contract
/// | Function Name | Sighash    | Function Signature        |
/// | ------------- | ---------- | ------------------------- |
/// | getPrice      | 41976e09   | getPrice(address)         |
/// | setPrice      | 00e4768b   | setPrice(address,uint256) |
interface IPriceOracle {
    function getPrice(address token) external view returns (uint256);
    function setPrice(address token, uint256 price) external;
}

interface ILending {
    // immutable
    struct TokenSnapshot {
        uint256 blockNumber;
        address token;
        uint256 price; // price at the blockNumber
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

    // nominal value = price * amount
    function getValue(address token, uint256 amount) internal view returns (uint256) {
        return _oracle.getPrice(token) * amount;
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
        _;
        string memory tokenName = getTokenName(token);
        uint256 value = getValue(token, amount);
        if (_eventType == EventType.DEPOSIT) {
            emit Deposit(msg.sender, block.number, tokenName, value);
        } else if (_eventType == EventType.WITHDRAW) {
            emit Withdraw(msg.sender, block.number, tokenName, value);
        } else if (_eventType == EventType.BORROW) {
            emit Borrow(msg.sender, block.number, tokenName, value);
        } else if (_eventType == EventType.REPAY) {
            emit Repay(msg.sender, block.number, tokenName, value);
        } else if (_eventType == EventType.LIQUIDATE) {
            emit Liquidate(msg.sender, block.number, tokenName, value);
        } else {
            revert("invalid event type");
        }
    }
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
contract DreamAcademyLending is _DreamAcademyLending, ILending, Initializable, ReentrancyGuardTransient {
    // 본 컨트랙트는 계약의 상태와 토큰의 전송만 관리
    // 모든 계산은 calculator에 위임

    uint256 totalSupply;
    uint256 totalBorrow;
    uint256 supplyRate;
    uint256 borrowRate;
    uint256 collateralFactor;

    mapping(address => TokenSnapshot) private _vault;
    mapping(address => TokenSnapshot) private _loan;

    constructor(IPriceOracle priceOracle, address pairToken) _DreamAcademyLending(priceOracle, pairToken) {
        _PAIR = pairToken;
    }

    /// @dev Initialize the lending protocol
    /// This function is restricted to be called only once since the contract is deployed
    /// Get ETH and pair token from the sender and deposit them to the vault
    function initializeLendingProtocol(address pair) external payable initializer {
        uint256 amount = msg.value;
        // assume deposit ETH will succeed without sending any value
        ERC20(pair).transferFrom(msg.sender, address(this), amount);
        // TODO update as if ETH and pair token are deposited to the vault
    }

    function deposit(address token, uint256 amount)
        external
        payable
        override
        nonReentrant
        emitEvent(EventType.DEPOSIT, token, amount)
    {
        if (msg.value > 0 && token == _ETH && amount == msg.value) {
            return;
        } else {
            ERC20(token).transferFrom(msg.sender, address(this), amount);
        }

        // TODO update the vault
    }

    function withdraw(address token, uint256 amount)
        external
        override
        nonReentrant
        emitEvent(EventType.WITHDRAW, token, amount)
    {
        // TODO implement the withdraw function
        // 일단 요청하는대로 무조건 돈을 돌려줄 수 있게 구현
        if (token != _ETH) {
            ERC20(token).transfer(msg.sender, amount);
        } else {
            callWithValueMustSuccess(msg.sender, amount, "");
        }
    }

    function borrow(address token, uint256 amount)
        external
        override
        nonReentrant
        emitEvent(EventType.BORROW, token, amount)
    {
        // TODO implement the borrow function
        // 일단 요청하는대로 무조건 빌릴 수 있게 구현
        if (token != _ETH) {
            ERC20(token).transfer(msg.sender, amount);
        } else {
            callWithValueMustSuccess(msg.sender, amount, "");
        }
    }

    function repay(address token, uint256 amount)
        external
        override
        nonReentrant
        emitEvent(EventType.REPAY, token, amount)
    {
        // TODO implement the repay function
    }

    function liquidate(address borrower, address token, uint256 amount)
        external
        override
        nonReentrant
        emitEvent(EventType.LIQUIDATE, token, amount)
    {
        // TODO implement the liquidate function
        // 일단 무조건 실패하도록 구현
        if (borrower != address(0)) {
            revert("liquidate failed");
        }
    }

    function getAccruedSupplyAmount(address token) external view returns (uint256) {
        // TODO implement the getAccruedSupplyAmount function
    }
}
