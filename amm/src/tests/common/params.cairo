// Core lib imports.
use starknet::contract_address_const;
use starknet::ContractAddress;

// Local imports.
use amm::types::core::{Position, MarketConfigs, ValidLimits, Config};
use amm::types::i128::{i128, I128Trait};
use amm::libraries::constants::OFFSET;
use amm::tests::common::utils::to_e28;


////////////////////////////////
// TYPES
////////////////////////////////

#[derive(Drop, Copy)]
pub struct DeployParams {
    pub owner: ContractAddress,
}

#[derive(Drop, Copy)]
pub struct ERC20ConstructorParams {
    pub name_: felt252,
    pub symbol_: felt252,
    pub decimals: u8,
    pub initial_supply: u256,
    pub recipient: ContractAddress
}

#[derive(Drop, Copy)]
pub struct CreateMarketParams {
    pub owner: ContractAddress,
    pub base_token: ContractAddress,
    pub quote_token: ContractAddress,
    pub width: u32,
    pub strategy: ContractAddress,
    pub swap_fee_rate: u16,
    pub fee_controller: ContractAddress,
    pub start_limit: u32,
    pub controller: ContractAddress,
    pub market_configs: Option<MarketConfigs>,
}

#[derive(Drop, Copy)]
pub struct FeeControllerParams {
    pub market_manager: ContractAddress,
}

#[derive(Drop, Copy)]
pub struct ModifyPositionParams {
    pub owner: ContractAddress,
    pub market_id: felt252,
    pub lower_limit: u32,
    pub upper_limit: u32,
    pub liquidity_delta: i128,
}

#[derive(Drop, Copy)]
pub struct SwapParams {
    pub owner: ContractAddress,
    pub market_id: felt252,
    pub is_buy: bool,
    pub amount: u256,
    pub exact_input: bool,
    pub threshold_sqrt_price: Option<u256>,
    pub threshold_amount: Option<u256>,
    pub deadline: Option<u64>
}

#[derive(Drop, Copy)]
pub struct SwapMultipleParams {
    pub owner: ContractAddress,
    pub in_token: ContractAddress,
    pub out_token: ContractAddress,
    pub amount: u256,
    pub route: Span<felt252>,
    pub threshold_amount: Option<u256>,
    pub deadline: Option<u64>,
}

#[derive(Drop, Copy)]
pub struct TransferOwnerParams {
    pub owner: ContractAddress,
    pub new_owner: ContractAddress
}

////////////////////////////////
// CONSTANTS
////////////////////////////////

pub fn owner() -> ContractAddress {
    contract_address_const::<0x123456>()
}

pub fn treasury() -> ContractAddress {
    contract_address_const::<0x33333333>()
}

pub fn alice() -> ContractAddress {
    contract_address_const::<0xaaaaaaaa>()
}

pub fn bob() -> ContractAddress {
    contract_address_const::<0xbbbbbbbb>()
}

pub fn charlie() -> ContractAddress {
    contract_address_const::<0xcccccccc>()
}

////////////////////////////////
// PARAMETERS
////////////////////////////////

pub fn default_deploy_params() -> DeployParams {
    DeployParams { owner: owner() }
}

pub fn default_token_params() -> (ContractAddress, ERC20ConstructorParams, ERC20ConstructorParams) {
    let treasury = treasury();
    let base_params = token_params(
        'Ethereum', 'ETH', 18, to_e28(5000000000000000000000000000000000000000000), treasury
    );
    let quote_params = token_params(
        'USDC', 'USDC', 18, to_e28(100000000000000000000000000000000000000000000), treasury
    );
    (treasury, base_params, quote_params)
}

pub fn token_params(
    name_: felt252, symbol_: felt252, decimals: u8, initial_supply: u256, recipient: ContractAddress
) -> ERC20ConstructorParams {
    ERC20ConstructorParams { name_, symbol_, decimals, initial_supply, recipient }
}

pub fn default_market_params() -> CreateMarketParams {
    CreateMarketParams {
        owner: owner(),
        base_token: contract_address_const::<0x0>(), // Replaced with actual address on deployment
        quote_token: contract_address_const::<0x0>(), // Replaced with actual address on deployment
        width: 1,
        swap_fee_rate: 30, // 0.3%
        fee_controller: contract_address_const::<
            0x0
        >(), // Replaced with actual address on deployment
        strategy: contract_address_const::<0x0>(), // Replaced with actual address on deployment
        start_limit: OFFSET + 749558,
        controller: contract_address_const::<0x0>(),
        market_configs: Option::None(())
    }
}

pub fn valid_limits(
    min_lower: u32, max_lower: u32, min_upper: u32, max_upper: u32, min_width: u32, max_width: u32
) -> ValidLimits {
    ValidLimits { min_lower, max_lower, min_upper, max_upper, min_width, max_width }
}

pub fn config<T>(value: T, fixed: bool) -> Config<T> {
    Config { value, fixed }
}

pub fn default_transfer_owner_params() -> TransferOwnerParams {
    TransferOwnerParams { owner: owner(), new_owner: alice() }
}

pub fn fee_controller_params(
    market_manager: ContractAddress, swap_fee_rate: u16,
) -> FeeControllerParams {
    FeeControllerParams { market_manager, }
}

pub fn modify_position_params(
    owner: ContractAddress,
    market_id: felt252,
    lower_limit: u32,
    upper_limit: u32,
    liquidity_delta: i128,
) -> ModifyPositionParams {
    ModifyPositionParams { owner, market_id, lower_limit, upper_limit, liquidity_delta }
}

pub fn swap_params(
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

pub fn swap_multiple_params(
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
