use starknet::ContractAddress;
use starknet::class_hash::ClassHash;

use amm::types::core::{
    MarketInfo, MarketState, MarketConfigs, OrderBatch, Position, LimitInfo, LimitOrder,
    ERC721PositionInfo
};
use amm::types::i128::i128;
use amm::types::i256::i256;

#[starknet::interface]
trait IMarketManager<TContractState> {
    ////////////////////////////////
    // VIEW
    ////////////////////////////////

    // Get contract owner.
    fn owner(self: @TContractState) -> ContractAddress;

    // Whether market is whitelisted for creation.
    fn is_market_whitelisted(self: @TContractState, market_id: felt252) -> bool;

    // Whether token is whitelisted (allows creation of unowned and non-strategy markets).
    fn is_token_whitelisted(self: @TContractState, token: ContractAddress) -> bool;

    // Get base token for market.
    fn base_token(self: @TContractState, market_id: felt252) -> ContractAddress;

    // Get quote token for market.
    fn quote_token(self: @TContractState, market_id: felt252) -> ContractAddress;

    // Get market width.
    fn width(self: @TContractState, market_id: felt252) -> u32;

    // Get market strategy.
    fn strategy(self: @TContractState, market_id: felt252) -> ContractAddress;

    // Get market fee controller.
    fn fee_controller(self: @TContractState, market_id: felt252) -> ContractAddress;

    // Get market swap fee rate.
    fn swap_fee_rate(self: @TContractState, market_id: felt252) -> u16;

    // Get market flash loan fee rate.
    fn flash_loan_fee_rate(self: @TContractState, token: ContractAddress) -> u16;

    // Get position info.
    fn position(
        self: @TContractState,
        market_id: felt252,
        owner: felt252,
        lower_limit: u32,
        upper_limit: u32
    ) -> Position;

    // Get order info.
    fn order(self: @TContractState, order_id: felt252) -> LimitOrder;

    // Get market id.
    fn market_id(
        self: @TContractState,
        base_token: ContractAddress,
        quote_token: ContractAddress,
        width: u32,
        strategy: ContractAddress,
        swap_fee_rate: u16,
        fee_controller: ContractAddress,
        controller: ContractAddress,
    ) -> felt252;

    // Get market info (immutable).
    fn market_info(self: @TContractState, market_id: felt252) -> MarketInfo;

    // Get market state (mutable).
    fn market_state(self: @TContractState, market_id: felt252) -> MarketState;

    // Get market configs (either fixed or upgradeable).
    fn market_configs(self: @TContractState, market_id: felt252) -> MarketConfigs;

    // Get limit order batch info.
    fn batch(self: @TContractState, batch_id: felt252) -> OrderBatch;

    // Get market liquidity.
    fn liquidity(self: @TContractState, market_id: felt252) -> u128;

    // Get market current limit.
    fn curr_limit(self: @TContractState, market_id: felt252) -> u32;

    // Get market current sqrt price.
    fn curr_sqrt_price(self: @TContractState, market_id: felt252) -> u256;

    // Get limit info.
    fn limit_info(self: @TContractState, market_id: felt252, limit: u32) -> LimitInfo;

    // Checks if limit is initialised.
    fn is_limit_init(self: @TContractState, market_id: felt252, width: u32, limit: u32) -> bool;

    // Fetches next initialised limit from a starting limit.
    fn next_limit(
        self: @TContractState, market_id: felt252, is_buy: bool, width: u32, start_limit: u32
    ) -> Option<u32>;

    // Get donations.
    fn donations(self: @TContractState, asset: ContractAddress) -> u256;

    // Get token reserves.
    fn reserves(self: @TContractState, asset: ContractAddress) -> u256;

    // Returns total amount of tokens and accrued fees inside of a liquidity position.
    // 
    // # Arguments
    // * `position_id` - position id
    //
    // # Returns
    // * `base_amount` - amount of base tokens inside position, exclusive of fees
    // * `quote_amount` - amount of quote tokens inside position, exclusive of fees
    // * `base_fees` - base fees accumulated inside position
    // * `quote_fees` - quote fees accumulated inside position
    fn amounts_inside_position(
        self: @TContractState, position_id: felt252,
    ) -> (u256, u256, u256, u256);

    // Returns total amount of tokens inside of a limit order.
    // 
    // # Arguments
    // * `order_id` - order id
    // * `market_id` - market id
    //
    // # Returns
    // * `base_amount` - amount of base tokens inside order
    // * `quote_amount` - amount of quote tokens inside order
    fn amounts_inside_order(
        self: @TContractState, order_id: felt252, market_id: felt252,
    ) -> (u256, u256);

    // Converts liquidity to base and quote token amounts.
    fn liquidity_to_amounts(
        self: @TContractState,
        market_id: felt252,
        lower_limit: u32,
        upper_limit: u32,
        liquidity_delta: u128,
    ) -> (u256, u256);

    // Converts token amount to liquidity.
    fn amount_to_liquidity(
        self: @TContractState, market_id: felt252, is_bid: bool, limit: u32, amount: u256,
    ) -> u128;

    // Returns information about ERC721 position.
    fn ERC721_position_info(self: @TContractState, token_id: felt252) -> ERC721PositionInfo;


    ////////////////////////////////
    // EXTERNAL
    ////////////////////////////////

    // Create a new market. 
    // 
    // # Arguments
    // * `base_token` - base token address
    // * `quote_token` - quote token address
    // * `width` - limit width of market
    // * `strategy` - strategy contract address, or 0 if no strategy
    // * `swap_fee_rate` - swap fee denominated in bps
    // * `flash_loan_fee` - flash loan fee denominated in bps
    // * `fee_controller` - fee controller contract address
    // * `start_limit` - initial limit (shifted)
    // * `controller` - market controller for upgrading market configs, or 0 if none
    // * `configs` - (optional) custom market configurations
    //
    // # Returns
    // * `market_id` - Market ID
    fn create_market(
        ref self: TContractState,
        base_token: ContractAddress,
        quote_token: ContractAddress,
        width: u32,
        strategy: ContractAddress,
        swap_fee_rate: u16,
        fee_controller: ContractAddress,
        start_limit: u32,
        controller: ContractAddress,
        configs: Option<MarketConfigs>,
    ) -> felt252;

    // Add or remove liquidity from a position, or collect fees by passing 0 as liquidity delta.
    //
    // # Arguments
    // * `market_id` - Market ID
    // * `lower_limit` - Lower limit at which position starts
    // * `upper_limit` - Higher limit at which position ends
    // * `liquidity_delta` - Amount of liquidity to add or remove
    //
    // # Returns
    // * `base_amount` - Amount of base tokens transferred in (+ve) or out (-ve), including fees
    // * `quote_amount` - Amount of quote tokens transferred in (+ve) or out (-ve), including fees
    // * `base_fees` - Amount of base tokens collected in fees
    // * `quote_fees` - Amount of quote tokens collected in fees
    fn modify_position(
        ref self: TContractState,
        market_id: felt252,
        lower_limit: u32,
        upper_limit: u32,
        liquidity_delta: i128,
    ) -> (i256, i256, u256, u256);

    // As with `modify_position`, but with a referrer.
    //
    // # Arguments
    // * `market_id` - Market ID
    // * `lower_limit` - Lower limit at which position starts
    // * `upper_limit` - Higher limit at which position ends
    // * `liquidity_delta` - Amount of liquidity to add or remove
    // * `referrer` - Referrer address
    //
    // # Returns
    // * `base_amount` - Amount of base tokens transferred in (+ve) or out (-ve), including fees
    // * `quote_amount` - Amount of quote tokens transferred in (+ve) or out (-ve), including fees
    // * `base_fees` - Amount of base tokens collected in fees
    // * `quote_fees` - Amount of quote tokens collected in fees
    fn modify_position_with_referrer(
        ref self: TContractState,
        market_id: felt252,
        lower_limit: u32,
        upper_limit: u32,
        liquidity_delta: i128,
        referrer: ContractAddress,
    ) -> (i256, i256, u256, u256);

    // Create a new limit order.
    // Must be placed below the current limit for bids, or above the current limit for asks.
    // 
    // # Arguments
    // * `market_id` - market id
    // * `is_bid` - whether bid order
    // * `limit` - limit at which order is placed
    // * `liquidity_delta` - amount of liquidity to add or remove
    //
    // # Returns
    // * `order_id` - order id
    fn create_order(
        ref self: TContractState,
        market_id: felt252,
        is_bid: bool,
        limit: u32,
        liquidity_delta: u128,
    ) -> felt252;

    // Collect a limit order.
    // Collects filled amount and refunds unfilled portion.
    // 
    // # Arguments
    // * `market_id` - market id
    // * `order_id` - order id
    //
    // # Returns
    // * `base_amount` - amount of base tokens collected
    // * `quote_amount` - amount of quote tokens collected
    fn collect_order(
        ref self: TContractState, market_id: felt252, order_id: felt252,
    ) -> (u256, u256);

    // Swap tokens through a market.
    //
    // # Arguments
    // * `market_id` - ID of market to execute swap through
    // * `is_buy` - whether swap is a buy or sell
    // * `amount` - amount of tokens to swap
    // * `exact_input` - true if `amount` is exact input, false if exact output
    // * `threshold_sqrt_price` - maximum sqrt price to swap at for buys, minimum for sells
    // * `threshold_amount` - minimum amount out for exact input, or max amount in for exact output
    // * `deadline` - deadline for swap to be executed by
    //
    // # Returns
    // * `amount_in` - amount of tokens swapped in gross of fees
    // * `amount_out` - amount of tokens swapped out net of fees
    // * `fees` - fees paid in token swapped in
    fn swap(
        ref self: TContractState,
        market_id: felt252,
        is_buy: bool,
        amount: u256,
        exact_input: bool,
        threshold_sqrt_price: Option<u256>,
        threshold_amount: Option<u256>,
        deadline: Option<u64>,
    ) -> (u256, u256, u256);

    // Swap tokens across multiple markets in a multi-hop route.
    // 
    // # Arguments
    // * `in_token` - in token address
    // * `out_token` - out token address
    // * `amount` - amount of tokens to swap in
    // * `route` - list of market ids defining the route to swap through
    // * `threshold_amount` - minimum amount out
    // * `deadline` - deadline for swap to be executed by
    //
    // # Returns
    // * `amount_out` - amount of tokens swapped out net of fees
    fn swap_multiple(
        ref self: TContractState,
        in_token: ContractAddress,
        out_token: ContractAddress,
        amount: u256,
        route: Span<felt252>,
        threshold_amount: Option<u256>,
        deadline: Option<u64>,
    ) -> u256;

    // Obtain quote for a swap between tokens (returned as panic message).
    // This is the safest way to obtain a quote as it does not rely on the strategy to
    // correctly report its queued and placed positions.
    // The first entry in the returned array is 'Quote' to distinguish it from other errors.
    //
    // # Arguments
    // * `market_id` - market id
    // * `is_buy` - whether swap is a buy or sell
    // * `amount` - amount of tokens to swap
    // * `exact_input` - true if `amount` is exact input, or false if exact output
    // 
    // # Returns (as panic message)
    // * `amount` - amount out (if exact input) or amount in (if exact output)
    fn quote(
        ref self: TContractState, market_id: felt252, is_buy: bool, amount: u256, exact_input: bool,
    );

    // Obtain quote for a swap across multiple markets in a multi-hop route.
    // Returned as error message. This is the safest way to obtain a quote as it does not rely on
    // the strategy to correctly report its queued and placed positions.
    // The first entry in the returned array is 'quote_multiple' to distinguish it from other errors.
    // 
    // # Arguments
    // * `in_token` - in token address
    // * `out_token` - out token address
    // * `amount` - amount of tokens to swap in
    // * `route` - list of market ids defining the route to swap through
    //
    // # Returns (as error message)
    // * `amount_out` - amount of tokens swapped out net of fees
    fn quote_multiple(
        ref self: TContractState,
        in_token: ContractAddress,
        out_token: ContractAddress,
        amount: u256,
        route: Span<felt252>,
    );

    // Obtain quote for a single swap.
    // Caution: this function returns a correct quote only so long as the strategy correctly
    // reports its queued and placed positions. This function is intended for use by on-chain
    // callers that cannot retrieve `quote` via error message. Alternatively, it can be used 
    // to obtain guaranteed correct quotes for non-strategy markets.
    //
    // # Arguments
    // * `market_id` - market id
    // * `is_buy` - whether swap is a buy or sell
    // * `amount` - amount of tokens to swap
    // * `exact_input` - true if `amount` is exact input, or false if exact output
    // * `ignore_strategy` - whether to ignore strategy positions when fetching quote
    //
    // # Returns
    // * `amount` - amount out (if exact input) or amount in (if exact output)
    fn unsafe_quote(
        self: @TContractState,
        market_id: felt252,
        is_buy: bool,
        amount: u256,
        exact_input: bool,
        ignore_strategy: bool,
    ) -> u256;

    // Obtain quote for a multi-market swap.
    // Caution: this function returns a correct quote only so long as the strategy correctly
    // reports its queued and placed positions. This function is intended for use by on-chain
    // callers that cannot retrieve `quote_multiple` via error message. Alternatively, it can 
    // be used to obtain guaranteed correct quotes for non-strategy markets.
    //
    // # Arguments
    // * `in_token` - in token address
    // * `out_token` - out token address
    // * `amount` - amount of tokens to swap in
    // * `route` - list of market ids defining the route to swap through
    // * `ignore_strategy` - whether to ignore strategy positions when fetching quote
    //
    // # Returns
    // * `amount_out` - amount of tokens swapped out net of fees
    fn unsafe_quote_multiple(
        self: @TContractState,
        in_token: ContractAddress,
        out_token: ContractAddress,
        amount: u256,
        route: Span<felt252>,
        ignore_strategy: bool,
    ) -> u256;

    // Initiates a flash loan.
    // Flash loan receiver must be a contract that implements `ILoanReceiver`.
    //
    // # Arguments
    // * `token` - contract address of the token borrowed
    // * `amount` - borrow amount requested
    fn flash_loan(ref self: TContractState, token: ContractAddress, amount: u256);

    // Mint ERC721 to represent an open liquidity position.
    //
    // # Arguments
    // * `position_id` - id of position mint
    fn mint(ref self: TContractState, position_id: felt252);

    // Burn ERC721 to unlock capital from open liquidity positions.
    //
    // # Arguments
    // * `position_id` - id of position to burn
    fn burn(ref self: TContractState, position_id: felt252);

    // Whitelist markets
    // Callable by owner only.
    //
    // # Arguments
    // * `market_ids` - array of market ids
    fn whitelist_markets(ref self: TContractState, market_ids: Array<felt252>);

    // Whitelist tokens.
    // Callable by owner only.
    //
    // # Arguments
    // * `tokens` - array of token addresses
    fn whitelist_tokens(ref self: TContractState, tokens: Array<ContractAddress>);

    // Sweeps excess tokens from contract.
    // Used to collect tokens sent to contract by mistake.
    //
    // # Arguments
    // * `receiver` - Recipient of swept tokens
    // * `token` - Token to sweep
    // * `amount` - Requested amount of token to sweep
    //
    // # Returns
    // * `amount_collected` - Amount of base token swept
    fn sweep(
        ref self: TContractState, receiver: ContractAddress, token: ContractAddress, amount: u256,
    ) -> u256;

    // Request transfer ownership of the contract.
    // Part 1 of 2 step process to transfer ownership.
    //
    // # Arguments
    // * `new_owner` - New owner of the contract
    fn transfer_owner(ref self: TContractState, new_owner: ContractAddress);

    // Called by new owner to accept ownership of the contract.
    // Part 2 of 2 step process to transfer ownership.
    fn accept_owner(ref self: TContractState);

    // Set flash loan fee rate.
    // Callable by owner only.
    //
    // # Arguments
    // * `token` - contract address of the token borrowed
    // * `fee` - flash loan fee denominated in bps
    fn set_flash_loan_fee_rate(ref self: TContractState, token: ContractAddress, fee: u16);

    // Set market configs.
    // Callable by market owner only. Enforces checks that each config is upgradeable.
    // 
    // # Arguments
    // * `market_id` - market id'
    // * `new_configs` - new market configs
    fn set_market_configs(ref self: TContractState, market_id: felt252, new_configs: MarketConfigs);

    // Upgrade contract class.
    // Callable by owner only.
    //
    // # Arguments
    // * `new_class_hash` - new class hash of contract
    fn upgrade(ref self: TContractState, new_class_hash: ClassHash);
}
