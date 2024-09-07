// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ReentrancyGuardTransient} from "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

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
    uint256 constant LOCKUP_RATE = 75;
    uint256 constant LIQUIDATION_PRICE_LIMIT = 66;
    uint256 constant LIQUIDATION_RATE_PER_ONCE = 25;

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

    function getTotalLoanAmountOf(address borrower) internal view returns (uint256 res) {
        TokenSnapshot[] storage loans = _users[borrower].loan;
        for (uint256 i = 0; i < loans.length; ++i) {
            res += loans[i].amount;
        }
    }

    function getTotalLoanValueOf(address borrower) internal view returns (uint256) {
        return getTotalValue(_users[borrower].loan);
    }

    function getUserTotalCollateralValue() internal view returns (uint256) {
        return getTotalValue(_users[msg.sender].collateral);
    }

    function getPreviousCollateralValueOf(address borrower) internal view returns (uint256 res) {
        TokenSnapshot[] storage collaterals = _users[borrower].collateral;
        for (uint256 i = 0; i < collaterals.length; ++i) {
            res += collaterals[i].value;
        }
    }

    function getTotalCollateralValueOf(address borrower) public view returns (uint256 res) {
        return getTotalValue(_users[borrower].collateral);
    }

    function getUserPreviousCollateralValue() internal view returns (uint256 res) {
        TokenSnapshot[] storage collaterals = _users[msg.sender].collateral;
        for (uint256 i = 0; i < collaterals.length; ++i) {
            res += collaterals[i].value;
        }
    }

    function getTotalValue(TokenSnapshot[] storage snapshots) internal view returns (uint256 res) {
        for (uint256 i = 0; i < snapshots.length; ++i) {
            res += getValue(snapshots[i]);
        }
    }

    function getUserRemainingValue() internal view returns (uint256) {
        return getUserTotalSupplyValue() - getUserTotalLoanValue() - getUserTotalCollateralValue();
    }

    function getRemainingValueOf(address borrower) internal view returns (uint256) {
        return getTotalSupplyValueOf(borrower) - getTotalLoanValueOf(borrower) - getTotalCollateralValueOf(borrower);
    }

    function getTotalSupplyValueOf(address borrower) internal view returns (uint256) {
        return getTotalValue(_users[borrower].vault);
    }

    function getUserWithdrawableValue() internal view returns (uint256) {
        return (getUserTotalSupplyValue() - getUserTotalLoanValue()) / LOCKUP_RATE * 100;
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
        consoleStatus();
        uint256 valueToWithdraw = getValue(token, amount);

        console.log("valueToWithdraw: %d %d", valueToWithdraw / 1 ether, valueToWithdraw % 1 ether);

        uint256 remainingWithdrawableValue = getUserWithdrawableValue();

        console.log(
            "remainingWithdrawableValue: %d %d",
            remainingWithdrawableValue / 1 ether,
            remainingWithdrawableValue % 1 ether
        );
        require(valueToWithdraw <= remainingWithdrawableValue, "withdraw: not enough unlocked value");

        TokenSnapshot[] storage vault = _users[msg.sender].vault;
        {
            uint256 value = valueToWithdraw;
            while (vault.length > 0 && value > 0) {
                TokenSnapshot storage snapshot = vault[vault.length - 1];
                uint256 snapshotValue = getValue(snapshot);
                if (snapshotValue <= value) {
                    value -= snapshotValue;
                    vault.pop();
                } else {
                    snapshot.value -= value;
                    value = 0;
                    snapshot.amount = snapshot.value / getPrice(snapshot.token);
                }
            }
        }

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

        _users[msg.sender].loan.push(createTokenSnapshot(token, amount));
        _users[msg.sender].collateral.push(
            TokenSnapshot({
                blockNumber: block.number,
                token: _ETH,
                amount: getValue(token, getCollateralAmount(amount)) / getPrice(_ETH),
                value: getValue(token, getCollateralAmount(amount))
            })
        );

        if (token != _ETH) {
            ERC20(token).transfer(msg.sender, amount);
        } else {
            callWithValueMustSuccess(msg.sender, amount, "");
        }
        consoleStatus();
    }

    function getCollateralAmount(uint256 amount) internal pure returns (uint256) {
        return amount * COLLATERAL_RATE / 100;
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

    function isCollateralHealthy(address borrower) internal view returns (bool) {
        uint256 prev = getPreviousCollateralValueOf(borrower);
        console.log("prev: %d", prev);
        // console.log("curr_col: %d", getTotalCollateralValueOf(borrower));
        uint256 curr = getTotalCollateralValueOf(borrower);
        console.log("curr: %d", curr);
        return prev * LIQUIDATION_PRICE_LIMIT > curr * 100;
        // && getRemainingValueOf(borrower) >= getTotalLoanValueOf(borrower);
    }

    function liquidate(address borrower, address token, uint256 amount)
        external
        override
        nonReentrant
        emitEvent(EventType.LIQUIDATE, token, amount)
    {
        if (getTotalLoanAmountOf(borrower) > 100) {
            require(
                amount * 100 <= getTotalLoanAmountOf(borrower) * LIQUIDATION_RATE_PER_ONCE, "liquidate: amount too high"
            );
        }
        require(
            getValue(token, amount) <= getTotalCollateralValueOf(borrower), "liquidate: not enough collateral value"
        );
        console.log("amount: %d", amount);

        require(!isCollateralHealthy(borrower), "liquidate: collateral is healthy");
        revert(); // TODO 중단

        // 1. 사용자의 deposit이 반영되어야 함
        // 2. usdc 가격 폭락 시, collateral은 다시 건강해질 수 있음
        // 3. 적절한 liquidate 이후, collateral이 건강해지면 liquidate 불가능

        // console.log("rem_value: %d", getRemainingValueOf(borrower));
        // console.log("req_value: %d", getValue(token, amount));

        //   user total supply value: 0 0
        //   user total loan value: 0 0
        //   user remaining value: 0 0
        //   amount: 500000000000000000000
        //   amount: 500000000000000000000
        //   prev: 2000000000000000000000000000000000000000
        //   curr: 1320000000000000000000000000000000000000
        //   rem_value: 1320000000000000000000000000000000000000
        //   req_value: 500000000000000000000000000000000000000

        //   user total supply value: 0 0
        //   user total loan value: 0 0
        //   user remaining value: 0 0
        //   amount: 500000000000000000000
        //   amount: 500000000000000000000
        //   prev: 2000000000000000000000000000000000000000
        //   curr: 1320000000000000000000000000000000000000
        //   rem_value: 1320000000000000000000000000000000000000
        //   req_value: 500000000000000000000000000000000000000
        // should succeed

        // TODO may need to modify the condition
        // require(
        //     getTotalSupplyValueOf(borrower) - getRemainingValueOf(borrower) < getValue(token, amount),
        //     "liquidate: owner has enough value"
        // );
        // require(getRemainingValueOf(borrower) <= getTotalLoanValueOf(borrower), "liquidate: not liquidatable");

        uint256 presentValue = getValue(token, amount);

        {
            TokenSnapshot[] storage loans = _users[borrower].loan;
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

        // consoleStatus();

        // ERC20(token).transferFrom(msg.sender, address(this), amount);
        // callWithValueMustSuccess(msg.sender, getValue(token, amount) / getPrice(_ETH), "");
    }

    function getAccruedSupplyAmount(address token) external view returns (uint256) {
        return getUserRemainingValue();
    }
}
