// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

interface IPriceOracle {
    function getPrice(address token) external view returns (uint256);
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
/// 1 block 당 12sec 고정

contract DreamAcademyLending is ILending {
    IPriceOracle internal _oracle;
    address internal _usdc;

    address constant NATIVE_ETH = address(0);
    uint256 constant OC_RATE = 200;
    mapping(address => uint256) internal _price;

    struct Collateral {
        mapping(address => uint256) owned;
        mapping(address => uint256) locked;
    }

    mapping(address => Collateral) internal _balances;

    modifier updateBalance(address token, int256 amount) {
        _;
        mapping(address => uint256) storage owned = _balances[msg.sender].owned;
        owned[token] = uint256(int256(owned[token]) + amount);
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

    function initializeLendingProtocol(address usdc) external payable override {
        (bool res,) =
            address(this).call{value: msg.value}(abi.encodeWithSelector(ILending.deposit.selector, usdc, msg.value));
        res = res && ERC20(usdc).transferFrom(msg.sender, address(this), msg.value);
        require(res);
    }

    function deposit(address token, uint256 amount) external payable override updateBalance(token, int256(amount)) {
        if (msg.value >= amount) {} else {
            require(ERC20(token).transferFrom(msg.sender, address(this), amount));
        }
    }

    /// @dev 맡겨둔 ETH를 담보로 USDC를 빌립니다.
    /// 200%의 과담보율을 적용합니다. 예를 들어, 1000 USDC를 빌리려면 2000 USDC의 가치에 해당하는 ETH를 담보로 제공해야 합니다.
    /// @param amount 빌릴 USDC의 양
    function borrow(address token, uint256 amount) external override updatePrice(token) {
        Collateral storage balance = _balances[msg.sender];

        uint256 valueToBorrow = amount * _price[token];
        uint256 valueNeededToBorrow = (valueToBorrow * OC_RATE) / 100;
        require(valueNeededToBorrow <= totalValueOwned());

        balance.owned[NATIVE_ETH] -= valueNeededToBorrow / _price[NATIVE_ETH];

        balance.owned[token] += valueToBorrow / _price[token];
        balance.locked[token] += valueNeededToBorrow - valueToBorrow;

        require(ERC20(token).transfer(msg.sender, amount));
    }

    event Log(uint256 value);

    function totalValueOwned() internal view returns (uint256 totalValue) {
        totalValue += _balances[msg.sender].owned[NATIVE_ETH] * _price[NATIVE_ETH];
        // totalValue += _balances[msg.sender].owned[_usdc] * _price[_usdc];
    }

    // TODO block number를 이용한 이자 계산
    function repay(address usdc, uint256 amount) external override {
        _balances[msg.sender].locked[usdc] -= amount;
        _balances[msg.sender].owned[NATIVE_ETH] += amount;
        require(ERC20(usdc).transfer(msg.sender, amount));
    }

    function withdraw(address token, uint256 amount) external override updateBalance(token, -int256(amount)) {
        require(_balances[msg.sender].owned[token] >= amount);

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
