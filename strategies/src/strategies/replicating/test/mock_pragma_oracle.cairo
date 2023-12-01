use strategies::strategies::replicating::pragma::{
    PragmaPricesResponse, DataType, AggregationMode, SimpleDataType
};

#[starknet::interface]
trait IMockPragmaOracle<TContractState> {
    fn get_data_with_USD_hop(
        self: @TContractState,
        base_currency_id: felt252,
        quote_currency_id: felt252,
        aggregation_mode: AggregationMode,
        typeof: SimpleDataType,
        expiration_timestamp: Option<u64>,
    ) -> PragmaPricesResponse;
    fn set_data_with_USD_hop(
        ref self: TContractState,
        base_currency_id: felt252,
        quote_currency_id: felt252,
        price: u128,
    );
    fn get_data_median(self: @TContractState, data_type: DataType) -> PragmaPricesResponse;
    fn set_data_median(ref self: TContractState, data_type: DataType, price: u128);
    fn calculate_volatility(
        self: @TContractState,
        data_type: DataType,
        start_tick: u64,
        end_tick: u64,
        num_samples: u64,
        aggregation_mode: AggregationMode
    ) -> (u128, u32);
    fn set_volatility(ref self: TContractState, pair_id: felt252, volatility: u128, decimals: u32,);
}

#[starknet::contract]
mod MockPragmaOracle {
    use super::IMockPragmaOracle;

    use strategies::strategies::replicating::pragma::{
        PragmaPricesResponse, DataType, AggregationMode, SimpleDataType
    };

    #[storage]
    struct Storage {
        usd_prices: LegacyMap::<felt252, u128>,
        prices: LegacyMap::<(felt252, felt252), u128>,
        volatility: LegacyMap::<felt252, (u128, u32)>,
    }

    #[external(v0)]
    impl MockPragmaOracle of IMockPragmaOracle<ContractState> {
        fn get_data_with_USD_hop(
            self: @ContractState,
            base_currency_id: felt252,
            quote_currency_id: felt252,
            aggregation_mode: AggregationMode,
            typeof: SimpleDataType,
            expiration_timestamp: Option<u64>,
        ) -> PragmaPricesResponse {
            let price = self.prices.read((base_currency_id, quote_currency_id));
            PragmaPricesResponse {
                price,
                decimals: 8,
                last_updated_timestamp: 1,
                num_sources_aggregated: 1,
                expiration_timestamp: Option::None(()),
            }
        }

        fn set_data_with_USD_hop(
            ref self: ContractState,
            base_currency_id: felt252,
            quote_currency_id: felt252,
            price: u128,
        ) {
            self.prices.write((base_currency_id, quote_currency_id), price);
        }

        fn get_data_median(self: @ContractState, data_type: DataType) -> PragmaPricesResponse {
            let price = match data_type {
                DataType::SpotEntry(x) => self.usd_prices.read(x),
                DataType::FutureEntry((x, y)) => self.usd_prices.read(x),
                DataType::GenericEntry(x) => self.usd_prices.read(x),
            };
            PragmaPricesResponse {
                price,
                decimals: 8,
                last_updated_timestamp: 1,
                num_sources_aggregated: 1,
                expiration_timestamp: Option::None(()),
            }
        }

        fn set_data_median(ref self: ContractState, data_type: DataType, price: u128) {
            match data_type {
                DataType::SpotEntry(x) => self.usd_prices.write(x, price),
                DataType::FutureEntry((x, y)) => self.usd_prices.write(x, price),
                DataType::GenericEntry(x) => self.usd_prices.write(x, price),
            }
        }

        fn calculate_volatility(
            self: @ContractState,
            data_type: DataType,
            start_tick: u64,
            end_tick: u64,
            num_samples: u64,
            aggregation_mode: AggregationMode
        ) -> (u128, u32) {
            match data_type {
                DataType::SpotEntry(x) => self.volatility.read(x),
                DataType::FutureEntry((x, y)) => self.volatility.read(x),
                DataType::GenericEntry(x) => self.volatility.read(x),
            }
        }

        fn set_volatility(
            ref self: ContractState, pair_id: felt252, volatility: u128, decimals: u32,
        ) {
            self.volatility.write(pair_id, (volatility, decimals));
        }
    }
}
