// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IPriceOracle {
    function getPrice(string memory symbol) external view returns (uint256);
    function setPrice(address token, uint256 price) external;
}

interface ILending {
    function initializeLendingProtocol(address usdc) external payable;
    function deposit(address usdc, uint256 amount) external payable;
    function borrow(address usdc, uint256 amount) external;
    function repay(address usdc, uint256 amount) external;
    function withdraw(address usdc, uint256 amount) external;
    function getAccruedSupplyAmount(address usdc) external view returns (uint256);
    function liquidate(address usdc, address borrower) external;
}

contract DreamAcademyLending is ILending {
    IPriceOracle internal _oracle;
    IERC20 internal _usdc;

    constructor(IPriceOracle oracle, address usdc) {
        _oracle = oracle;
        _usdc = IERC20(usdc);
    }

    function initializeLendingProtocol(address usdc) external payable override {
        // lending.initializeLendingProtocol{value: 1}(address(usdc)); // set reserve ^__^
    }

    function deposit(address usdc, uint256 amount) external payable override {}

    function borrow(address usdc, uint256 amount) external override {}

    function repay(address usdc, uint256 amount) external override {}

    function withdraw(address usdc, uint256 amount) external override {}

    function getAccruedSupplyAmount(address usdc) external view override returns (uint256) {}

    function liquidate(address usdc, address borrower) external override {}
}
