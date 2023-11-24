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

# Swap

## Case 1: (SPZN): Swap with normal liquidity position, zero liquidity, no limit crossed

1. Update swap_id: [10000]
2. Read state: [60000]
3. Run checks: [1000]
4. Update Strategy: [1000][T]
5. Fetch fee rate: [0]
6. Init swap state: [25000]
7. Swap Iterator: [14196060][T]
   1. Checks + Init state: [0]
   2. Tree next limit: [116320]
   3. Calculate target price: [425280]
   4. Compute Swap Amounts: [0][T]
      1. Calculate amounts: [0]
      2. Calculate next sqrt price: [0]
      3. Update amounts: [0]
      4. Calc fee: [0]
   5. Calc amts + fees: [0]
   6. Update market state: [8913060]
8. Calc swap amts: [0]
9. Update fee: [20000]
10. Update market state: [25000]
11. Update reserves: [40000]
12. Fill full limits: [10366430] [T]
13. Fill partial limits: [55010] [T]
   1. Read State: [55010]
14. Transfer tokens: [721700]
15. Strategy cleanup: [0]
16. Emit event: [1000]

Total: [25522200]

## Case 2: (SPHN): Swap with normal liquidity position, high liquidity, no limit crossed

1. Update swap_id: [10000]
2. Read state: [60000]
3. Run checks: [1000]
4. Update Strategy: [1000][T]
5. Fetch fee rate: [0]
6. Init swap state: [25000]
7. Swap Iterator: [14196060][T]
   1. Checks + Init state: [0]
   2. Tree next limit: [116320]
   3. Calculate target price: [425280]
   4. Compute Swap Amounts: [0][T]
      1. Calculate amounts: [0]
      2. Calculate next sqrt price: [0]
      3. Update amounts: [0]
      4. Calc fee: [0]
   5. Calc amts + fees: [0]
   6. Update market state: [8913060]
8. Calc swap amts: [0]
9. Update fee: [20000]
10. Update market state: [25000]
11. Update reserves: [40000]
12. Fill full limits: [10366430] [T]
13. Fill partial limits: [0] [T]
14. Transfer tokens: [721700]
15. Strategy cleanup: [0]
16. Emit event: [1000]

Total: [25467190]

## Case 3: (SPZ1): Swap with normal liquidity position, zero liquidity, one limit crossed

1. Update swap_id: [10000]
2. Read state: [60000]
3. Run checks: [1000]
4. Update Strategy: [1000][T]
5. Fetch fee rate: [0]
6. Init swap state: [25000]
7. Swap Iterator: [19582220][T]
   1. 1st Iteration: [591600][T]
      1. Checks + Init state: [0]
      2. Tree next limit: [116320]
      3. Calculate target price: [425280]
      4. Compute Swap Amounts: [0][T]
         1. Calculate amounts: [0]
         2. Calculate next sqrt price: [0]
         3. Update amounts: [0]
         4. Calc fee: [0]
      5. Calc amts + fees: [0]
      6. Append filled limit: [0]
      7. Update limit info: [50000]
      8. Update mkt state: [0]
   2. 2nd Iteration: [9507820][T]
      1. Checks + Init state: [0]
      2. Tree next limit: [169480]
      3. Calculate target price: [425280]
      4. Compute Swap Amounts: [0][T]
         1. Calculate amounts: [0]
         2. Calculate next sqrt price: [0]
         3. Update amounts: [0]
         4. Calc fee: [0]
      5. Calc amts + fees: [0]
      6. Update mkt state: [8913060]
8. Calc swap amts: [0]
9. Update fee: [20000]
10. Update market state: [25000]
11. Update reserves: [40000]
12. Fill full limits: [10366430] [T]
13. Fill partial limits: [0] [T]
14. Transfer tokens: [721700]
15. Strategy cleanup: [0]
16. Emit event: [1000]

Total: [30853350]

## Case 4: (SPH1): Swap with normal liquidity position, high liquidity, one limit crossed

1. Update swap_id: [10000]
2. Read state: [60000]
3. Run checks: [1000]
4. Update Strategy: [1000][T]
5. Fetch fee rate: [0]
6. Init swap state: [25000]
7. Swap Iterator: [11486560][T]
   1. 1st Iteration: [804240][T]
      1. Checks + Init state: [0]
      2. Tree next limit: [328960]
      3. Calculate target price: [425280]
      4. Compute Swap Amounts: [0][T]
         1. Calculate amounts: [0]
         2. Calculate next sqrt price: [0]
         3. Update amounts: [0]
         4. Calc fee: [0]
      5. Calc amts + fees: [0]
      6. Append filled limit: [0]
      7. Update limit info: [50000]
      8. Update mkt state: [0]
   2. 2nd Iteration: [1199520][T]
      1. Checks + Init state: [0]
      2. Tree next limit: [774240]
      3. Calculate target price: [425280]
      4. Compute Swap Amounts: [0][T]
         1. Calculate amounts: [0]
         2. Calculate next sqrt price: [0]
         3. Update amounts: [0]
         4. Calc fee: [0]
      5. Calc amts + fees: [0]
8. Calc swap amts: [0]
9. Update fee: [20000]
10. Update market state: [25000]
11. Update reserves: [40000]
12. Fill full limits: [10366430] [T]
13. Fill partial limits: [0] [T]
14. Transfer tokens: [721700]
15. Strategy cleanup: [0]
16. Emit event: [1000]

Total: [22757690]

## Case 5: (SPH4): Swap with normal liquidity position, high liquidity, four limits crossed

TODO

## Case 6: (SPH4): Swap with normal liquidity position, zero liquidity, four limits crossed

TODO

## Case 7: (SLLFF): Swap with limit order, limit fully filled

1. Update swap_id: [10000]
2. Read state: [60000]
3. Run checks: [1000]
4. Update Strategy: [1000][T]
5. Fetch fee rate: [0]
6. Init swap state: [25000]
7. Swap Iterator: [10562840][T]
   1. 1st Iteration: [538440][T]
      1. Checks + Init state: [0]
      2. Tree next limit: [63160]
      3. Calculate target price: [425280]
      4. Compute Swap Amounts: [0][T]
         1. Calculate amounts: [0]
         2. Calculate next sqrt price: [0]
         3. Update amounts: [0]
         4. Calc fee: [0]
      5. Calc amts + fees: [0]
      6. Append filled limit: [0]
      7. Update limit info: [50000]
      8. Update mkt state: [0]
   2. 2nd Iteration: [541600][T]
      1. Checks + Init state: [0]
      2. Tree next limit: [116320]
      3. Calculate target price: [425280]
      4. Compute Swap Amounts: [0][T]
         1. Calculate amounts: [0]
         2. Calculate next sqrt price: [0]
         3. Update amounts: [0]
         4. Calc fee: [0]
      5. Calc amts + fees: [0]
8. Calc swap amts: [0]
9. Update fee: [20000]
10. Update market state: [25000]
11. Update reserves: [40000]
12. Fill full limits: [10366430] [T]
13. Fill partial limits: [0] [T]
14. Transfer tokens: [721700]
15. Strategy cleanup: [0]
16. Emit event: [1000]

Total: [21833970]

## Case 8: (SLLPF): Swap with limit order, limit partially filled

1. Update swap_id: [10000]
2. Read state: [60000]
3. Run checks: [1000]
4. Update Strategy: [1000][T]
5. Fetch fee rate: [0]
6. Init swap state: [25000]
7. Swap Iterator: [19688540][T]
   1. 1st Iteration: [538440][T]
      1. Checks + Init state: [0]
      2. Tree next limit: [63160]
      3. Calculate target price: [425280]
      4. Compute Swap Amounts: [0][T]
         1. Calculate amounts: [0]
         2. Calculate next sqrt price: [0]
         3. Update amounts: [0]
         4. Calc fee: [0]
      5. Calc amts + fees: [0]
      6. Append filled limit: [0]
      7. Update limit info: [50000]
      8. Update mkt state: [0]
   2. 2nd Iteration: [9667300][T]
      1. Checks + Init state: [0]
      2. Tree next limit: [328960]
      3. Calculate target price: [425280]
      4. Compute Swap Amounts: [0][T]
         1. Calculate amounts: [0]
         2. Calculate next sqrt price: [0]
         3. Update amounts: [0]
         4. Calc fee: [0]
      5. Calc amts + fees: [0]
      6. Update market state: [8913060]
8. Calc swap amts: [0]
9. Update fee: [20000]
10. Update market state: [25000]
11. Update reserves: [40000]
12. Fill full limits: [10366430] [T]
13. Fill partial limits: [75010] [T]
   1. Read State: [55010]
   2. Update Fill: [20000]
14. Transfer tokens: [721700]
15. Strategy cleanup: [0]
16. Emit event: [1000]

Total: [31034680]
