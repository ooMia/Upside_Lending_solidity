// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.27;

import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {ReentrancyGuardTransient} from "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";

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

abstract contract _Lending {
    using Address for address;

    enum Operation {
        DEPOSIT,
        WITHDRAW,
        BORROW,
        REPAY,
        LIQUIDATE
    }

    // 담보가 감소되는 연산 후에는 반드시 LTV < LT 조건이 만족되어야 한다.
    // LTV (Loan to Value) = (대출액 / 담보액) * 100
    // LT (Liquidation Threshold) = 75
    // 담보액 * LT >= 대출액 * 100을 만족한다면, 언제든 인출이 가능하다.
    // 담보액 * LT < 대출액 * 100 일 경우, 청산이 가능하다.
    // 사용자가 예금을 예치하면 담보액에 반영되
    uint256 internal constant LT = 75;

    address internal immutable _PAIR;
    IPriceOracle internal immutable _ORACLE;
    address internal constant _ETH = address(0);
    address internal immutable _THIS = address(this);

    constructor(IPriceOracle oracle, address pair) {
        _ORACLE = oracle;
        _PAIR = pair;
    }

    modifier identity(address user, Operation op) {
        uint256 preUserBalance =
            op != Operation.LIQUIDATE ? getTotalBalanceOf(user) : getTotalBalanceValueOf(msg.sender);
        uint256 preThisBalance = getTotalBalanceOf(_THIS);
        uint256 preOpLoan = getTotalBorrowedValue(user);
        uint256 preOpCollateral = getTotalCollateralValue(user);
        uint256 preLTV = getLTV1e36(user);

        if (op == Operation.DEPOSIT) {
            // LTV < LT 조건 불필요
        } else if (op == Operation.WITHDRAW) {
            require(isLoanHealthy(user), "identity|WITHDRAW: Loan is unhealthy"); // pessimistic: if needed
        } else if (op == Operation.BORROW) {
            require(isLoanHealthy(user), "identity|BORROW: Loan is unhealthy"); // pessimistic: if needed
        } else if (op == Operation.REPAY) {
            // LTV < LT 조건 불필요
        } else if (op == Operation.LIQUIDATE) {
            // user: borrower
            require(!isLoanHealthy(user), "identity|LIQUIDATE: Loan is healthy");
        }
        _;
        uint256 postUserBalance =
            op != Operation.LIQUIDATE ? getTotalBalanceOf(user) : getTotalBalanceValueOf(msg.sender);
        uint256 postThisBalance = getTotalBalanceOf(_THIS);
        uint256 postOpLoan = getTotalBorrowedValue(user);
        uint256 postOpCollateral = getTotalCollateralValue(user);
        uint256 postLTV = getLTV1e36(user);

        if (op == Operation.DEPOSIT) {
            require(preUserBalance > postUserBalance, "identity|DEPOSIT: User balance not decreased");
            require(preThisBalance < postThisBalance, "identity|DEPOSIT: Contract balance not increased");
            require(preOpLoan == postOpLoan, "identity|DEPOSIT: Loan changed");
            require(preOpCollateral < postOpCollateral, "identity|DEPOSIT: Collateral not increased");
            require(preLTV > postLTV, "identity|DEPOSIT: LTV not decreased");
        } else if (op == Operation.WITHDRAW) {
            require(preUserBalance < postUserBalance, "identity|WITHDRAW: User balance not increased");
            require(preThisBalance > postThisBalance, "identity|WITHDRAW: Contract balance not decreased");
            require(preOpLoan == postOpLoan, "identity|WITHDRAW: Loan changed");
            require(preOpCollateral > postOpCollateral, "identity|WITHDRAW: Collateral not decreased");
            require(preLTV < postLTV, "identity|WITHDRAW: LTV not increased");
            require(isLoanHealthy(user), "identity|WITHDRAW: Loan become unhealthy"); // optimistic
        } else if (op == Operation.BORROW) {
            require(preUserBalance < postUserBalance, "identity|BORROW: User balance not increased");
            require(preThisBalance > postThisBalance, "identity|BORROW: Contract balance not decreased");
            require(preOpLoan < postOpLoan, "identity|BORROW: Loan not increased");
            require(preOpCollateral == postOpCollateral, "identity|WITHDRAW: Collateral changed");
            require(preLTV < postLTV, "identity|BORROW: LTV not increased");
            require(isLoanHealthy(user), "identity|BORROW: Loan become unhealthy"); // optimistic
        } else if (op == Operation.REPAY) {
            // LTV < LT 조건 불필요
            require(preUserBalance > postUserBalance, "identity|REPAY: User balance not decreased");
            require(preThisBalance < postThisBalance, "identity|REPAY: Contract balance not increased");
            require(preOpLoan > postOpLoan, "identity|REPAY: Loan not decreased");
            require(preOpCollateral == postOpCollateral, "identity|REPAY: Collateral changed");
            require(preLTV > postLTV, "identity|REPAY: LTV not decreased");
        } else if (op == Operation.LIQUIDATE) {
            // LTV < LT 조건 불필요
            // user: msg.sender, balanceType: value
            require(preUserBalance >= postUserBalance, "identity|LIQUIDATE: Total value of user balance increased");
            require(preThisBalance <= postThisBalance, "identity|LIQUIDATE: Total value of contract balance decreased");
            require(preOpLoan > postOpLoan, "identity|LIQUIDATE: Loan not decreased");
            require(preOpCollateral > postOpCollateral, "identity|LIQUIDATE: Collateral not decreased");
            require(preLTV > postLTV, "identity|LIQUIDATE: LTV not decreased");
        }
    }

    /// @dev ERC20 토큰과 이더리움의 잔고를 합산하여 반환하는 함수
    /// IERC20(_PAIR).balanceOf(user) + user.balance
    function getTotalBalanceOf(address user) internal view returns (uint256 res) {
        res = abi.decode(
            _PAIR.functionStaticCall(abi.encodeWithSelector(IERC20(_PAIR).balanceOf.selector, user)), (uint256)
        );
        res += user.balance;
    }

    function getTotalBalanceValueOf(address user) internal view returns (uint256 res) {
        res = getPrice(_PAIR)
            * abi.decode(
                _PAIR.functionStaticCall(abi.encodeWithSelector(IERC20(_PAIR).balanceOf.selector, user)), (uint256)
            );
        res += getPrice(_ETH) * user.balance;
    }

    function getPrice(address token) internal view returns (uint256) {
        return abi.decode(
            address(_ORACLE).functionStaticCall(abi.encodeWithSelector(_ORACLE.getPrice.selector, token)), (uint256)
        );
    }

    function getLTV(address user) internal view returns (uint256) {
        return (getTotalBorrowedValue(user) * 100) / getTotalCollateralValue(user);
    }

    function getLTV1e36(address user) internal view returns (uint256) {
        return (getTotalBorrowedValue(user) * 100 * 1e36) / getTotalCollateralValue(user);
    }

    // 유저의 대출액을 조회하는 함수
    // 1. deposit 함수를 통해 예금을 예치한 경우, 대출액은 변하지 않아야 한다.
    // 2. withdraw 함수를 통해 예금을 인출한 경우, 대출액은 변하지 않아야 한다.
    // 3. borrow 함수를 통해 대출을 받은 경우, 대출액이 증가되어야 한다.
    // 4. repay 함수를 통해 대출을 상환한 경우, 대출액이 감소되어야 한다.
    // 5. liquidate 함수를 통해 청산된 경우, 대출액이 감소되어야 한다.
    function getTotalBorrowedValue(address user) internal view virtual returns (uint256);

    // 유저의 담보액을 조회하는 함수
    // 1. deposit 함수를 통해 예금을 예치한 경우, 담보액이 증가되어야 한다.
    // 2. withdraw 함수를 통해 예금을 인출한 경우, 담보액이 감소되어야 한다.
    // 3. borrow 함수를 통해 대출을 받은 경우, 담보액이 감소되어야 한다.
    // 4. repay 함수를 통해 대출을 상환한 경우, 담보액이 증가되어야 한다.
    // 5. liquidate 함수를 통해 청산된 경우, 담보액이 감소되어야 한다.
    function getTotalCollateralValue(address user) internal view virtual returns (uint256);

    /// @dev LTV < LT 조건을 만족하는지 확인하는 함수
    function isLoanHealthy(address user) internal view returns (bool) {
        return getLTV1e36(user) < LT * 1e36;
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
contract DreamAcademyLending is _Lending, Initializable, ReentrancyGuardTransient {
    struct Value {
        address token;
        uint256 amount;
        uint256 blockNumber;
    }

    struct User {
        Value[] loans;
        Value[] collaterals;
    }

    mapping(address => User) private _USERS;

    constructor(IPriceOracle oracle, address token) _Lending(oracle, token) {}

    function initializeLendingProtocol(address token) external payable initializer {
        // TODO implement
    }

    function getAccruedSupplyAmount(address token) external nonReentrant returns (uint256) {
        // TODO implement
    }

    function deposit(address token, uint256 amount) external payable nonReentrant {
        // TODO implement
    }

    function withdraw(address token, uint256 amount) external nonReentrant {
        // TODO implement
    }

    function borrow(address token, uint256 amount) external nonReentrant {
        // TODO implement
    }

    function repay(address token, uint256 amount) external nonReentrant {
        // TODO implement
    }

    function liquidate(address user, address token, uint256 amount) external nonReentrant {
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

    function getAccruedValue(Value storage v) internal view returns (uint256) {
        // TODO implement interest rate
        return v.amount * getPrice(v.token) * (1 + block.number - v.blockNumber);
    }

    function sumValues(Value[] storage values) internal view returns (uint256 res) {
        for (uint256 i = 0; i < values.length; ++i) {
            res += getAccruedValue(values[i]);
        }
    }
}
