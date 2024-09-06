// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

/// @dev Interface for the PriceOracle contract
/// | Function Name | Sighash    | Function Signature        |
/// | ------------- | ---------- | ------------------------- |
/// | getPrice      | 41976e09   | getPrice(address)         |
/// | setPrice      | 00e4768b   | setPrice(address,uint256) |
interface IPriceOracle {
    function getPrice(address token) external view returns (uint256);
    function setPrice(address token, uint256 price) external;
}

contract LendCalculator {
    IPriceOracle private _oracle;

    constructor(IPriceOracle _priceOracle) {
        _oracle = _priceOracle;
    }
}

contract DreamAcademyLending is LendCalculator {
    address private constant _ETH = address(0);
    address private immutable _PAIR;

    constructor(IPriceOracle priceOracle, address pairToken) LendCalculator(priceOracle) {
        _PAIR = pairToken;
    }

    function initializeLendingProtocol(address pair) external payable {
        // TODO implement the lending protocol
    }

    function deposit(address token, uint256 amount) external payable {
        // TODO implement the deposit function
    }

    function withdraw(address token, uint256 amount) external {
        // TODO implement the withdraw function
    }

    function borrow(address token, uint256 amount) external {
        // TODO implement the borrow function
    }

    function repay(uint256 amount) external {
        // TODO implement the repay function
    }

    function liquidate(address borrower) external {
        // TODO implement the liquidate function
    }
    function getAccruedSupplyAmount(address token) external view returns (uint256) {
        // TODO implement the getAccruedSupplyAmount function
    }
}
