// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.27;

import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
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
contract DreamAcademyLending is Initializable, ReentrancyGuardTransient {
    constructor(IPriceOracle oracle, address token) {}

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
}
