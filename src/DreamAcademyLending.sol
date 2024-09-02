// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {PriceManager} from "./PriceManager.sol";
import {Vault} from "./Vault.sol";

import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

interface IPriceOracle {
    function getPrice(address token) external view returns (uint256);
    function setPrice(address token, uint256 price) external;
}

interface ILending {
    function initializeLendingProtocol(address usdc) external payable;
    function borrow(address token, uint256 amount) external;
    function repay(address token, uint256 amount) external;
    function liquidate(address borrower, address token, uint256 amount) external;
}

contract DreamAcademyLending is Vault, PriceManager, ILending, Initializable {
    IPriceOracle internal _oracle;
    address internal _usdc;

    address constant NATIVE_ETH = address(0);
    uint256 constant OC_RATE = 175;
    mapping(address => uint256) internal _price;

    struct Deposit {
        uint256 amount;
        uint256 blockNumber;
    }

    struct Balance {
        mapping(address => Deposit) _deposit;
        mapping(address => uint256) locked;
        uint256 borrowed;
    }

    mapping(address => Balance) internal _balances;

    modifier updateBalance(address token, int256 amount) {
        _;
        Deposit storage _deposit = _balances[msg.sender]._deposit[token];
        _deposit.amount = uint256(int256(_deposit.amount) + amount);
    }

    modifier updatePrice(address token) {
        _price[token] = _oracle.getPrice(token);
        _price[NATIVE_ETH] = _oracle.getPrice(NATIVE_ETH);
        _;
    }

    constructor(IPriceOracle oracle, address usdc) {
        _oracle = oracle;
        _usdc = usdc;
    }

    function initializeLendingProtocol(address usdc) external payable override initializer {
        (bool res,) =
            address(this).call{value: msg.value}(abi.encodeWithSelector(Vault.deposit.selector, usdc, msg.value));
        res = res && ERC20(usdc).transferFrom(msg.sender, address(this), msg.value);
        require(res);
    }

    function deposit(address token, uint256 amount) external payable override updateBalance(token, int256(amount)) {
        require(msg.value >= amount || ERC20(token).transferFrom(msg.sender, address(this), amount));
    }

    /// @dev 맡겨둔 ETH를 담보로 USDC를 빌립니다.
    /// OC_RATE%의 과담보율을 적용합니다. 예를 들어, OC_RATE가 1750이라면 1000 USDC를 빌릴 때, 1750 USDC의 가치에 해당하는 ETH를 담보로 제공해야 합니다.
    /// @param amount 빌릴 USDC의 양
    function borrow(address token, uint256 amount) external override updatePrice(token) {
        Balance storage balance = _balances[msg.sender];

        uint256 valueToBorrow = amount * _price[token];
        uint256 valueNeededToBorrow = (valueToBorrow * OC_RATE) / 100;
        require(valueNeededToBorrow <= totalValueOwned());

        balance._deposit[NATIVE_ETH].amount -= valueNeededToBorrow / _price[NATIVE_ETH];

        balance._deposit[token].amount += valueToBorrow / _price[token];
        balance.locked[token] += valueNeededToBorrow - valueToBorrow;
        balance.borrowed += amount;

        require(ERC20(token).transfer(msg.sender, amount));
    }

    event Log(uint256 value);

    function totalValueOwned() internal view returns (uint256 totalValue) {
        totalValue += _balances[msg.sender]._deposit[NATIVE_ETH].amount * _price[NATIVE_ETH];
    }

    // TODO block number를 이용한 이자 계산
    function repay(address usdc, uint256 amount) external override {
        Balance storage balance = _balances[msg.sender];
        balance.borrowed -= amount;
        require(ERC20(usdc).transferFrom(msg.sender, address(this), amount));

        if (balance.borrowed == 0) {
            require(ERC20(usdc).transfer(msg.sender, balance.locked[usdc]));
            balance.locked[usdc] = 0;
        }
    }

    function withdraw(address token, uint256 amount) external override updateBalance(token, -int256(amount)) {
        require(_balances[msg.sender]._deposit[token].amount >= amount);

        if (token == NATIVE_ETH) {
            (bool res,) = msg.sender.call{value: amount}("");
            require(res);
            return;
        }
        require(ERC20(token).transfer(msg.sender, amount));
    }

    function getAccruedSupplyAmount(address usdc) external view override returns (uint256) {
        Deposit storage _deposit = _balances[msg.sender]._deposit[usdc];
        return (_deposit.amount * (block.number - _deposit.blockNumber)) / 100;
    }

    /// @dev can liquidate the whole position when the borrowed amount is less than 100, otherwise only 25% can be liquidated at once.
    function liquidate(address borrower, address usdc, uint256 amount) external override {
        Balance storage balance = _balances[borrower];
        amount = amount < 100 ? Math.min(amount, balance.locked[usdc]) : Math.min(amount, balance.locked[usdc] / 4);

        emit Log(amount);
        emit Log(_price[usdc]);
        emit Log(balance.borrowed);

        if (amount / _price[usdc] == 0) {}
        balance.borrowed -= amount * _price[usdc];

        require(ERC20(usdc).transferFrom(msg.sender, address(this), amount));
        if (balance.borrowed == 0) {
            require(ERC20(usdc).transfer(borrower, balance.locked[usdc] / _price[usdc]));
            balance.locked[usdc] = 0;
        }
    }

    // receive() external payable {}
    // fallback() external payable {}
}
