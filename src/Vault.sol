// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

interface IVault {
    function deposit(address token, uint256 amount) external payable;
    function withdraw(address token, uint256 amount) external;
}

contract Vault is IVault {
    function deposit(address token, uint256 amount) external payable virtual {}
    function withdraw(address token, uint256 amount) external virtual {}

    function depositUSDC(uint256 amount) internal {}
    function withdrawUSDC(uint256 amount) internal {}
    function getUSDCBalance() internal view returns (uint256) {}

    function depositETH(uint256 amount) internal {}
    function withdrawETH(uint256 amount) internal {}
    function getETHBalance() internal view returns (uint256) {}
}
