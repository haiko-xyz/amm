// Core lib imports.
use core::traits::AddEq;
use core::serde::Serde;
use starknet::ContractAddress;
use starknet::contract_address_const;
use starknet::deploy_syscall;
use starknet::testing::{set_caller_address, set_contract_address, set_block_timestamp};
use core::starknet::SyscallResultTrait;
use core::result::ResultTrait;
use option::OptionTrait;
use traits::TryInto;
use array::ArrayTrait;

// Local imports.
use amm::tests::common::params::{ERC20ConstructorParams, token_params, treasury};
use amm::contracts::erc20::ERC20;

// External imports.
use openzeppelin::token::erc20::interface::{ERC20ABIDispatcher, ERC20ABIDispatcherTrait};


fn deploy_token(params: ERC20ConstructorParams) -> ERC20ABIDispatcher {
    set_contract_address(treasury());
    let mut constructor_calldata = ArrayTrait::<felt252>::new();
    params.name_.serialize(ref constructor_calldata);
    params.symbol_.serialize(ref constructor_calldata);
    params.initial_supply.serialize(ref constructor_calldata);
    params.recipient.serialize(ref constructor_calldata);

    let (deployed_address, _) = deploy_syscall(
        ERC20::TEST_CLASS_HASH.try_into().unwrap(), 0, constructor_calldata.span(), false
    )
        .unwrap();

    ERC20ABIDispatcher { contract_address: deployed_address }
}

fn fund(token: ERC20ABIDispatcher, user: ContractAddress, amount: u256) {
    set_contract_address(treasury());
    token.transfer(user, amount);
}

fn approve(
    token: ERC20ABIDispatcher, owner: ContractAddress, spender: ContractAddress, amount: u256
) {
    set_contract_address(owner);
    token.approve(spender, amount);
}
