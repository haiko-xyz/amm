# Benchmark cases

| #   | Action                                                               | Gas   |
| --- | -------------------------------------------------------------------- | ----- |
| 1   | Create market                                                        |       |
| 2   | Add liquidity at previously uninitialised limit                      |       |
| 3   | Add liquidity at previously initialised limit                        |       |
| 4   | Add liquidity at prev. initialised lower + uninitialised upper limit |       |
| 5   | Remove partial liquidity from position (no fees)                     |       |
| 6   | Remove all liquidity from position (no fees)                         |       |
| 7   | Remove all liquidity from position (with fees)                       |       |
| 8   | Collect fees from position                                           |       |
| 9   | Swap with zero liquidity                                             | 77    |
| 10  | Swap within 1 tick                                                   | 2262  |
| 11  | Swap with 1 tick crossed                                             | 4967  |
| 12  | Swap with 2 ticks crossed                                            | 5291  |
| 13  | Swap with 4 ticks crossed                                            | 8298  |
| 14  | Swap with 4 ticks crossed (wide interval)                            | 8409  |
| 15  | Swap with 6 ticks crossed                                            | 11338 |
| 16  | Swap with 6 ticks crossed (wide interval)                            | 11426 |
| 17  | Swap with 10 ticks crossed                                           | 17377 |
| 18  | Swap with 10 ticks crossed (wide interval)                           | 17446 |
| 19  | Swap with 20 ticks crossed                                           | 32200 |
| 20  | Swap with 20 ticks crossed (wide interval)                           | 35240 |
| 21  | Swap across a limit order, partial fill (cross 1 tick)               | 4932  |
| 22  | Swap across a limit order, full fill (cross 1 tick)                  | 3379  |

### Raw data

1. Create market
   1. Before:
   2. Gross:
   3. Net:
2. Add liquidity at previously uninitialised limit
   1. Before:
   2. Gross:
   3. Net:
3. Add liquidity at previously initialised limit
   1. Before:
   2. Gross:
   3. Net:
4. Add liquidity at prev. initialised lower + uninitialised upper limit
   1. Before:
   2. Gross:
   3. Net:
5. Remove partial liquidity from position (no fees)
   1. Before:
   2. Gross:
   3. Net:
6. Remove all liquidity from position (no fees)
   1. Before:
   2. Gross:
   3. Net:
7. Remove all liquidity from position (with fees)
   1. Before:
   2. Gross:
   3. Net:
8. Collect fees from position
   1. Before:
   2. Gross:
   3. Net:
9. Swap with zero liquidity
   1. Before: 44770
   2. Gross: 44847
   3. Net: 77
10. Swap within 1 tick
    1. Before: 61238
    2. Gross: 63500
    3. Net: 2262
11. Swap with 1 tick crossed
    1. Before: 70279
    2. Gross: 74246
    3. Net: 4967
12. Swap with 2 ticks crossed
    1. Before: 70279
    2. Gross: 75570
    3. Net: 5291
13. Swap with 4 ticks crossed
    1. Before: 79357
    2. Gross: 87655
    3. Net: 8298
14. Swap with 4 ticks crossed (wide interval)
    1. Before: 81878
    2. Gross: 90288
    3. Net: 8409
15. Swap with 6 ticks crossed
    1. Before: 88437
    2. Gross: 99775
    3. Net: 11338
16. Swap with 6 ticks crossed (wide interval)
    1. Before: 90925
    2. Gross: 102351
    3. Net: 11426
17. Swap with 10 ticks crossed
    1. Before: 106583
    2. Gross: 123960
    3. Net: 17377
18. Swap with 10 ticks crossed (wide interval)
    1. Before: 109026
    2. Gross: 126472
    3. Net: 17446
19. Swap with 20 ticks crossed
    1. Before: 140605
    2. Gross: 172800
    3. Net: 32200
20. Swap with 20 ticks crossed (wide interval)
    1. Before: 152155
    2. Gross: 187395
    3. Net: 35240
21. Swap across a limit order, partial fill (cross 1 tick)
    1. Before: 61216
    2. Gross: 66148
    3. Net: 4932
22. Swap across a limit order, full fill (cross 1 tick)
    1. Before: 61216
    2. Gross: 63595
    3. Net: 3379
23. Create limit order
24. Collect unfilled limit order
25. Collect partially filled limit order
26. Collect fully filled limit order
27. Swap within a tick with strategy enabled, no position updates
28. Swap within a tick with strategy enabled, one position update
29. Swap within a tick with strategy enabled, both position updates
