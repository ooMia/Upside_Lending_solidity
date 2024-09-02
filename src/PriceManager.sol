// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {IPriceOracle} from "./DreamAcademyLending.sol";

interface IPriceManager {
    function getAccruedSupplyAmount(address token) external view returns (uint256);
}

contract PriceManager is IPriceManager {
    function getAccruedSupplyAmount(address token) external view virtual returns (uint256) {}
}
