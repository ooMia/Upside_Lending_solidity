https://github.com/compound-finance/compound-protocol/blob/master/contracts/ExponentialNoError.sol

- https://compound.finance/Developers

- https://docs.compound.finance/collateral-and-borrowing/

- https://github.com/compound-finance/compound-protocol/blob/a3214f67b73310d547e00fc578e8355911c9d376/contracts/CToken.sol#L327

```solidity
/**
    * @notice Applies accrued interest to total borrows and reserves
    * @dev This calculates interest accrued from the last checkpointed block
    *   up to the current block and writes new checkpoint to storage.
    */
function accrueInterest() virtual override public returns (uint) {
    /* Remember the initial block number */
    uint currentBlockNumber = getBlockNumber();
    uint accrualBlockNumberPrior = accrualBlockNumber;

    /* Short-circuit accumulating 0 interest */
    if (accrualBlockNumberPrior == currentBlockNumber) {
        return NO_ERROR;
    }

    /* Read the previous values out of storage */
    uint cashPrior = getCashPrior();
    uint borrowsPrior = totalBorrows;
    uint reservesPrior = totalReserves;
    uint borrowIndexPrior = borrowIndex;

    /* Calculate the current borrow interest rate */
    uint borrowRateMantissa = interestRateModel.getBorrowRate(cashPrior, borrowsPrior, reservesPrior);
    require(borrowRateMantissa <= borrowRateMaxMantissa, "borrow rate is absurdly high");

    /* Calculate the number of blocks elapsed since the last accrual */
    uint blockDelta = currentBlockNumber - accrualBlockNumberPrior;

    /*
        * Calculate the interest accumulated into borrows and reserves and the new index:
        *  simpleInterestFactor = borrowRate * blockDelta
        *  interestAccumulated = simpleInterestFactor * totalBorrows
        *  totalBorrowsNew = interestAccumulated + totalBorrows
        *  totalReservesNew = interestAccumulated * reserveFactor + totalReserves
        *  borrowIndexNew = simpleInterestFactor * borrowIndex + borrowIndex
        */

    Exp memory simpleInterestFactor = mul_(Exp({mantissa: borrowRateMantissa}), blockDelta);
    uint interestAccumulated = mul_ScalarTruncate(simpleInterestFactor, borrowsPrior);
    uint totalBorrowsNew = interestAccumulated + borrowsPrior;
    uint totalReservesNew = mul_ScalarTruncateAddUInt(Exp({mantissa: reserveFactorMantissa}), interestAccumulated, reservesPrior);
    uint borrowIndexNew = mul_ScalarTruncateAddUInt(simpleInterestFactor, borrowIndexPrior, borrowIndexPrior);

    /////////////////////////
    // EFFECTS & INTERACTIONS
    // (No safe failures beyond this point)

    /* We write the previously calculated values into storage */
    accrualBlockNumber = currentBlockNumber;
    borrowIndex = borrowIndexNew;
    totalBorrows = totalBorrowsNew;
    totalReserves = totalReservesNew;

    /* We emit an AccrueInterest event */
    emit AccrueInterest(cashPrior, interestAccumulated, borrowIndexNew, totalBorrowsNew);

    return NO_ERROR;
}
```
