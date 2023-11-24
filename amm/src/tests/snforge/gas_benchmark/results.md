# Modify position

## Case 1 (MPALU): Add liquidity at previously uninitialised limits

1. Initial market config checks: [36000]
2. Read state: [61000]
3. Input checks: [0]
4. Update liquidity: [4057650][T]
   1. Read state: [25000]
   2. Update lower limit: [1811120][T]
      1. Update limit: [25000]
      2. Check overflow: [0]
      3. Update bitmap: [1761120]
      4. Calc and set fee factors: [0]
   3. Update upper limit: [1279520][T]
      1. Update limit: [25000]
      2. Check overflow: [0]
      3. Update bitmap: [1229520]
      4. Calc and set fee factors: [0]
   4. Initialise position: [41450]
   5. Calc fees: [0]
   6. Update position: [25000]
   7. Calculate token amounts: [875560]
5. Update fees: [0]
6. Update reserves: [40000]
7. Transfer tokens: [1065940]
8. Emit event: [1000]

Total: [5261590]

## Case 2 (MPALI): Add liquidity at previously initialised limits

1. Initial market config checks: [36000]
2. Read state: [61000]
3. Input checks: [0]
4. Update liquidity: [1067010][T]
   1. Read state: [25000]
   2. Update lower limit: [50000][T]
      1. Update limit: [25000]
      2. Check overflow: [0]
      3. Update bitmap: [0]
      4. Calc and set fee factors: [0]
   3. Update upper limit: [50000][T]
      1. Update limit: [25000]
      2. Check overflow: [0]
      3. Update bitmap: [1229520]
      4. Calc and set fee factors: [0]
   4. Initialise position: [41450]
   5. Calc fees: [0]
   6. Update position: [25000]
   7. Calculate token amounts: [875560]
5. Update fees: [0]
6. Update reserves: [40000]
7. Transfer tokens: [1065940]
8. Emit event: [1000]

Total: [2270950]

## Case 3 (MPALIU): Add liquidity at initialised lower, but previously uninitialised upper limit

TODO

## Case 4 (MPCF): Collect fees from position (position is only one at limits)

TODO

## Case 5 (MPRL01): Remove liquidity with no accumulated fees (position is only one at limits)

TODO

## Case 6 (MPRLFM): Remove liquidity with accumulated fees (position is only one at limits)

TODO

## Case 7 (MPRL01): Remove liquidity with no accumulated fees (other positions exist at limits)

TODO

## Case 8 (MPRLFM): Remove liquidity with accumulated fees (other positions exist at limits)

TODO
