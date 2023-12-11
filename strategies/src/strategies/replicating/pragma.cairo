use starknet::ContractAddress;
use starknet::class_hash::ClassHash;
use array::ArrayTrait;

const MEDIAN: felt252 = 'MEDIAN'; // str_to_felt("MEDIAN")
const SPOT: felt252 = 'SPOT';
const FUTURE: felt252 = 'FUTURE';
const GENERIC: felt252 = 'GENERIC';
const OPTION: felt252 = 'OPTION';
const BOTH_TRUE: felt252 = 2;
const USD_CURRENCY_ID: felt252 = 'USD';


#[derive(Copy, Drop, Serde, starknet::Store)]
struct BaseEntry {
    timestamp: u64,
    source: felt252,
    publisher: felt252,
}

#[derive(Serde, Drop, Copy)]
struct GenericEntryStorage {
    timestamp__value: u256,
}

#[derive(Copy, Drop, Serde)]
struct SpotEntry {
    base: BaseEntry,
    price: u128,
    pair_id: felt252,
    volume: u128,
}
#[derive(Copy, Drop, Serde)]
struct GenericEntry {
    base: BaseEntry,
    key: felt252,
    value: u128,
}

#[derive(Copy, Drop, PartialOrd, Serde)]
struct FutureEntry {
    base: BaseEntry,
    price: u128,
    pair_id: felt252,
    volume: u128,
    expiration_timestamp: u64,
}

#[derive(Serde, Drop, Copy)]
struct OptionEntry {
    base: BaseEntry,
    rawParameters: rawSVI,
    essviParameters: eSSVI,
    forwardPrice: u256,
    strikePrice: u256,
    expirationTimestamp: u64,
}

#[derive(Serde, Drop, Copy)]
struct rawSVI {
    a: u256,
    b: u256,
    rho: u256,
    m: u256,
    sigma: u256,
    decimals: u32
}

#[derive(Serde, Drop, Copy)]
struct eSSVI {
    theta: u256,
    rho: u256,
    phi: u256
}


#[derive(Serde, Drop, Copy)]
struct EntryStorage {
    timestamp: u64,
    volume: u128,
    price: u128,
}


/// Data Types
/// The value is the `pair_id` of the data
/// For future option, pair_id and expiration timestamp
///
/// * `Spot` - Spot price
/// * `Future` - Future price
/// * `Option` - Option price
#[derive(Drop, Copy, Serde)]
enum DataType {
    SpotEntry: felt252,
    FutureEntry: (felt252, u64),
    GenericEntry: felt252,
// OptionEntry: (felt252, felt252),
}

#[derive(Drop, Copy)]
enum PossibleEntryStorage {
    Spot: u256, //structure SpotEntryStorage
    Future: u256, //structure FutureEntryStorage
//  Option: OptionEntryStorage, //structure OptionEntryStorage
}

#[derive(Drop, Copy, Serde)]
enum SimpleDataType {
    SpotEntry: (),
    FutureEntry: (),
//  OptionEntry: (),
}

#[derive(Drop, Copy, Serde)]
enum PossibleEntries {
    Spot: SpotEntry,
    Future: FutureEntry,
    Generic: GenericEntry,
//  Option: OptionEntry,
}


enum ArrayEntry {
    SpotEntry: Array<SpotEntry>,
    FutureEntry: Array<FutureEntry>,
    GenericEntry: Array<GenericEntry>,
//  OptionEntry: Array<OptionEntry>,
}


#[derive(Serde, Drop, Copy, starknet::Store)]
struct Pair {
    id: felt252, // same as key currently (e.g. str_to_felt("ETH/USD") - force uppercase)
    quote_currency_id: felt252, // currency id - str_to_felt encode the ticker
    base_currency_id: felt252, // currency id - str_to_felt encode the ticker
}

#[derive(Serde, Drop, Copy, starknet::Store)]
struct Currency {
    id: felt252,
    decimals: u32,
    is_abstract_currency: bool, // True (1) if not a specific token but abstract, e.g. USD or ETH as a whole
    starknet_address: ContractAddress, // optional, e.g. can have synthetics for non-bridged assets
    ethereum_address: ContractAddress, // optional
}

#[derive(Serde, Drop)]
struct Checkpoint {
    timestamp: u64,
    value: u128,
    aggregation_mode: AggregationMode,
    num_sources_aggregated: u32,
}

#[derive(Serde, Drop, Copy, starknet::Store)]
struct FetchCheckpoint {
    pair_id: felt252,
    type_of: felt252,
    index: u64,
    expiration_timestamp: u64,
    aggregation_mode: u8,
}

#[derive(Serde, Drop, Copy)]
struct PragmaPricesResponse {
    price: u128,
    decimals: u32,
    last_updated_timestamp: u64,
    num_sources_aggregated: u32,
    expiration_timestamp: Option<u64>,
}

#[derive(Serde, Drop, Copy)]
enum AggregationMode {
    Median: (),
    Mean: (),
    Error: (),
}

#[starknet::interface]
trait IOracleABI<TContractState> {
    fn get_decimals(self: @TContractState, data_type: DataType) -> u32;
    fn get_data_median(self: @TContractState, data_type: DataType) -> PragmaPricesResponse;
    fn get_data_median_for_sources(
        self: @TContractState, data_type: DataType, sources: Span<felt252>
    ) -> PragmaPricesResponse;
    fn get_data(
        self: @TContractState, data_type: DataType, aggregation_mode: AggregationMode
    ) -> PragmaPricesResponse;
    fn get_data_median_multi(
        self: @TContractState, data_types: Span<DataType>, sources: Span<felt252>
    ) -> Span<PragmaPricesResponse>;
    fn get_data_entry(
        self: @TContractState, data_type: DataType, source: felt252
    ) -> PossibleEntries;
    fn get_data_for_sources(
        self: @TContractState,
        data_type: DataType,
        aggregation_mode: AggregationMode,
        sources: Span<felt252>
    ) -> PragmaPricesResponse;
    fn get_data_entries(self: @TContractState, data_type: DataType) -> Span<PossibleEntries>;
    fn get_data_entries_for_sources(
        self: @TContractState, data_type: DataType, sources: Span<felt252>
    ) -> (Span<PossibleEntries>, u64);
    fn get_last_checkpoint_before(
        self: @TContractState,
        data_type: DataType,
        timestamp: u64,
        aggregation_mode: AggregationMode,
    ) -> (Checkpoint, u64);
    fn get_data_with_USD_hop(
        self: @TContractState,
        base_currency_id: felt252,
        quote_currency_id: felt252,
        aggregation_mode: AggregationMode,
        typeof: SimpleDataType,
        expiration_timestamp: Option::<u64>
    ) -> PragmaPricesResponse;
    fn get_publisher_registry_address(self: @TContractState) -> ContractAddress;
    fn get_latest_checkpoint_index(
        self: @TContractState, data_type: DataType, aggregation_mode: AggregationMode
    ) -> (u64, bool);
    fn get_latest_checkpoint(
        self: @TContractState, data_type: DataType, aggregation_mode: AggregationMode
    ) -> Checkpoint;
    fn get_checkpoint(
        self: @TContractState,
        data_type: DataType,
        checkpoint_index: u64,
        aggregation_mode: AggregationMode
    ) -> Checkpoint;
    fn get_sources_threshold(self: @TContractState,) -> u32;
    fn get_admin_address(self: @TContractState,) -> ContractAddress;
    fn get_implementation_hash(self: @TContractState) -> ClassHash;
    fn publish_data(ref self: TContractState, new_entry: PossibleEntries);
    fn publish_data_entries(ref self: TContractState, new_entries: Span<PossibleEntries>);
    fn set_admin_address(ref self: TContractState, new_admin_address: ContractAddress);
    fn update_publisher_registry_address(
        ref self: TContractState, new_publisher_registry_address: ContractAddress
    );
    fn add_currency(ref self: TContractState, new_currency: Currency);
    fn update_currency(ref self: TContractState, currency_id: felt252, currency: Currency);
    fn add_pair(ref self: TContractState, new_pair: Pair);
    fn set_checkpoint(
        ref self: TContractState, data_type: DataType, aggregation_mode: AggregationMode
    );
    fn set_checkpoints(
        ref self: TContractState, data_types: Span<DataType>, aggregation_mode: AggregationMode
    );
    fn set_sources_threshold(ref self: TContractState, threshold: u32);
    fn upgrade(ref self: TContractState, impl_hash: ClassHash);
}

#[starknet::interface]
trait ISummaryStatsABI<TContractState> {
    fn calculate_mean(
        self: @TContractState,
        data_type: DataType,
        start: u64,
        stop: u64,
        aggregation_mode: AggregationMode
    ) -> (u128, u32);

    fn calculate_volatility(
        self: @TContractState,
        data_type: DataType,
        start_tick: u64,
        end_tick: u64,
        num_samples: u64,
        aggregation_mode: AggregationMode
    ) -> (u128, u32);

    fn calculate_twap(
        self: @TContractState,
        data_type: DataType,
        aggregation_mode: AggregationMode,
        time: u64,
        start_time: u64,
    ) -> (u128, u32);


    fn get_oracle_address(self: @TContractState) -> ContractAddress;
}
