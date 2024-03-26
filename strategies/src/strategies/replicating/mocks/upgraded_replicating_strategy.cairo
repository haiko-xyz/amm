use starknet::ContractAddress;

#[starknet::interface]
pub trait IUpgradedReplicatingStrategy<TContractState> {
    fn foo(self: @TContractState) -> u32;
}

#[starknet::contract]
pub mod UpgradedReplicatingStrategy {
    use super::IUpgradedReplicatingStrategy;

    ////////////////////////////////
    // STORAGE
    ////////////////////////////////

    #[storage]
    struct Storage {
        foo: u32,
    }

    ////////////////////////////////
    // CONSTRUCTOR
    ////////////////////////////////

    #[abi(embed_v0)]
    impl UpgradedReplicatingStrategy of IUpgradedReplicatingStrategy<ContractState> {
        ////////////////////////////////
        // VIEW FUNCTIONS
        ////////////////////////////////

        fn foo(self: @ContractState) -> u32 {
            self.foo.read()
        }
    }
}
