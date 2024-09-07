# 코드 분석

#### [github.com/Entropy1110](https://github.com/Entropy1110/Lending_solidity)

```solidity
contract UpsideAcademyLending {

    event LogUint(uint256 value);

    IPriceOracle public priceOracle;
    ERC20 public asset;
    uint256 public INTEREST_RATE = 1000000138822311089315088974; // ../FindInterestPerBlock.py 뉴턴 랩슨 방식으로 블록 당 이자율 계산
    uint256 constant DECIMAL = 1e27; // for precision
    uint256 private totalBorrowedUSDC; // total borrowed USDC, including interest
    uint256 private totalUSDC; // total USDC supplied
    uint256 private lastInterestUpdatedBlock; // last block number when the interest(totalBorrowedUSDC, User.USDCInterest) was updated
    address[] public suppliedUsers; // list of users who supplied USDC

    struct User {
        uint256 borrowedAsset;
        uint256 depositedAsset;
        uint256 depositedETH;
        uint256 borrwedBlock;
        uint256 USDCInterest;
    }

    mapping(address => User) public userBalances;


    // initialize the lending protocol with the price oracle and the token address
    constructor(IPriceOracle _priceOracle, address token) {
        priceOracle = _priceOracle;
        asset = ERC20(token);
    }

    function initializeLendingProtocol(address _usdc) external payable {
        asset = ERC20(_usdc);
        deposit(_usdc, msg.value);
    }



    // deposited asset + interest 계산
    function getAccruedSupplyAmount(address _asset) public returns (uint256) {
        if (_asset == address(0)) {

            return userBalances[msg.sender].depositedETH;
        } else {
            updateUSDC();
            return userBalances[msg.sender].depositedAsset + userBalances[msg.sender].USDCInterest;
        }
    }


    // deposit asset or ETH
    function deposit(address _asset, uint256 _amount) public payable {
        require(_asset == address(0) || _asset == address(asset), "Invalid asset");

        if (_asset == address(0)) {
            require(msg.value >= _amount, "msg.value should be greater than 0");
            userBalances[msg.sender].depositedETH += _amount;
        } else {
            require(_amount <= asset.allowance(msg.sender, address(this)), "Allowance not set");
            require(asset.balanceOf(msg.sender) >= _amount, "Insufficient balance");
            require(asset.transferFrom(msg.sender, address(this), _amount), "Transfer failed");
            userBalances[msg.sender].depositedAsset += _amount; // add to the user's deposited balance
            totalUSDC += _amount; // add to the total USDC supplied
            suppliedUsers.push(msg.sender); // add the user to the USDC suppliers list
        }
    }

    function withdraw(address _asset, uint256 _amount) external {
        require(_asset == address(0) || _asset == address(asset), "Invalid asset");

        uint256 ethCollateral = userBalances[msg.sender].depositedETH; // user's deposited ETH
        uint256 assetPrice = priceOracle.getPrice(address(asset)); // price of the asset
        uint256 ethPrice = priceOracle.getPrice(address(0)); // price of ETH
        uint256 borrowedPeriod = block.number - userBalances[msg.sender].borrwedBlock; // period since the user borrowed the asset
        uint256 borrowed = userBalances[msg.sender].borrowedAsset * pow(INTEREST_RATE, borrowedPeriod) / DECIMAL; // amount of borrowed asset + interest


        if (_asset == address(0)) { // 이더를 출금한 후 필요한 담보 <= balance가 망가지지 않도록.
            require(ethCollateral >= _amount, "Insufficient deposited balance");
            require(address(this).balance >= _amount, "Insufficient supply");
            require((ethCollateral - _amount) * 75 / 100 >= borrowed * assetPrice / ethPrice, "Insufficient collateral"); // LT = 75%

            userBalances[msg.sender].depositedETH -= _amount;
            payable(msg.sender).transfer(_amount);
        } else {
            uint maxDepositable = getAccruedSupplyAmount(msg.sender); // 이자 한번 더 계산.
            require(maxDepositable >= _amount, "Insufficient deposited balance");
            totalUSDC -= _amount;
            userBalances[msg.sender].depositedAsset -= _amount - userBalances[msg.sender].USDCInterest;
            userBalances[msg.sender].USDCInterest = 0; // withdraw from the interest first

            require(asset.transfer(msg.sender, _amount), "Transfer failed");
        }

    }

    function borrow(address _asset, uint256 _amount) external {
        require(_asset == address(0) || _asset == address(asset), "Invalid asset");
        require(asset.balanceOf(address(this)) >= _amount, "Insufficient supply");

        uint256 ethCollateral = userBalances[msg.sender].depositedETH;
        uint256 assetPrice = priceOracle.getPrice(_asset);
        uint256 ethPrice = priceOracle.getPrice(address(0));
        uint256 collateralValue = ethCollateral * ethPrice;
        uint borrowedPeriod = block.number - userBalances[msg.sender].borrwedBlock;
        userBalances[msg.sender].borrowedAsset = userBalances[msg.sender].borrowedAsset * pow(INTEREST_RATE, borrowedPeriod) / DECIMAL; // 이자 계산
        uint256 maxBorrowable = (collateralValue * 50) / (100 * assetPrice) - userBalances[msg.sender].borrowedAsset; // LTV = 50%

        require(maxBorrowable >= _amount, "Insufficient collateral");

        userBalances[msg.sender].borrwedBlock = block.number; // update the borrowedBlock
        userBalances[msg.sender].borrowedAsset += _amount;
        totalBorrowedUSDC += _amount;

        require(ERC20(_asset).transfer(msg.sender, _amount), "Borrow transfer failed");
    }

    function repay(address token, uint256 _amount) external {

        require(token == address(0) || token == address(asset), "Invalid asset");

        User storage user = userBalances[msg.sender];

        require(_amount <= asset.allowance(msg.sender, address(this)), "Allowance not set");
        require(user.borrowedAsset >= _amount, "Repay amount exceeds debt");

        user.borrowedAsset -= _amount;
        totalBorrowedUSDC -= _amount;

        require(asset.transferFrom(msg.sender, address(this), _amount), "Repay transfer failed");
    }


    function liquidate(address user, address token, uint256 _amount) external {
        uint256 borrowed = userBalances[user].borrowedAsset;
        require(borrowed > 0, "No debt to liquidate");

        uint256 ethCollateral = userBalances[user].depositedETH;
        uint256 ethPrice = priceOracle.getPrice(address(0));
        uint256 assetPrice = priceOracle.getPrice(token);
        uint256 collateralValue = ethCollateral * ethPrice;
        uint256 debtValue = borrowed * assetPrice;

        require(collateralValue * 75 / 100 < debtValue, "Not liquidatable"); // LT = 75%

        if (_amount == borrowed){
            require(borrowed <= 100, "can liquidate the whole position when the borrowed amount is less than 100");
        }else{
            require(borrowed * 25 / 100 >= _amount, "can liquidate 25% of the borrowed amount");
        }

        userBalances[user].borrowedAsset -= _amount;
        totalBorrowedUSDC -= _amount;
        userBalances[user].depositedETH -= _amount * assetPrice / ethPrice;

        require(ERC20(token).transferFrom(msg.sender, address(this), _amount), "Liquidation transfer failed");
    }



    // 대출 이자 분배
    // 총_대출_금액 * 블록_당_이자율 ^ 블록수 - 총_대출_금액 = 이자
    // 이자 분배 -> 유저_당_이자 += 이자 * 각_유저의_예치_금액 / 총_예치_금액
    function updateUSDC() internal {

        uint256 blocksElapsed = block.number - lastInterestUpdatedBlock;
        uint256 accumed;
        uint256 interest;

        accumed = totalBorrowedUSDC * pow(INTEREST_RATE, blocksElapsed) / DECIMAL;

        for (uint i = 0; i < suppliedUsers.length; i++) { // updates all users' interest at once
            User storage user = userBalances[suppliedUsers[i]];
            interest = (accumed - totalBorrowedUSDC) * user.depositedAsset / totalUSDC;
            user.USDCInterest += interest;
        }

        lastInterestUpdatedBlock = block.number;
        totalBorrowedUSDC = accumed;

    }


    function pow(uint256 a, uint256 n) internal pure returns (uint256 z) {
        z = n % 2 != 0 ? a : DECIMAL;

        for (n /= 2; n != 0; n /= 2) {
            a = a ** 2 / DECIMAL;

            if (n % 2 != 0) {
                z = z * a / DECIMAL;
            }
        }
    }

}
```

## setUp

## testDepositEtherWithoutTxValueFails

## testDepositEtherWithInsufficientValueFails

## testDepositEtherWithEqualValueSucceeds

## testDepositUSDCWithInsufficientValueFails

## testDepositUSDCWithEqualValueSucceeds

## testBorrowWithInsufficientCollateralFails

## testBorrowWithInsufficientSupplyFails

## testBorrowWithSufficientCollateralSucceeds

## testBorrowWithSufficientSupplySucceeds

## testBorrowMultipleWithInsufficientCollateralFails

## testBorrowMultipleWithSufficientCollateralSucceeds

## testBorrowWithSufficientCollateralAfterRepaymentSucceeds

## testBorrowWithInSufficientCollateralAfterRepaymentFails

- vm.roll() 수행

## testWithdrawInsufficientBalanceFails

## testWithdrawUnlockedBalanceSucceeds

## testWithdrawMultipleUnlockedBalanceSucceeds

## testWithdrawLockedCollateralAfterBorrowSucceeds

## testWithdrawLockedCollateralAfterInterestAccuredFails

- vm.roll() 수행

## testWithdrawYieldSucceeds

- vm.roll() 수행

## testWithdrawLockedCollateralFails

## testExchangeRateChangeAfterUserBorrows

- `testWithdrawLockedCollateralFails` 테스트에 의존성이 있음.
- vm.roll() 수행

```solidity
    function testExchangeRateChangeAfterUserBorrows() external {
        usdc.transfer(user3, 30000000 ether);
        vm.startPrank(user3);
        usdc.approve(address(lending), type(uint256).max);
        lending.deposit(address(usdc), 30000000 ether);
        vm.stopPrank();

        testWithdrawLockedCollateralFails();

        vm.roll(block.number + (86400 * 1000 / 12));
        vm.prank(user3);
        assertEq(lending.getAccruedSupplyAmount(address(usdc)) / 1e18, 30000792);

        // other lender deposits USDC to our protocol.
        usdc.transfer(user4, 10000000 ether);
        vm.startPrank(user4);
        usdc.approve(address(lending), type(uint256).max);
        lending.deposit(address(usdc), 10000000 ether);
        vm.stopPrank();

        vm.roll(block.number + (86400 * 500 / 12));
        vm.prank(user3);
        uint256 a = lending.getAccruedSupplyAmount(address(usdc));

        vm.prank(user4);
        uint256 b = lending.getAccruedSupplyAmount(address(usdc));

        vm.prank(user1);
        uint256 c = lending.getAccruedSupplyAmount(address(usdc));

        assertEq((a + b + c) / 1e18 - 30000000 - 10000000 - 100000000, 6956);
        assertEq(a / 1e18 - 30000000, 1547);
        assertEq(b / 1e18 - 10000000, 251);
    }
```

## testWithdrawFullUndilutedAfterDepositByOtherAccountSucceeds

## testLiquidationHealthyLoanFails

## testLiquidationUnhealthyLoanSucceeds

## testLiquidationExceedingDebtFails

## testLiquidationHealthyLoanAfterPriorLiquidationFails

## testLiquidationAfterBorrowerCollateralDepositFails

## testLiquidationAfterDebtPriceDropFails

```solidity
// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "src/DreamAcademyLending.sol";

contract CUSDC is ERC20 {
    constructor() ERC20("Circle Stable Coin", "USDC") {
        _mint(msg.sender, type(uint256).max);
    }
}

contract DreamOracle {
    address public operator;
    mapping(address => uint256) prices;

    constructor() {
        operator = msg.sender;
    }

    function getPrice(address token) external view returns (uint256) {
        require(prices[token] != 0, "the price cannot be zero");
        return prices[token];
    }

    function setPrice(address token, uint256 price) external {
        require(msg.sender == operator, "only operator can set the price");
        prices[token] = price;
    }
}

contract Testx is Test {
    DreamOracle dreamOracle;
    DreamAcademyLending lending;
    ERC20 usdc;

    address user1;
    address user2;
    address user3;
    address user4;

    function setUp() external {
        user1 = address(0x1337);
        user2 = address(0x1337 + 1);
        user3 = address(0x1337 + 2);
        user4 = address(0x1337 + 3);
        dreamOracle = new DreamOracle();

        vm.deal(address(this), 10000000 ether);
        usdc = new CUSDC();

        lending = new DreamAcademyLending(IPriceOracle(address(dreamOracle)), address(usdc));
        usdc.approve(address(lending), type(uint256).max);

        lending.initializeLendingProtocol{value: 1}(address(usdc));

        dreamOracle.setPrice(address(0x0), 1339 ether);
        dreamOracle.setPrice(address(usdc), 1 ether);
    }

    function testDepositEtherWithoutTxValueFails() external {
        (bool success,) = address(lending).call{value: 0 ether}(
            abi.encodeWithSelector(DreamAcademyLending.deposit.selector, address(0x0), 1 ether)
        );
        assertFalse(success);
    }

    function testDepositEtherWithInsufficientValueFails() external {
        (bool success,) = address(lending).call{value: 2 ether}(
            abi.encodeWithSelector(DreamAcademyLending.deposit.selector, address(0x0), 3 ether)
        );
        assertFalse(success);
    }

    function testDepositEtherWithEqualValueSucceeds() external {
        (bool success,) = address(lending).call{value: 2 ether}(
            abi.encodeWithSelector(DreamAcademyLending.deposit.selector, address(0x0), 2 ether)
        );
        assertTrue(success);
        assertTrue(address(lending).balance == 2 ether + 1);
    }

    function testDepositUSDCWithInsufficientValueFails() external {
        usdc.approve(address(lending), 1);
        (bool success,) = address(lending).call(
            abi.encodeWithSelector(DreamAcademyLending.deposit.selector, address(usdc), 3000 ether)
        );
        assertFalse(success);
    }

    function testDepositUSDCWithEqualValueSucceeds() external {
        (bool success,) = address(lending).call(
            abi.encodeWithSelector(DreamAcademyLending.deposit.selector, address(usdc), 2000 ether)
        );
        assertTrue(success);
        assertTrue(usdc.balanceOf(address(lending)) == 2000 ether + 1);
    }

    function supplyUSDCDepositUser1() private {
        usdc.transfer(user1, 100000000 ether);
        vm.startPrank(user1);
        usdc.approve(address(lending), type(uint256).max);
        lending.deposit(address(usdc), 100000000 ether);
        vm.stopPrank();
    }

    function supplyEtherDepositUser2() private {
        vm.deal(user2, 100000000 ether);
        vm.prank(user2);
        lending.deposit{value: 100000000 ether}(address(0x00), 100000000 ether);
    }

    function supplySmallEtherDepositUser2() private {
        vm.deal(user2, 100000000 ether);
        vm.startPrank(user2);
        lending.deposit{value: 1 ether}(address(0x00), 1 ether);
        vm.stopPrank();
    }

    function testBorrowWithInsufficientCollateralFails() external {
        supplyUSDCDepositUser1();
        supplySmallEtherDepositUser2();

        dreamOracle.setPrice(address(0x0), 1339 ether);

        vm.startPrank(user2);
        {
            (bool success,) = address(lending).call(
                abi.encodeWithSelector(DreamAcademyLending.borrow.selector, address(usdc), 1000 ether)
            );
            assertFalse(success);
            assertTrue(usdc.balanceOf(user2) == 0 ether);
        }
        vm.stopPrank();
    }

    function testBorrowWithInsufficientSupplyFails() external {
        supplySmallEtherDepositUser2();
        dreamOracle.setPrice(address(0x0), 99999999999 ether);

        vm.startPrank(user2);
        {
            (bool success,) = address(lending).call(
                abi.encodeWithSelector(DreamAcademyLending.borrow.selector, address(usdc), 1000 ether)
            );
            assertFalse(success);
            assertTrue(usdc.balanceOf(user2) == 0 ether);
        }
        vm.stopPrank();
    }

    function testBorrowWithSufficientCollateralSucceeds() external {
        supplyUSDCDepositUser1();
        supplyEtherDepositUser2();

        vm.startPrank(user2);
        {
            lending.borrow(address(usdc), 1000 ether);
            assertTrue(usdc.balanceOf(user2) == 1000 ether);
        }
        vm.stopPrank();
    }

    function testBorrowWithSufficientSupplySucceeds() external {
        supplyUSDCDepositUser1();
        supplyEtherDepositUser2();

        vm.startPrank(user2);
        {
            lending.borrow(address(usdc), 1000 ether);
        }
        vm.stopPrank();
    }

    function testBorrowMultipleWithInsufficientCollateralFails() external {
        supplyUSDCDepositUser1();
        supplySmallEtherDepositUser2();

        dreamOracle.setPrice(address(0x0), 3000 ether);

        vm.startPrank(user2);
        {
            (bool success,) = address(lending).call(
                abi.encodeWithSelector(DreamAcademyLending.borrow.selector, address(usdc), 1000 ether)
            );
            assertTrue(success);
            (success,) = address(lending).call(
                abi.encodeWithSelector(DreamAcademyLending.borrow.selector, address(usdc), 1000 ether)
            );
            assertFalse(success);

            assertTrue(usdc.balanceOf(user2) == 1000 ether);
        }
        vm.stopPrank();
    }

    function testBorrowMultipleWithSufficientCollateralSucceeds() external {
        supplyUSDCDepositUser1();
        supplySmallEtherDepositUser2();

        dreamOracle.setPrice(address(0x0), 4000 ether);

        vm.startPrank(user2);
        {
            (bool success,) = address(lending).call(
                abi.encodeWithSelector(DreamAcademyLending.borrow.selector, address(usdc), 1000 ether)
            );
            assertTrue(success);
            (success,) = address(lending).call(
                abi.encodeWithSelector(DreamAcademyLending.borrow.selector, address(usdc), 1000 ether)
            );
            assertTrue(success);

            assertTrue(usdc.balanceOf(user2) == 2000 ether);
        }
        vm.stopPrank();
    }

    function testBorrowWithSufficientCollateralAfterRepaymentSucceeds() external {
        supplyUSDCDepositUser1();
        supplySmallEtherDepositUser2();

        dreamOracle.setPrice(address(0x0), 4000 ether);

        vm.startPrank(user2);
        {
            (bool success,) = address(lending).call(
                abi.encodeWithSelector(DreamAcademyLending.borrow.selector, address(usdc), 1000 ether)
            );
            assertTrue(success);
            (success,) = address(lending).call(
                abi.encodeWithSelector(DreamAcademyLending.borrow.selector, address(usdc), 1000 ether)
            );
            assertTrue(success);

            assertTrue(usdc.balanceOf(user2) == 2000 ether);

            usdc.approve(address(lending), type(uint256).max);

            (success,) = address(lending).call(
                abi.encodeWithSelector(DreamAcademyLending.repay.selector, address(usdc), 1000 ether)
            );
            assertTrue(success);

            (success,) = address(lending).call(
                abi.encodeWithSelector(DreamAcademyLending.borrow.selector, address(usdc), 1000 ether)
            );
            assertTrue(success);
        }
        vm.stopPrank();
    }

    function testBorrowWithInSufficientCollateralAfterRepaymentFails() external {
        supplyUSDCDepositUser1();
        supplySmallEtherDepositUser2();

        dreamOracle.setPrice(address(0x0), 4000 ether);

        vm.startPrank(user2);
        {
            (bool success,) = address(lending).call(
                abi.encodeWithSelector(DreamAcademyLending.borrow.selector, address(usdc), 1000 ether)
            );
            assertTrue(success);
            (success,) = address(lending).call(
                abi.encodeWithSelector(DreamAcademyLending.borrow.selector, address(usdc), 1000 ether)
            );
            assertTrue(success);

            assertTrue(usdc.balanceOf(user2) == 2000 ether);

            usdc.approve(address(lending), type(uint256).max);

            vm.roll(block.number + 1);

            (success,) = address(lending).call(
                abi.encodeWithSelector(DreamAcademyLending.repay.selector, address(usdc), 1000 ether)
            );
            assertTrue(success);

            (success,) = address(lending).call(
                abi.encodeWithSelector(DreamAcademyLending.borrow.selector, address(usdc), 1000 ether)
            );
            assertFalse(success);

            (success,) = address(lending).call(
                abi.encodeWithSelector(DreamAcademyLending.borrow.selector, address(usdc), 999 ether)
            );
            assertTrue(success);
        }
        vm.stopPrank();
    }

    function testWithdrawInsufficientBalanceFails() external {
        vm.deal(user2, 100000000 ether);
        vm.startPrank(user2);
        {
            lending.deposit{value: 100000000 ether}(address(0x00), 100000000 ether);

            (bool success,) = address(lending).call(
                abi.encodeWithSelector(DreamAcademyLending.withdraw.selector, address(0x0), 100000001 ether)
            );
            assertFalse(success);
        }
        vm.stopPrank();
    }

    function testWithdrawUnlockedBalanceSucceeds() external {
        vm.deal(user2, 100000000 ether);
        vm.startPrank(user2);
        {
            lending.deposit{value: 100000000 ether}(address(0x00), 100000000 ether);

            (bool success,) = address(lending).call(
                abi.encodeWithSelector(DreamAcademyLending.withdraw.selector, address(0x0), 100000001 ether - 1 ether)
            );
            assertTrue(success);
        }
        vm.stopPrank();
    }

    function testWithdrawMultipleUnlockedBalanceSucceeds() external {
        vm.deal(user2, 100000000 ether);
        vm.startPrank(user2);
        {
            lending.deposit{value: 100000000 ether}(address(0x00), 100000000 ether);

            (bool success,) = address(lending).call(
                abi.encodeWithSelector(DreamAcademyLending.withdraw.selector, address(0x0), 100000000 ether / 4)
            );
            assertTrue(success);
            (success,) = address(lending).call(
                abi.encodeWithSelector(DreamAcademyLending.withdraw.selector, address(0x0), 100000000 ether / 4)
            );
            assertTrue(success);
            (success,) = address(lending).call(
                abi.encodeWithSelector(DreamAcademyLending.withdraw.selector, address(0x0), 100000000 ether / 4)
            );
            assertTrue(success);
            (success,) = address(lending).call(
                abi.encodeWithSelector(DreamAcademyLending.withdraw.selector, address(0x0), 100000000 ether / 4)
            );
            assertTrue(success);
        }
        vm.stopPrank();
    }

    function testWithdrawLockedCollateralFails() external {
        supplyUSDCDepositUser1();
        supplySmallEtherDepositUser2();

        dreamOracle.setPrice(address(0x0), 4000 ether);

        vm.startPrank(user2);
        {
            (bool success,) = address(lending).call(
                abi.encodeWithSelector(DreamAcademyLending.borrow.selector, address(usdc), 1000 ether)
            );
            assertTrue(success);

            (success,) = address(lending).call(
                abi.encodeWithSelector(DreamAcademyLending.borrow.selector, address(usdc), 1000 ether)
            );
            assertTrue(success);

            (success,) = address(lending).call(
                abi.encodeWithSelector(DreamAcademyLending.withdraw.selector, address(0x0), 1 ether)
            );
            assertFalse(success);
        }
        vm.stopPrank();
    }

    function testWithdrawLockedCollateralAfterBorrowSucceeds() external {
        supplyUSDCDepositUser1();
        supplySmallEtherDepositUser2();

        dreamOracle.setPrice(address(0x0), 4000 ether); // 4000 usdc

        vm.startPrank(user2);
        {
            (bool success,) = address(lending).call(
                abi.encodeWithSelector(DreamAcademyLending.borrow.selector, address(usdc), 1000 ether)
            );
            assertTrue(success);

            (success,) = address(lending).call(
                abi.encodeWithSelector(DreamAcademyLending.borrow.selector, address(usdc), 1000 ether)
            );
            assertTrue(success);

            // 2000 / (4000 - 1333) * 100 = 74.xxxx
            // LT = 75%
            (success,) = address(lending).call(
                abi.encodeWithSelector(DreamAcademyLending.withdraw.selector, address(0x0), 1 ether * 1333 / 4000)
            );
            assertTrue(success);
        }
        vm.stopPrank();
    }

    function testWithdrawLockedCollateralAfterInterestAccuredFails() external {
        supplyUSDCDepositUser1();
        supplySmallEtherDepositUser2();

        dreamOracle.setPrice(address(0x0), 4000 ether); // 4000 usdc

        vm.startPrank(user2);
        {
            (bool success,) = address(lending).call(
                abi.encodeWithSelector(DreamAcademyLending.borrow.selector, address(usdc), 1000 ether)
            );
            assertTrue(success);

            (success,) = address(lending).call(
                abi.encodeWithSelector(DreamAcademyLending.borrow.selector, address(usdc), 1000 ether)
            );
            assertTrue(success);

            // 2000 / (4000 - 1333) * 100 = 74.xxxx
            // LT = 75%
            vm.roll(block.number + 1000);
            (success,) = address(lending).call(
                abi.encodeWithSelector(DreamAcademyLending.withdraw.selector, address(0x0), 1 ether * 1333 / 4000)
            );
            assertFalse(success);
        }
        vm.stopPrank();
    }

    function testWithdrawYieldSucceeds() external {
        usdc.transfer(user3, 30000000 ether);
        vm.startPrank(user3);
        usdc.approve(address(lending), type(uint256).max);
        lending.deposit(address(usdc), 30000000 ether);
        vm.stopPrank();

        supplyUSDCDepositUser1();
        supplySmallEtherDepositUser2();

        dreamOracle.setPrice(address(0x0), 4000 ether);

        bool success;

        vm.startPrank(user2);
        {
            (success,) = address(lending).call(
                abi.encodeWithSelector(DreamAcademyLending.borrow.selector, address(usdc), 1000 ether)
            );
            assertTrue(success);

            (success,) = address(lending).call(
                abi.encodeWithSelector(DreamAcademyLending.borrow.selector, address(usdc), 1000 ether)
            );
            assertTrue(success);

            (success,) = address(lending).call(
                abi.encodeWithSelector(DreamAcademyLending.withdraw.selector, address(0x0), 1 ether)
            );
            assertFalse(success);
        }
        vm.stopPrank();

        vm.roll(block.number + (86400 * 1000 / 12));
        vm.prank(user3);
        assertTrue(lending.getAccruedSupplyAmount(address(usdc)) / 1e18 == 30000792);

        vm.roll(block.number + (86400 * 500 / 12));
        vm.prank(user3);
        assertTrue(lending.getAccruedSupplyAmount(address(usdc)) / 1e18 == 30001605);

        vm.prank(user3);
        (success,) = address(lending).call(
            abi.encodeWithSelector(DreamAcademyLending.withdraw.selector, address(usdc), 30001605 ether)
        );
        assertTrue(success);
        assertTrue(usdc.balanceOf(user3) == 30001605 ether);

        assertTrue(lending.getAccruedSupplyAmount(address(usdc)) / 1e18 == 0);
    }

    function testExchangeRateChangeAfterUserBorrows() external {
        usdc.transfer(user3, 30000000 ether);
        vm.startPrank(user3);
        usdc.approve(address(lending), type(uint256).max);
        lending.deposit(address(usdc), 30000000 ether);
        vm.stopPrank();

        supplyUSDCDepositUser1();
        supplySmallEtherDepositUser2();

        dreamOracle.setPrice(address(0x0), 4000 ether);

        vm.startPrank(user2);
        {
            (bool success,) = address(lending).call(
                abi.encodeWithSelector(DreamAcademyLending.borrow.selector, address(usdc), 1000 ether)
            );
            assertTrue(success);

            (success,) = address(lending).call(
                abi.encodeWithSelector(DreamAcademyLending.borrow.selector, address(usdc), 1000 ether)
            );
            assertTrue(success);

            (success,) = address(lending).call(
                abi.encodeWithSelector(DreamAcademyLending.withdraw.selector, address(0x0), 1 ether)
            );
            assertFalse(success);
        }
        vm.stopPrank();

        vm.roll(block.number + (86400 * 1000 / 12));
        vm.prank(user3);
        assertTrue(lending.getAccruedSupplyAmount(address(usdc)) / 1e18 == 30000792);

        // other lender deposits USDC to our protocol.
        usdc.transfer(user4, 10000000 ether);
        vm.startPrank(user4);
        usdc.approve(address(lending), type(uint256).max);
        lending.deposit(address(usdc), 10000000 ether);
        vm.stopPrank();

        vm.roll(block.number + (86400 * 500 / 12));
        vm.prank(user3);
        uint256 a = lending.getAccruedSupplyAmount(address(usdc));

        vm.prank(user4);
        uint256 b = lending.getAccruedSupplyAmount(address(usdc));

        vm.prank(user1);
        uint256 c = lending.getAccruedSupplyAmount(address(usdc));

        assertEq((a + b + c) / 1e18 - 30000000 - 10000000 - 100000000, 6956);
        assertEq(a / 1e18 - 30000000, 1547);
        assertEq(b / 1e18 - 10000000, 251);
    }

    function testWithdrawFullUndilutedAfterDepositByOtherAccountSucceeds() external {
        vm.deal(user2, 100000000 ether);
        vm.startPrank(user2);
        {
            lending.deposit{value: 100000000 ether}(address(0x00), 100000000 ether);
        }
        vm.stopPrank();

        vm.deal(user3, 100000000 ether);
        vm.startPrank(user3);
        {
            lending.deposit{value: 100000000 ether}(address(0x00), 100000000 ether);
        }
        vm.stopPrank();

        vm.startPrank(user2);
        {
            lending.withdraw(address(0x00), 100000000 ether);
            assertEq(address(user2).balance, 100000000 ether);
        }
        vm.stopPrank();
    }

    function testLiquidationHealthyLoanFails() external {
        supplyUSDCDepositUser1();
        supplySmallEtherDepositUser2();

        dreamOracle.setPrice(address(0x0), 4000 ether);

        vm.startPrank(user2);
        {
            // use all collateral
            (bool success,) = address(lending).call(
                abi.encodeWithSelector(DreamAcademyLending.borrow.selector, address(usdc), 2000 ether)
            );
            assertTrue(success);

            assertTrue(usdc.balanceOf(user2) == 2000 ether);

            usdc.approve(address(lending), type(uint256).max);
        }
        vm.stopPrank();

        usdc.transfer(user3, 3000 ether);
        vm.startPrank(user3);
        {
            usdc.approve(address(lending), type(uint256).max);
            (bool success,) = address(lending).call(
                abi.encodeWithSelector(DreamAcademyLending.liquidate.selector, user2, address(usdc), 800 ether)
            );
            assertFalse(success);
        }
        vm.stopPrank();
    }

    function testLiquidationUnhealthyLoanSucceeds() external {
        supplyUSDCDepositUser1();
        supplySmallEtherDepositUser2();

        dreamOracle.setPrice(address(0x0), 4000 ether);

        vm.startPrank(user2);
        {
            // use all collateral
            (bool success,) = address(lending).call(
                abi.encodeWithSelector(DreamAcademyLending.borrow.selector, address(usdc), 2000 ether)
            );
            assertTrue(success);

            assertTrue(usdc.balanceOf(user2) == 2000 ether);

            usdc.approve(address(lending), type(uint256).max);
        }
        vm.stopPrank();

        dreamOracle.setPrice(address(0x0), (4000 * 66 / 100) * 1e18); // drop price to 66%
        usdc.transfer(user3, 3000 ether);

        vm.startPrank(user3);
        {
            usdc.approve(address(lending), type(uint256).max);
            (bool success,) = address(lending).call(
                abi.encodeWithSelector(DreamAcademyLending.liquidate.selector, user2, address(usdc), 500 ether)
            );
            assertTrue(success);
        }
        vm.stopPrank();
    }

    function testLiquidationExceedingDebtFails() external {
        // ** README **
        // can liquidate the whole position when the borrowed amount is less than 100,
        // otherwise only 25% can be liquidated at once.
        supplyUSDCDepositUser1();
        supplySmallEtherDepositUser2();

        dreamOracle.setPrice(address(0x0), 4000 ether);

        vm.startPrank(user2);
        {
            // use all collateral
            (bool success,) = address(lending).call(
                abi.encodeWithSelector(DreamAcademyLending.borrow.selector, address(usdc), 2000 ether)
            );
            assertTrue(success);

            assertTrue(usdc.balanceOf(user2) == 2000 ether);

            usdc.approve(address(lending), type(uint256).max);
        }
        vm.stopPrank();

        dreamOracle.setPrice(address(0x0), (4000 * 66 / 100) * 1e18); // drop price to 66%
        usdc.transfer(user3, 3000 ether);

        vm.startPrank(user3);
        {
            usdc.approve(address(lending), type(uint256).max);
            (bool success,) = address(lending).call(
                abi.encodeWithSelector(DreamAcademyLending.liquidate.selector, user2, address(usdc), 501 ether)
            );
            assertFalse(success);
        }
        vm.stopPrank();
    }

    function testLiquidationHealthyLoanAfterPriorLiquidationFails() external {
        supplyUSDCDepositUser1();
        supplySmallEtherDepositUser2();

        dreamOracle.setPrice(address(0x0), 4000 ether);

        vm.startPrank(user2);
        {
            // use all collateral
            (bool success,) = address(lending).call(
                abi.encodeWithSelector(DreamAcademyLending.borrow.selector, address(usdc), 2000 ether)
            );
            assertTrue(success);

            assertTrue(usdc.balanceOf(user2) == 2000 ether);

            usdc.approve(address(lending), type(uint256).max);
        }
        vm.stopPrank();

        dreamOracle.setPrice(address(0x0), (4000 * 66 / 100) * 1e18); // drop price to 66%
        usdc.transfer(user3, 3000 ether);

        vm.startPrank(user3);
        {
            usdc.approve(address(lending), type(uint256).max);
            (bool success,) = address(lending).call(
                abi.encodeWithSelector(DreamAcademyLending.liquidate.selector, user2, address(usdc), 500 ether)
            );
            assertTrue(success);
            (success,) = address(lending).call(
                abi.encodeWithSelector(DreamAcademyLending.liquidate.selector, user2, address(usdc), 100 ether)
            );
            assertFalse(success);
        }
        vm.stopPrank();
    }

    function testLiquidationAfterBorrowerCollateralDepositFails() external {
        supplyUSDCDepositUser1();
        supplySmallEtherDepositUser2();

        dreamOracle.setPrice(address(0x0), 4000 ether);

        vm.startPrank(user2);
        {
            // use all collateral
            (bool success,) = address(lending).call(
                abi.encodeWithSelector(DreamAcademyLending.borrow.selector, address(usdc), 2000 ether)
            );
            assertTrue(success);

            assertTrue(usdc.balanceOf(user2) == 2000 ether);

            usdc.approve(address(lending), type(uint256).max);
        }
        vm.stopPrank();

        supplySmallEtherDepositUser2();

        dreamOracle.setPrice(address(0x0), (4000 * 66 / 100) * 1e18); // drop price to 66%
        usdc.transfer(user3, 3000 ether);

        vm.startPrank(user3);
        {
            usdc.approve(address(lending), type(uint256).max);
            (bool success,) = address(lending).call(
                abi.encodeWithSelector(DreamAcademyLending.liquidate.selector, user2, address(usdc), 500 ether)
            );
            assertFalse(success);
        }
        vm.stopPrank();
    }

    function testLiquidationAfterDebtPriceDropFails() external {
        // just imagine if USDC falls down
        supplyUSDCDepositUser1();
        supplySmallEtherDepositUser2();

        dreamOracle.setPrice(address(0x0), 4000 ether);

        vm.startPrank(user2);
        {
            // use all collateral
            (bool success,) = address(lending).call(
                abi.encodeWithSelector(DreamAcademyLending.borrow.selector, address(usdc), 2000 ether)
            );
            assertTrue(success);

            assertTrue(usdc.balanceOf(user2) == 2000 ether);

            usdc.approve(address(lending), type(uint256).max);
        }
        vm.stopPrank();

        dreamOracle.setPrice(address(0x0), (4000 * 66 / 100) * 1e18); // drop Ether price to 66%
        dreamOracle.setPrice(address(usdc), 1e17); // drop USDC price to 0.1, 90% down
        usdc.transfer(user3, 3000 ether);

        vm.startPrank(user3);
        {
            usdc.approve(address(lending), type(uint256).max);
            (bool success,) = address(lending).call(
                abi.encodeWithSelector(DreamAcademyLending.liquidate.selector, user2, address(usdc), 500 ether)
            );
            assertFalse(success);
        }
        vm.stopPrank();
    }

    receive() external payable {
        // for ether receive
    }
}
```
