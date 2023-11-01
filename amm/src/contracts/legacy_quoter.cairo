use starknet::ContractAddress;
use starknet::class_hash::ClassHash;

#[starknet::interface]
trait ILegacyQuoter<TContractState> {
    fn owner(self: @TContractState) -> ContractAddress;
    fn market_manager(self: @TContractState) -> ContractAddress;

    fn quote(
        self: @TContractState,
        market_id: felt252,
        is_buy: bool,
        amount: u256,
        exact_input: bool,
        threshold_sqrt_price: Option<u256>,
    ) -> u256;

    fn set_market_manager(ref self: TContractState, market_manager: ContractAddress);

    fn upgrade(ref self: TContractState, new_class_hash: ClassHash);
}


#[starknet::contract]
mod LegacyQuoter {
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
    use super::ILegacyQuoter;

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
    impl LegacyQuoter of ILegacyQuoter<ContractState> {
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
                entry_point_selector: selector!("simulate_swap"),
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

        // Update market manager.
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
