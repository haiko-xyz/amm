# Benchmark cases

1. Create market
   1. Before: 67.51
   2. Gross: 178.21
   3. Net: 110.70
2. Add liquidity at previously uninitialised limit
   1. Before: 178.38
   2. Gross: 1286.56
   3. Net: 1108.18
3. Add liquidity at previously initialised limit
   1. Before: 1286.56
   2. Gross: 1965.12
   3. Net: 678.56
4. Add liquidity at prev. initialised lower + uninitialised upper limit
   1. Before: 1286.56
   2. Gross: 1988.8
   3. Net: 702.24
5. Remove partial liquidity from position (no fees)
   1. Before: 1286.56
   2. Gross: 1958.4
   3. Net: 671.84
6. Remove all liquidity from position (no fees)
   1. Before: 1286.56
   2. Gross: 2400.16
   3. Net: 1113.6
7. Remove all liquidity from position (with fees)
   1. Before: 3350.24
   2. Gross: 4469.6
   3. Net: 1119.36
8. Collect fees from position
   1. Before: 3350.24
   2. Gross: 3580.16
   3. Net: 229.92
9. Swap with zero liquidity
   1. Before: 178.38
   2. Gross: 320.22
   3. Net: 141.84
10. Swap with normal liquidity, within 1 limit
    1. Before: 1286.24
    2. Gross: 3348.96
    3. Net: 2062.72
11. Swap with normal liquidity, 1 limit crossed
    1. Before: 2241.28
    2. Gross: 5283.36
    3. Net: 3042.08
12. Swap with normal liquidity, 4 limits crossed
    1. Before: 3236.16
    2. Gross: 6770.24
    3. Net: 3534.08
13. Swap with normal liquidity, 9 limits crossed
    1. Before: 4231.04
    2. Gross: 11176.64
    3. Net: 6945.6
14. Swap with limit order, partial fill
15. Swap with limit order, full fill
16. Swap with strategy enabled, no position updates
17. Swap with strategy enabled, one position update
18. Swap with strategy enabled, both position updates
19. Create limit order
20. Collect unfilled limit order
21. Collect partially filled limit order
22. Collect fully filled limit order
