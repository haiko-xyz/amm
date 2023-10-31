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
use amm::tests::helpers::params::{ERC20ConstructorParams, token_params, treasury};

// External imports.
use snforge_std::{declare, ContractClass, ContractClassTrait, start_prank, stop_prank};
use openzeppelin::token::erc20::erc20::ERC20;
use openzeppelin::token::erc20::interface::{IERC20, IERC20Dispatcher, IERC20DispatcherTrait};


fn declare_token() -> ContractClass {
    declare('ERC20')
}

fn deploy_token(class: ContractClass, params: ERC20ConstructorParams) -> IERC20Dispatcher {
    let mut constructor_calldata = ArrayTrait::<felt252>::new();
    params.name_.serialize(ref constructor_calldata);
    params.symbol_.serialize(ref constructor_calldata);
    params.initial_supply.serialize(ref constructor_calldata);
    params.recipient.serialize(ref constructor_calldata);
    let contract_address = class.deploy(@constructor_calldata).unwrap();
    IERC20Dispatcher { contract_address }
}

fn fund(token: IERC20Dispatcher, user: ContractAddress, amount: u256) {
    start_prank(token.contract_address, treasury());
    token.transfer(user, amount);
    stop_prank(token.contract_address);
}

fn approve(
    token: IERC20Dispatcher, owner: ContractAddress, spender: ContractAddress, amount: u256
) {
    start_prank(token.contract_address, owner);
    token.approve(spender, amount);
    stop_prank(token.contract_address);
}
