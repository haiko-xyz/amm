// Core lib imports.
use traits::{Into, TryInto};
use option::OptionTrait;
use starknet::contract_address_const;
use starknet::ContractAddress;
use starknet::contract_address::ContractAddressZeroable;

// Local imports.
use amm::types::core::{Position, MarketConfigs, ValidLimits, Config};
use amm::types::i256::{i256, I256Trait};
use amm::libraries::constants::OFFSET;
use amm::tests::common::utils::to_e28;


////////////////////////////////
// TYPES
////////////////////////////////

#[derive(Drop, Copy)]
struct DeployParams {
    owner: ContractAddress,
}

#[derive(Drop, Copy)]
struct ERC20ConstructorParams {
    name_: felt252,
    symbol_: felt252,
    initial_supply: u256,
    recipient: ContractAddress
}

#[derive(Drop, Copy)]
struct CreateMarketParams {
    owner: ContractAddress,
    base_token: ContractAddress,
    quote_token: ContractAddress,
    width: u32,
    strategy: ContractAddress,
    swap_fee_rate: u16,
    fee_controller: ContractAddress,
    protocol_share: u16,
    start_limit: u32,
    controller: ContractAddress,
    market_configs: Option<MarketConfigs>,
}

#[derive(Drop, Copy)]
struct FeeControllerParams {
    market_manager: ContractAddress,
}

#[derive(Drop, Copy)]
struct ModifyPositionParams {
    owner: ContractAddress,
    market_id: felt252,
    lower_limit: u32,
    upper_limit: u32,
    liquidity_delta: i256,
}

#[derive(Drop, Copy)]
struct SwapParams {
    owner: ContractAddress,
    market_id: felt252,
    is_buy: bool,
    amount: u256,
    exact_input: bool,
    threshold_sqrt_price: Option<u256>,
    threshold_amount: Option<u256>,
    deadline: Option<u64>
}

#[derive(Drop, Copy)]
struct SwapMultipleParams {
    owner: ContractAddress,
    in_token: ContractAddress,
    out_token: ContractAddress,
    amount: u256,
    route: Span<felt252>,
    threshold_amount: Option<u256>,
    deadline: Option<u64>,
}

#[derive(Drop, Copy)]
struct TransferOwnerParams {
    owner: ContractAddress,
    new_owner: ContractAddress
}

////////////////////////////////
// CONSTANTS
////////////////////////////////

fn owner() -> ContractAddress {
    contract_address_const::<0x123456>()
}

fn treasury() -> ContractAddress {
    contract_address_const::<0x33333333>()
}

fn alice() -> ContractAddress {
    contract_address_const::<0xaaaaaaaa>()
}

fn bob() -> ContractAddress {
    contract_address_const::<0xbbbbbbbb>()
}

fn charlie() -> ContractAddress {
    contract_address_const::<0xcccccccc>()
}

////////////////////////////////
// PARAMETERS
////////////////////////////////

fn default_deploy_params() -> DeployParams {
    DeployParams { owner: owner() }
}

fn default_token_params() -> (ContractAddress, ERC20ConstructorParams, ERC20ConstructorParams) {
    let treasury = treasury();
    let base_params = token_params(
        'Ethereum', 'ETH', to_e28(5000000000000000000000000000000000000000000), treasury
    );
    let quote_params = token_params(
        'USDC', 'USDC', to_e28(100000000000000000000000000000000000000000000), treasury
    );
    (treasury, base_params, quote_params)
}

fn token_params(
    name_: felt252, symbol_: felt252, initial_supply: u256, recipient: ContractAddress
) -> ERC20ConstructorParams {
    ERC20ConstructorParams { name_, symbol_, initial_supply, recipient }
}

fn default_market_params() -> CreateMarketParams {
    CreateMarketParams {
        owner: owner(),
        base_token: ContractAddressZeroable::zero(), // Replaced with actual address on deployment
        quote_token: ContractAddressZeroable::zero(), // Replaced with actual address on deployment
        width: 1,
        swap_fee_rate: 30, // 0.3%
        fee_controller: ContractAddressZeroable::zero(), // Replaced with actual address on deployment
        strategy: ContractAddressZeroable::zero(), // Replaced with actual address on deployment
        protocol_share: 20, // 0.2%
        start_limit: OFFSET + 749558,
        controller: ContractAddressZeroable::zero(),
        market_configs: Option::None(())
    }
}

fn valid_limits(min_lower: u32, max_lower: u32, min_upper: u32, max_upper: u32) -> ValidLimits {
    ValidLimits { min_lower, max_lower, min_upper, max_upper }
}

fn config<T>(value: T, fixed: bool) -> Config<T> {
    Config { value, fixed }
}

fn default_transfer_owner_params() -> TransferOwnerParams {
    TransferOwnerParams { owner: owner(), new_owner: alice() }
}

fn fee_controller_params(
    market_manager: ContractAddress, swap_fee_rate: u16,
) -> FeeControllerParams {
    FeeControllerParams { market_manager, }
}

fn modify_position_params(
    owner: ContractAddress,
    market_id: felt252,
    lower_limit: u32,
    upper_limit: u32,
    liquidity_delta: i256,
) -> ModifyPositionParams {
    ModifyPositionParams { owner, market_id, lower_limit, upper_limit, liquidity_delta }
}

fn swap_params(
    owner: ContractAddress,
    market_id: felt252,
    is_buy: bool,
    exact_input: bool,
    amount: u256,
    threshold_sqrt_price: Option<u256>,
    threshold_amount: Option<u256>,
    deadline: Option<u64>
) -> SwapParams {
    SwapParams {
        owner,
        market_id,
        is_buy,
        exact_input,
        amount,
        threshold_sqrt_price,
        threshold_amount,
        deadline
    }
}

fn swap_multiple_params(
    owner: ContractAddress,
    in_token: ContractAddress,
    out_token: ContractAddress,
    amount: u256,
    route: Span<felt252>,
    threshold_amount: Option<u256>,
    deadline: Option<u64>,
) -> SwapMultipleParams {
    SwapMultipleParams { owner, in_token, out_token, amount, route, threshold_amount, deadline }
}
