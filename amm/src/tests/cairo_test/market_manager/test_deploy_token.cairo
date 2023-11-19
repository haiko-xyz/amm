// Local imports.
use amm::tests::cairo_test::helpers::token::deploy_token;
use amm::tests::common::params::{token_params, treasury, ERC20ConstructorParams};
use amm::tests::common::utils::to_e28;

// External imports.
use openzeppelin::token::erc20::interface::{ERC20ABIDispatcher, ERC20ABIDispatcherTrait};

////////////////////////////////
// TESTS
////////////////////////////////

#[test]
#[available_gas(40000000)]
fn test_deploy_token_initialises_immutables() {
    // Deploy token.
    let params = token_params('USDC', 'USDC', to_e28(1000000000), treasury());
    let token = deploy_token(params);

    // Check immutables.
    assert(token.name() == params.name_, 'Deploy token: Wrong name');
    assert(token.symbol() == params.symbol_, 'Deploy token: Wrong symbol');
    assert(token.decimals() == 18, 'Deploy token: Wrong decimals');
    assert(token.total_supply() == params.initial_supply, 'Deploy token: Wrong init supply');
    assert(
        token.balance_of(params.recipient) == params.initial_supply,
        'Deploy token: Wrong recipient B'
    );
}
