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
                    quote.print();
                    return quote.into();
                },
            }
        }
    }
}