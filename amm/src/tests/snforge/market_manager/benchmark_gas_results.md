# Benchmark cases

| #   | Action                                                               | Gas     |
| --- | -------------------------------------------------------------------- | ------- |
| 1   | Create market                                                        | 110.70  |
| 2   | Add liquidity at previously uninitialised limit                      | 1025.28 |
| 3   | Add liquidity at previously initialised limit                        | 678.56  |
| 4   | Add liquidity at prev. initialised lower + uninitialised upper limit | 702.24  |
| 5   | Remove partial liquidity from position (no fees)                     | 671.84  |
| 6   | Remove all liquidity from position (no fees)                         | 922.88  |
| 7   | Remove all liquidity from position (with fees)                       | 928.64  |
| 8   | Collect fees from position                                           | 229.92  |
| 9   | Swap with zero liquidity                                             | 141.84  |
| 10  | Swap within 1 tick                                                   | 2062.72 |
| 11  | Swap with 1 tick crossed                                             | 3042.08 |
| 12  | Swap with 2 ticks crossed                                            | 3236.16 |
| 13  | Swap with 4 ticks crossed                                            | 4346.88 |
| 14  | Swap with 4 ticks crossed (wide interval)                            | 4571.36 |
| 15  | Swap with 6 ticks crossed                                            | 5525.28 |
| 16  | Swap with 6 ticks crossed (wide interval)                            | 5700.96 |
| 17  | Swap with 10 ticks crossed                                           | 7800.00 |
| 18  | Swap with 10 ticks crossed (wide interval)                           | 7938.56 |
| 19  | Swap with 20 ticks crossed                                           |         |
| 20  | Swap with 20 ticks crossed (wide interval)                           |         |

### Raw data

1. Create market
   1. Before: 67.51
   2. Gross: 178.21
   3. Net: 110.70
2. Add liquidity at previously uninitialised limit
   1. Before: 1242.88
   2. Gross: 2268.16
   3. Net: 1025.28
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
   1. Before: 2089.44
   2. Gross: 3012.32
   3. Net: 922.88
7. Remove all liquidity from position (with fees)
   1. Before: 4153.12
   2. Gross: 5081.76
   3. Net: 928.64
8. Collect fees from position
   1. Before: 3350.24
   2. Gross: 3580.16
   3. Net: 229.92
9. Swap with zero liquidity
   1. Before: 178.38
   2. Gross: 320.22
   3. Net: 141.84
10. Swap within 1 tick
    1. Before: 1286.24
    2. Gross: 3348.96
    3. Net: 2062.72
11. Swap with 1 tick crossed
    1. Before: 2241.28
    2. Gross: 5283.36
    3. Net: 3042.08
12. Swap with 2 ticks crossed
    1. Before: 2241.6
    2. Gross: 5477.76
    3. Net: 3236.16
13. Swap with 4 ticks crossed
    1. Before: 3266.08
    2. Gross: 7612.96
    3. Net: 4346.88
14. Swap with 4 ticks crossed (wide interval)
    1. Before: 3411.04
    2. Gross: 7982.40
    3. Net: 4571.36
15. Swap with 6 ticks crossed
    1. Before: 4294.4
    2. Gross: 9819.68
    3. Net: 5525.28
16. Swap with 6 ticks crossed (wide interval)
    1. Before: 4374.24
    2. Gross: 10075.2
    3. Net: 5700.96
17. Swap with 10 ticks crossed
    1. Before: 6323.04
    2. Gross: 14123.04
    3. Net: 7800.00
18. Swap with 10 ticks crossed (wide interval)
    1. Before: 6313.12
    2. Gross: 14251.68
    3. Net: 7938.56
19. Swap with 20 ticks crossed
    1. Before:
    2. Gross:
    3. Net:
20. Swap with 20 ticks crossed (wide interval)
    1. Before:
    2. Gross:
    3. Net:
21. Swap across a limit order, partial fill (cross 1 tick)
22. Swap across a limit order, full fill (cross 1 tick)
23. Create limit order
24. Collect unfilled limit order
25. Collect partially filled limit order
26. Collect fully filled limit order
27. Swap within a tick with strategy enabled, no position updates
28. Swap within a tick with strategy enabled, one position update
29. Swap within a tick with strategy enabled, both position updates
