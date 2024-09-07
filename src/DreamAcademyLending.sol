// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ReentrancyGuardTransient} from "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";

import "forge-std/Test.sol";

import {ILending, _DreamAcademyLending} from "./SubModule.sol";

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
contract DreamAcademyLending is _DreamAcademyLending, ILending, Initializable, ReentrancyGuardTransient {
    // 본 컨트랙트는 계약의 상태와 토큰의 전송만 관리
    // 모든 계산은 calculator에 위임

    uint256 constant COLLATERAL_RATE = 100;

    // immutable
    // struct TokenSnapshot {
    //     uint256 blockNumber;
    //     address token;
    //     uint256 price; // can be 1 if Snapshots combined
    //     uint256 amount;
    //     uint256 value; // price * amount
    // }

    struct UserInfo {
        TokenSnapshot[] vault;
        TokenSnapshot[] loan;
        TokenSnapshot[] collateral;
    }

    mapping(address => UserInfo) private _users;

    constructor(IPriceOracle priceOracle, address pairToken) _DreamAcademyLending(priceOracle, pairToken) {
        _PAIR = pairToken;
    }

    function getUserTotalSupplyValue() internal view returns (uint256) {
        return getTotalValue(_users[msg.sender].vault);
    }

    function getUserTotalLoanValue() internal view returns (uint256) {
        return getTotalValue(_users[msg.sender].loan);
    }

    function getUserTotalCollateralValue() internal view returns (uint256) {
        return getTotalValue(_users[msg.sender].collateral);
    }

    function getTotalValue(TokenSnapshot[] storage snapshots) internal view returns (uint256 res) {
        for (uint256 i = 0; i < snapshots.length; ++i) {
            res += getValue(snapshots[i]);
        }
    }

    function getUserRemainingValue() internal view returns (uint256) {
        return getUserTotalSupplyValue() - getUserTotalLoanValue() - getUserTotalCollateralValue();
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
        require(amount > 0, "deposit: amount == 0");
        if (token == _ETH) {
            require(msg.value >= amount, "deposit: msg.value < amount");
        } else {
            require(ERC20(token).transferFrom(msg.sender, address(this), amount), "deposit: token transfer failed");
        }
        _users[msg.sender].vault.push(createTokenSnapshot(token, amount));
        consoleStatus();
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

    function consoleStatus() internal view {
        console.log(
            "user total supply value: %d %d", getUserTotalSupplyValue() / 1 ether, getUserTotalSupplyValue() % 1 ether
        );
        console.log(
            "user total loan value: %d %d", getUserTotalLoanValue() / 1 ether, getUserTotalLoanValue() % 1 ether
        );
        console.log("user remaining value: %d %d", getUserRemainingValue() / 1 ether, getUserRemainingValue() % 1 ether);
    }

    function borrow(address token, uint256 amount)
        external
        override
        nonReentrant
        emitEvent(EventType.BORROW, token, amount)
    {
        consoleStatus();

        require(
            getUserRemainingValue() >= (100 + COLLATERAL_RATE) * getValue(token, amount) / 100,
            "borrow: not enough remaining value"
        );

        TokenSnapshot memory snapshot = createTokenSnapshot(token, amount);
        _users[msg.sender].loan.push(snapshot);
        _users[msg.sender].collateral.push(snapshot);

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
        require(token != _ETH, "repay: token must be ERC20");

        // TODO implement the repay function
        // 전달된 자산의 현재 가치 확인하고 loan에서 제거
        // loan에서 제거한 만큼 collateral에서도 제거

        uint256 presentValue = getValue(token, amount);
        TokenSnapshot[] storage loans = _users[msg.sender].loan;
        {
            uint256 pv = presentValue;
            while (loans.length > 0 && pv > 0) {
                TokenSnapshot storage loan = loans[loans.length - 1];
                uint256 loanValue = getValue(loan);
                if (loanValue <= pv) {
                    pv -= loanValue;
                    loans.pop();
                } else {
                    loan.value -= pv;
                    pv = 0;
                    loan.amount = loan.value / getPrice(loan.token);
                }
            }
        }
        TokenSnapshot[] storage collateral = _users[msg.sender].collateral;
        {
            // 일단 동일한 방식으로 구현
            uint256 pv = presentValue;
            while (collateral.length > 0 && pv > 0) {
                TokenSnapshot storage coll = collateral[collateral.length - 1];
                uint256 collValue = getValue(coll);
                if (collValue <= pv) {
                    pv -= collValue;
                    collateral.pop();
                } else {
                    coll.value -= pv;
                    pv = 0;
                    coll.amount = coll.value / getPrice(coll.token);
                }
            }
        }
        ERC20(token).transferFrom(msg.sender, address(this), amount);
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
        return getUserRemainingValue();
    }
}
