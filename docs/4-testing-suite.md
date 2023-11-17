# Testing suite

Sphinx uses both the native Cairo runner and [Starknet Foundry](https://github.com/foundry-rs/starknet-foundry/tree/master) for testing:

1. `cairo-test` is used for the majority of unit and integration tests. These can be found under [`amm/tests/cairo-test`](../amm/src/tests/cairo_test).
2. `starknet-foundry` is used for more complex tests such as fuzzing, invariant tests, fork tests, etc. These can be found under [`amm/tests/snforge`](../amm/src/tests/snforge).

Common utilities and test contracts used by both testing frameworks can be found under [`amm/tests/common`](../amm/src/tests/common).

## Libraries and utilities

Common actions such as deploying contracts, approving spend allowances etc have been abstracted into a set of helper functions to enable reuse across test cases.

When writing new test cases, it is recommended to use these libraries to ensure consistency and code reuse:

- `helpers` ([`cairo-test`](../amm/src/tests/cairo_test/helpers), [`snforge`](../amm/src/tests/snforge/helpers)) contain common actions for interacting with each contract
- `params` ([`common`](../amm/src/tests/common/params.cairo)) contains default parameters for each function call as well as helper functions for compiling calldata
- `utils` ([`common`](../amm/src/tests/common/utils.cairo)) contains utility functions for testing

## Models

Sphinx's execution logic is relatively complex. To help with testing, we rely on a set of [models](../models) to replicate the computations under each test case. The models produce a set of canonical results that can be compared to test outputs.

The models are written in Typescript and run on `decimal.js`, a high precision math library. They are designed to be as simple as possible to minimise the risk of bugs, although of course they are not guaranteed to be bug free.

Crucially, conceptual errors in the contracts will not be caught as they will make their way into both the contracts and the models. To mitigate this, we also write invariant tests to check for internal consistency in the contract logic itself.

## Running tests

### `cairo-test`

To run test cases with `cairo-test`, make sure you have install:

- [`scarb`](https://github.com/software-mansion/scarb/)
- [`cairo`](https://github.com/starkware-libs/cairo)

```bash
cd amm
scarb test -f cairo_test
```

To run specific test cases, specify the full path or the test name, e.g.:

```bash
scarb test -f cairo_test::math::test_bit_math::test_msb_cases

# same as above if test name is unique
scarb test -f test_msb_cases
```

### `snforge`

To run `snforge` tests, make sure you have installed:

- [`scarb`](https://github.com/software-mansion/scarb/)
- [`cairo`](https://github.com/starkware-libs/cairo)
- [`snforge`](https://github.com/foundry-rs/starknet-foundry/)

```bash
snforge test snforge
```

To run specific test cases, specify the full path or the test name, e.g.:

```bash
snforge test snforge::math::test_bit_math_invariants::test_msb_invariant

# same as above if test name is unique
snforge test test_msb_invariant
```
