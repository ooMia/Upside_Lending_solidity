// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

interface IPriceOracle {
    function getPrice(string memory symbol) external view returns (uint256);

    function setPrice(address token, uint256 price) external;
}

interface ILending {
    function initializeLendingProtocol(address _usdc) external payable;
    function deposit(address _usdc, uint256 _amount) external payable;
    function borrow(address _usdc, uint256 _amount) external;
    function repay(address _usdc, uint256 _amount) external;
    function withdraw(address _usdc, uint256 _amount) external;
    function getAccruedSupplyAmount(address _usdc) external view returns (uint256);
    function liquidate(address _usdc, address _borrower) external;
}

contract DreamAcademyLending is ILending {
    IPriceOracle internal oracle;
    address internal usdc;

    constructor(IPriceOracle _oracle, address _usdc) {
        oracle = _oracle;
        usdc = _usdc;
    }

    function initializeLendingProtocol(address _usdc) external payable override {}

    function deposit(address _usdc, uint256 _amount) external payable override {}

    function borrow(address _usdc, uint256 _amount) external override {}

    function repay(address _usdc, uint256 _amount) external override {}

    function withdraw(address _usdc, uint256 _amount) external override {}

    function getAccruedSupplyAmount(address _usdc) external view override returns (uint256) {}

    function liquidate(address _usdc, address _borrower) external override {}
}
