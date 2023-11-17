# WIP

This following test cases are currently missing. They are WIP and we aim to complete them prior to audit. The to dos below will likely be completed in parallel with or following the audit.

Existing tests

- Swap / modify position operations: canonical model results
- Check existing tests for missing cases (fail cases, check vs Uni code base)
- Add fuzzing and invariant tests
- Add tests for event emission

New tests

- Tests for minting and burning liquidity position NFTs
- Tests for sweep
- Tests for collecting protocol fees
- Tests for setting owner
- Tests for setting flash loan fee
- Tests for protocol fees
- Tests for dynamic fees

Other to dos

- Review access controls, timelock, and other security features
- Review gas usage
- Review flash loan attack vectors
- Review reentrancy attack vectors
- Build Forta detection bots
- Upgrade to components for ERC20 and ERC721 once OZ contracts released
