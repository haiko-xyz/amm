use strategies::strategies::replicating::types::{StrategyParams, OracleParams, StrategyState};

#[starknet::interface]
trait IStorePackingContract<TContractState> {
    fn get_strategy_params(self: @TContractState, market_id: felt252) -> StrategyParams;
    fn get_oracle_params(self: @TContractState, market_id: felt252) -> OracleParams;
    fn get_strategy_state(self: @TContractState, market_id: felt252) -> StrategyState;

    fn set_strategy_params(
        ref self: TContractState, market_id: felt252, strategy_params: StrategyParams
    );
    fn set_oracle_params(ref self: TContractState, market_id: felt252, oracle_params: OracleParams);
    fn set_strategy_state(
        ref self: TContractState, market_id: felt252, strategy_state: StrategyState
    );
}

#[starknet::contract]
mod StorePackingContract {
    use strategies::strategies::replicating::types::{StrategyParams, OracleParams, StrategyState};
    use strategies::strategies::replicating::store_packing::{
        StrategyParamsStorePacking, OracleParamsStorePacking, StrategyStateStorePacking,
    };
    use super::IStorePackingContract;

    ////////////////////////////////
    // STORAGE
    ////////////////////////////////

    #[storage]
    struct Storage {
        strategy_params: LegacyMap::<felt252, StrategyParams>,
        oracle_params: LegacyMap::<felt252, OracleParams>,
        strategy_state: LegacyMap::<felt252, StrategyState>,
    }

    #[constructor]
    fn constructor(ref self: ContractState,) {}

    #[abi(embed_v0)]
    impl StorePackingContract of IStorePackingContract<ContractState> {
        ////////////////////////////////
        // VIEW FUNCTIONS
        ////////////////////////////////

        fn get_strategy_params(self: @ContractState, market_id: felt252) -> StrategyParams {
            self.strategy_params.read(market_id)
        }

        fn get_oracle_params(self: @ContractState, market_id: felt252) -> OracleParams {
            self.oracle_params.read(market_id)
        }

        fn get_strategy_state(self: @ContractState, market_id: felt252) -> StrategyState {
            self.strategy_state.read(market_id)
        }

        ////////////////////////////////
        // EXTERNAL FUNCTIONS
        ////////////////////////////////

        fn set_strategy_params(
            ref self: ContractState, market_id: felt252, strategy_params: StrategyParams
        ) {
            self.strategy_params.write(market_id, strategy_params);
        }

        fn set_oracle_params(
            ref self: ContractState, market_id: felt252, oracle_params: OracleParams
        ) {
            self.oracle_params.write(market_id, oracle_params);
        }

        fn set_strategy_state(
            ref self: ContractState, market_id: felt252, strategy_state: StrategyState
        ) {
            self.strategy_state.write(market_id, strategy_state);
        }
    }
}
