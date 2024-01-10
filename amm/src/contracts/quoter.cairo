#[starknet::contract]
mod Quoter {
    ////////////////////////////////
    // IMPORTS
    ////////////////////////////////

    // Core lib imports.
    use core::array::ArrayTrait;
    use starknet::syscalls::call_contract_syscall;
    use starknet::ContractAddress;
    use starknet::info::get_caller_address;
    use starknet::replace_class_syscall;
    use starknet::class_hash::ClassHash;

    // Local imports.
    use amm::interfaces::{
        IMarketManager::{IMarketManagerDispatcher, IMarketManagerDispatcherTrait}, IQuoter::IQuoter
    };

    // Third party imports.
    use openzeppelin::token::erc20::interface::{ERC20ABIDispatcher, ERC20ABIDispatcherTrait};

    ////////////////////////////////
    // STORAGE
    ////////////////////////////////

    #[storage]
    struct Storage {
        owner: ContractAddress,
        market_manager: ContractAddress,
    }

    ////////////////////////////////
    // CONSTRUCTOR
    ////////////////////////////////

    #[constructor]
    fn constructor(
        ref self: ContractState, owner: ContractAddress, market_manager: ContractAddress
    ) {
        self.owner.write(owner);
        self.market_manager.write(market_manager);
    }

    #[generate_trait]
    impl ModifierImpl of ModifierTrait {
        fn assert_only_owner(self: @ContractState) {
            assert(self.owner.read() == get_caller_address(), 'OnlyOwner')
        }
    }

    #[external(v0)]
    impl Quoter of IQuoter<ContractState> {
        // Get owner.
        //
        // # Returns
        // * `owner` - owner address
        fn owner(self: @ContractState) -> ContractAddress {
            return self.owner.read();
        }

        // Get market manager.
        //
        // # Returns
        // * `market_manager` - market manager address
        fn market_manager(self: @ContractState) -> ContractAddress {
            return self.market_manager.read();
        }

        // Obtain quote for a swap.
        //
        // # Arguments
        // * `market_id` - market ID
        // * `is_buy` - whether swap is a buy or sell
        // * `amount` - amount of tokens to swap in
        // * `exact_input` - true if `amount` is exact input, otherwise exact output
        //
        // # Returns
        // * `amount` - quoted amount out if exact input, quoted amount in if exact output
        fn quote(
            self: @ContractState, market_id: felt252, is_buy: bool, amount: u256, exact_input: bool,
        ) -> u256 {
            // Compile calldata.
            let mut calldata = array![];
            calldata.append(market_id);
            calldata.append(is_buy.into());
            calldata.append(amount.low.into());
            calldata.append(amount.high.into());
            calldata.append(exact_input.into());

            // Call `quote` in market manager.
            let res = call_contract_syscall(
                address: self.market_manager.read(),
                entry_point_selector: selector!("quote"),
                calldata: calldata.span(),
            );

            // Extract quote from error message.
            match res {
                Result::Ok(_) => {
                    assert(false, 'QuoteResultOk');
                    return 0;
                },
                Result::Err(error) => {
                    let quote_msg = *error.at(0);
                    assert(quote_msg == 'quote', 'QuoteInvalid');
                    let low: u128 = (*error.at(1)).try_into().expect('QuoteLowOF');
                    let high: u128 = (*error.at(2)).try_into().expect('QuoteHighOF');
                    u256 { low, high }
                },
            }
        }

        // Obtain quotes for a list of swaps.
        // Caution: this function returns correct quotes only so long as the strategy correctly
        // reports its queued and placed positions. This function is intended for use by on-chain
        // callers that cannot retrieve `quote` via error message. Alternatively, it can be used 
        // to obtain guaranteed correct quotes for non-strategy markets.
        //
        // # Arguments
        // * `market_ids` - list of market ids
        // * `is_buy` - whether swap is a buy or sell
        // * `amount` - amount of tokens to swap in
        // * `exact_input` - true if `amount` is exact input, otherwise exact output
        //
        // # Returns
        // * `amounts` - list of quoted amounts
        fn unsafe_quote_array(
            self: @ContractState,
            market_ids: Span<felt252>,
            is_buy: bool,
            amount: u256,
            exact_input: bool
        ) -> Span<u256> {
            let mut i = 0;
            let mut quotes: Array<u256> = array![];
            loop {
                if i == market_ids.len() {
                    break;
                }
                let dispatcher = IMarketManagerDispatcher {
                    contract_address: self.market_manager.read()
                };
                quotes
                    .append(
                        dispatcher
                            .unsafe_quote(*market_ids.at(i), is_buy, amount, exact_input, false)
                    );
                i += 1;
            };
            quotes.span()
        }

        // Obtain quote for a multi-market swap.
        //
        // # Arguments
        // * `in_token` - in token address
        // * `out_token` - out token address
        // * `amount` - amount of tokens to swap in
        // * `route` - list of market ids defining the route to swap through
        //
        // # Returns
        // * `amount` - quoted amount out
        fn quote_multiple(
            self: @ContractState,
            in_token: ContractAddress,
            out_token: ContractAddress,
            amount: u256,
            route: Span<felt252>,
        ) -> u256 {
            // Compile calldata.
            let mut calldata = array![];
            calldata.append(in_token.into());
            calldata.append(out_token.into());
            calldata.append(amount.low.into());
            calldata.append(amount.high.into());
            calldata.append(route.len().into());
            let mut i = 0;
            loop {
                if i == route.len() {
                    break;
                }
                calldata.append(*route.at(i));
                i += 1;
            };

            // Call `quote_multiple` in market manager.
            let res = call_contract_syscall(
                address: self.market_manager.read(),
                entry_point_selector: selector!("quote_multiple"),
                calldata: calldata.span(),
            );

            // Extract quote from error message.
            match res {
                Result::Ok(_) => {
                    assert(false, 'QuoteResultOk');
                    return 0;
                },
                Result::Err(error) => {
                    let quote_msg = *error.at(0);
                    assert(quote_msg == 'quote_multiple', 'QuoteInvalid');
                    let low: u128 = (*error.at(1)).try_into().expect('QuoteLowOF');
                    let high: u128 = (*error.at(2)).try_into().expect('QuoteHighOF');
                    u256 { low, high }
                },
            }
        }

        // Obtain quotes for a list of multi-market swaps.
        // Caution: this function returns correct quotes only so long as the strategy correctly
        // reports its queued and placed positions. This function is intended for use by on-chain
        // callers that cannot retrieve `quote` via error message. Alternatively, it can be used 
        // to obtain guaranteed correct quotes for non-strategy markets.
        //
        // # Arguments
        // * `in_token` - in token address
        // * `out_token` - out token address
        // * `amount` - amount of tokens to swap in
        // * `routes` - list of routes to swap through
        // * `route_lens` - length of each swap route
        //
        // # Returns
        // * `amounts` - list of quoted amounts
        fn unsafe_quote_multiple_array(
            self: @ContractState,
            in_token: ContractAddress,
            out_token: ContractAddress,
            amount: u256,
            routes: Span<felt252>,
            route_lens: Span<u8>,
        ) -> Span<u256> {
            // Initialise array to collect quotes.
            let mut quotes: Array<u256> = array![];

            // Loop through routes and obtain quote.
            let mut i = 0;
            let mut j = 0;
            let mut route_end: u32 = (*route_lens.at(j)).into() - 1;
            let mut route: Array<felt252> = array![];
            loop {
                if i == routes.len() {
                    break;
                }
                route.append(*routes.at(i));
                if i == route_end {
                    let dispatcher = IMarketManagerDispatcher {
                        contract_address: self.market_manager.read()
                    };
                    let quote = dispatcher
                        .unsafe_quote_multiple(in_token, out_token, amount, route.span(), false);
                    quotes.append(quote);
                    // Move to next quote and reset array.
                    if j != route_lens.len() - 1 {
                        j += 1;
                        route_end += (*route_lens.at(j)).into();
                        route = array![];
                    }
                }
                i += 1;
            };

            // Return quotes
            quotes.span()
        }

        // Proxies call to token amounts (including accrued fees) inside a list of liquidity positions.
        // 
        // # Arguments
        // * `position_ids` - list of position ids
        //
        // # Returns
        // * `base_amount` - amount of base tokens inside position, exclusive of fees
        // * `quote_amount` - amount of quote tokens inside position, exclusive of fees
        // * `base_fees` - base fees accumulated inside position
        // * `quote_fees` - quote fees accumulated inside position
        fn amounts_inside_position_array(
            self: @ContractState, position_ids: Span<felt252>
        ) -> Span<(u256, u256, u256, u256)> {
            let mut i = 0;
            let mut amounts: Array<(u256, u256, u256, u256)> = array![];
            let dispatcher = IMarketManagerDispatcher {
                contract_address: self.market_manager.read()
            };
            loop {
                if i == position_ids.len() {
                    break;
                }
                amounts.append(dispatcher.amounts_inside_position(*position_ids.at(i)));
                i += 1;
            };
            amounts.span()
        }

        // Proxies call to fetch token amounts accrued inside a list of limit orders.
        // 
        // # Arguments
        // * `order_ids` - list of position ids
        // * `market_ids` - list of market ids
        //
        // # Returns
        // * `base_amount` - amount of base tokens inside order
        // * `quote_amount` - amount of quote tokens inside order
        fn amounts_inside_order_array(
            self: @ContractState, order_ids: Span<felt252>, market_ids: Span<felt252>
        ) -> Span<(u256, u256)> {
            assert(order_ids.len() == market_ids.len(), 'LengthMismatch');

            let mut i = 0;
            let mut amounts: Array<(u256, u256)> = array![];
            let dispatcher = IMarketManagerDispatcher {
                contract_address: self.market_manager.read()
            };
            loop {
                if i == order_ids.len() {
                    break;
                }
                amounts
                    .append(dispatcher.amounts_inside_order(*order_ids.at(i), *market_ids.at(i)));
                i += 1;
            };
            amounts.span()
        }

        // Proxies call to query token balances of a user.
        // 
        // # Arguments
        // * `user` - target user
        // * `tokens` - list of tokens
        //
        // # Returns
        // * `balances` - token balances of user
        fn token_balance_array(
            self: @ContractState, user: ContractAddress, tokens: Span<ContractAddress>
        ) -> Span<(u256, u8)> {
            let mut i = 0;
            let mut balances: Array<(u256, u8)> = array![];
            loop {
                if i == tokens.len() {
                    break;
                }
                let dispatcher = ERC20ABIDispatcher { contract_address: *tokens.at(i) };
                let balance = dispatcher.balance_of(user);
                let decimals = dispatcher.decimals();
                balances.append((balance, decimals));
                i += 1;
            };
            balances.span()
        }

        // Set market manager.
        //
        // # Arguments
        // * `market_manager` - market manager address
        fn set_market_manager(ref self: ContractState, market_manager: ContractAddress) {
            self.assert_only_owner();
            self.market_manager.write(market_manager);
        }

        // Upgrade contract class.
        // Callable by owner only.
        //
        // # Arguments
        // # `new_class_hash` - New class hash of the contract
        fn upgrade(ref self: ContractState, new_class_hash: ClassHash) {
            self.assert_only_owner();
            replace_class_syscall(new_class_hash);
        }
    }
}
