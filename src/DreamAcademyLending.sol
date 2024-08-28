// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

interface IPriceOracle {
    // price는 해당 토큰의 가치가 아니라,
    function getPrice(string memory symbol) external view returns (uint256);
    function setPrice(address token, uint256 price) external;
}

interface ILending {
    function initializeLendingProtocol(address usdc) external payable;
    function deposit(address token, uint256 amount) external payable;
    function borrow(address token, uint256 amount) external;
    function repay(address token, uint256 amount) external;
    function withdraw(address token, uint256 amount) external;
    function getAccruedSupplyAmount(address token) external view returns (uint256);
    function liquidate(address token, address borrower) external;
}

contract DreamAcademyLending is ILending {
    IPriceOracle internal _oracle;
    address internal _usdc;

    address constant NATIVE_ETH = address(0);
    mapping(address => uint256) internal _price;

    struct Collateral {
        mapping(address => uint256) unlocked;
    }

    mapping(address => Collateral) internal _balances;

    modifier updateBalance(address token, int256 amount) {
        _;
        mapping(address => uint256) storage owned = _balances[msg.sender].unlocked;
        owned[token] = uint256(int256(owned[token]) + amount);
    }

    modifier updatePrice(address token) {
        _price[token] = _oracle.getPrice(ERC20(token).symbol());
        _price[NATIVE_ETH] = _oracle.getPrice("ETH");
        _;
    }

    constructor(IPriceOracle oracle, address usdc) {
        _oracle = oracle;
        _usdc = usdc;
    }

    function initializeLendingProtocol(address usdc) external payable override {
        (bool res,) =
            address(this).call{value: msg.value}(abi.encodeWithSelector(ILending.deposit.selector, usdc, msg.value));
        res = res && ERC20(usdc).transferFrom(msg.sender, address(this), msg.value);
        require(res);
    }

    function deposit(address token, uint256 amount) external payable override updateBalance(token, int256(amount)) {
        if (msg.value >= amount) {
            return;
        }
        require(ERC20(token).transferFrom(msg.sender, address(this), amount));
    }

    /// @dev
    /// Check-Effects-Interactions Pattern
    function borrow(address token, uint256 amount) external override updatePrice(token) {
        mapping(address => uint256) storage owned = _balances[msg.sender].unlocked;

        require(_price[token] * amount <= totalValueOwned());

        owned[token] = (owned[token] * _price[token] - amount * _price[NATIVE_ETH]) / _price[token];

        owned[NATIVE_ETH] -= amount;

        require(ERC20(token).transferFrom(msg.sender, address(this), amount));
    }

    function totalValueOwned() internal view returns (uint256 totalValue) {
        totalValue += _balances[msg.sender].unlocked[NATIVE_ETH] * _price[NATIVE_ETH];
        totalValue += _balances[msg.sender].unlocked[_usdc] * _price[_usdc];
    }

    function repay(address usdc, uint256 amount) external override {}

    function withdraw(address token, uint256 amount) external override updateBalance(token, -int256(amount)) {
        if (token == NATIVE_ETH) {
            (bool res,) = msg.sender.call{value: amount}("");
            require(res);
            return;
        }
        require(ERC20(token).transfer(msg.sender, amount));
    }

    function getAccruedSupplyAmount(address usdc) external view override returns (uint256) {}

    function liquidate(address usdc, address borrower) external override {}

    // receive() external payable {}
    // fallback() external payable {}
}
