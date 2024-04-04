# Benchmark cases

| #   | Action                                                               | Gross  |
| --- | -------------------------------------------------------------------- | ------ |
| 1   | Create market                                                        | 41421  |
| 2   | Add liquidity at previously uninitialised limit                      | 62279  |
| 3   | Add liquidity at previously initialised limit                        | 55520  |
| 4   | Add liquidity at prev. initialised lower + uninitialised upper limit | 58838  |
| 5   | Remove partial liquidity from position (no fees)                     | 61441  |
| 6   | Remove all liquidity from position (no fees)                         | 56057  |
| 7   | Remove all liquidity from position (with fees)                       | 59305  |
| 8   | Collect fees from position                                           | 58539  |
| 9   | Swap with zero liquidity                                             | 41514  |
| 10  | Swap within 1 tick                                                   | 57318  |
| 11  | Swap with 1 tick crossed                                             | 66010  |
| 12  | Swap with 2 ticks crossed                                            | 67205  |
| 13  | Swap with 4 ticks crossed                                            | 77105  |
| 14  | Swap with 4 ticks crossed (wide interval)                            | 79495  |
| 15  | Swap with 6 ticks crossed                                            | 87041  |
| 16  | Swap with 6 ticks crossed (wide interval)                            | 89374  |
| 17  | Swap with 10 ticks crossed                                           | 106858 |
| 18  | Swap with 10 ticks crossed (wide interval)                           | 109127 |
| 19  | Swap with 20 ticks crossed                                           | 145874 |
| 20  | Swap with 20 ticks crossed (wide interval)                           | 158042 |
| 21  | Swap across a limit order, partial fill (cross 1 tick)               | 59719  |
| 22  | Swap across a limit order, full fill (cross 1 tick)                  | 56312  |
| 23  | Create limit order                                                   | 55141  |
| 24  | Collect unfilled limit order                                         | 46877  |
| 25  | Collect partially filled limit order                                 | 50371  |
| 26  | Collect fully filled limit order                                     | 52158  |
| 27  | Swap within a tick with strategy enabled, no position updates        | 67222  |
| 28  | Swap within a tick with strategy enabled, one position update        | 67231  |
| 29  | Swap within a tick with strategy enabled, both position updates      | 67231  |

### Raw data

1. Create market
   1. Before: 34738
   2. Gross: 41421
   3. Net: 6683
2. Add liquidity at previously uninitialised limit
   1. Before: 52935
   2. Gross: 62279
   3. Net: 9344
3. Add liquidity at previously initialised limit
   1. Before: 55163
   2. Gross: 55520
   3. Net: 357
4. Add liquidity at prev. initialised lower + uninitialised upper limit
   1. Before: 55163
   2. Gross: 58838
   3. Net: 3675
5. Remove partial liquidity from position (no fees)
   1. Before: 61088
   2. Gross: 61441
   3. Net: 353
6. Remove all liquidity from position (no fees)
   1. Before: 61088
   2. Gross: 56057
   3. Net: n/a
7. Remove all liquidity from position (with fees)
   1. Before: 63234
   2. Gross: 59305
   3. Net: n/a
8. Collect fees from position
   1. Before: 57309
   2. Gross: 58539
   3. Net:
9. Swap with zero liquidity
   1. Before: 41421
   2. Gross: 41514
   3. Net:
10. Swap within 1 tick
    1. Before: 55163
    2. Gross: 57318
    3. Net:
11. Swap with 1 tick crossed
    1. Before: 62269
    2. Gross: 66010
    3. Net:
12. Swap with 2 ticks crossed
    1. Before: 62269
    2. Gross: 67205
    3. Net:
13. Swap with 4 ticks crossed
    1. Before: 69407
    2. Gross: 77105
    3. Net:
14. Swap with 4 ticks crossed (wide interval)
    1. Before: 71684
    2. Gross: 79495
    3. Net:
15. Swap with 6 ticks crossed
    1. Before: 76547
    2. Gross: 87041
    3. Net:
16. Swap with 6 ticks crossed (wide interval)
    1. Before: 78791
    2. Gross: 89374
    3. Net:
17. Swap with 10 ticks crossed
    1. Before: 90813
    2. Gross: 106858
    3. Net:
18. Swap with 10 ticks crossed (wide interval)
    1. Before: 93012
    2. Gross: 109127
    3. Net:
19. Swap with 20 ticks crossed
    1. Before: 116231
    2. Gross: 145874
    3. Net:
20. Swap with 20 ticks crossed (wide interval)
    1. Before: 125597
    2. Gross: 158042
    3. Net:
21. Swap across a limit order, partial fill (cross 1 tick)
    1. Before: 55141
    2. Gross: 59719
    3. Net:
22. Swap across a limit order, full fill (cross 1 tick)
    1. Before: 55141
    2. Gross: 56312
    3. Net:
23. Create limit order
    1. Before: 41421
    2. Gross: 55141
    3. Net:
24. Collect unfilled limit order
    1. Before: 55141
    2. Gross: 46877
    3. Net:
25. Collect partially filled limit order
    1. Before: 59719
    2. Gross: 50371
    3. Net:
26. Collect fully filled limit order
    1. Before: 56312
    2. Gross: 52158
    3. Net:
27. Swap within a tick with strategy enabled, no position updates
    1. Before: 67129
    2. Gross: 67222
    3. Net:
28. Swap within a tick with strategy enabled, one position update
    1. Before: 67138
    2. Gross: 67231
    3. Net:
29. Swap within a tick with strategy enabled, both position updates
    1. Before: 67138
    2. Gross: 67231
    3. Net:
