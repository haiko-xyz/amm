use starknet::contract_address_const;
use starknet::syscalls::call_contract_syscall;

use amm::interfaces::IQuoter::{IQuoterDispatcher, IQuoterDispatcherTrait};
use snforge_std::{declare, ContractClass, ContractClassTrait, PrintTrait};

#[test]
#[fork("TESTNET")]
fn test_quoter_using_forked_state() {
    let owner = 0x2afc579c1a02e4e36b2717bb664bee705d749d581e150d1dd16311e3b3bb057;
    let market_manager = contract_address_const::<
        0x48c1140f9e9599bdc24d98f1895d913d841aedc30a8fec93f0efd90a2b6b7b9
    >();
    let quoter = contract_address_const::<
        0x06f3afe508abfb5a7829409739c5f3a86f8b7f97d5b4f63dea272d78b842642f
    >();
    let market_id: felt252 = 0x59673e57a0626f73e7badd2f8abfe8b620ebaa54f192a9b3f44ca1b3e2dc1b5;
    let is_buy = true;
    let amount: u256 = 100000000000000000;
    let exact_input = true;
    let threshold_sqrt_price: Option<u256> = Option::None(());

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
    // let res = call_contract_syscall(
    //     address: market_manager,
    //     entry_point_selector: selector!("quote"),
    //     calldata: calldata.span(),
    // );
    // (*res.unwrap_err().at(1)).print();

    // Call `quote` in quoter.
    let res = call_contract_syscall(
        address: quoter, entry_point_selector: selector!("quote"), calldata: calldata.span(),
    );
    (*res.unwrap_err().at(1)).print();

    // // Extract quote from error message.
    // match res {
    //     Result::Ok(_) => {
    //         assert(false, 'QuoteResultOk');
    //         // return 0;
    //     },
    //     Result::Err(error) => {
    //         let quote = *error.at(0);
    //         quote.print();
    //         // return quote;
    //     },
    // };

    assert(true, 'success');
// let class_hash = 0x035d4743ec2fa7da2dd411db6e9b88a385b7ec0954f007901b260b6183c50014;
// let contract = ContractClass { class_hash: class_hash.try_into().unwrap() };
// let contract_address = contract.deploy(@array![owner.into(), market_manager.into()]).unwrap();
// let legacy_quoter = ILegacyQuoterDispatcher{ contract_address };

// let quote = legacy_quoter.quote(market_id, is_buy, amount, exact_input, threshold_sqrt_price);
// quote.print();
}
