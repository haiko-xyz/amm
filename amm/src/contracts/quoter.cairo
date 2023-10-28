#[starknet::contract]
mod Quoter {
    ////////////////////////////////
    // IMPORTS
    ////////////////////////////////

    // Core lib imports.
    use core::array::ArrayTrait;
    use starknet::syscalls::call_contract_syscall;
    use starknet::ContractAddress;
    use debug::PrintTrait;

    // Local imports.
    use amm::interfaces::IQuoter::IQuoter;

    ////////////////////////////////
    // STORAGE
    ////////////////////////////////

    #[storage]
    struct Storage {
        market_manager: ContractAddress,
    }

    ////////////////////////////////
    // CONSTRUCTOR
    ////////////////////////////////

    #[constructor]
    fn constructor(ref self: ContractState, market_manager: ContractAddress) {
        self.market_manager.write(market_manager);
    }

    #[external(v0)]
    impl Quoter of IQuoter<ContractState> {

        // Obtain quote for a swap.
        //
        // # Arguments
        // * `market_id` - market ID
        // * `is_buy` - whether swap is a buy or sell
        // * `amount` - amount of tokens to swap in
        // * `exact_input` - true if `amount` is exact input, otherwise exact output
        // * `threshold_sqrt_price` - maximum sqrt price to swap at for buys, minimum for sells
        //
        // # Returns
        // * `amount` - quoted amount out if exact input, quoted amount in if exact output
        fn quote(
            self: @ContractState,
            market_id: felt252,
            is_buy: bool,
            amount: u256,
            exact_input: bool,
            threshold_sqrt_price: Option<u256>,
        ) -> u256 {
            // Compile calldata.
            let mut calldata = array![];
            calldata.append(market_id);
            calldata.append(is_buy.into());
            calldata.append(amount.low.into());
            calldata.append(amount.high.into());
            calldata.append(exact_input.into());
            match threshold_sqrt_price {
                Option::Some(threshold_sqrt_price) => {
                    calldata.append(0);
                    calldata.append(threshold_sqrt_price.low.into());
                    calldata.append(threshold_sqrt_price.high.into());
                },
                Option::None => calldata.append(1),
            };

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
                    let quote = *error.at(0);
                    return quote.into();
                },
            }
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
                    let quote = *error.at(0);
                    return quote.into();
                },
            }
        }
    }
}