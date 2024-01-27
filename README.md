# Haiko AMM

This repo contains the core contracts of Haiko AMM.

You can get started by reading through the following docs:

- [Technical Overview](./docs/1-technical-overview.md)
- [Comparison of Haiko vs Uniswap](./docs/2-haiko-vs-uniswap.md)
- [Using the Test Suite](./docs/4-testing-suite.md)
- [List of WIP Test Cases and Features](./docs/3-wip.md)

## Getting started

```shell
# Navigate to folder
cd amm

# Run the tests
scarb test -f cairo_test
snforge test snforge

# Build contracts
scarb build
```

## Version control

- [Scarb](https://github.com/software-mansion/scarb) 2.4.1
- [Cairo](https://github.com/starkware-libs/cairo) 2.4.1
- [Starknet Foundry](https://github.com/foundry-rs/starknet-foundry) 0.16.0
