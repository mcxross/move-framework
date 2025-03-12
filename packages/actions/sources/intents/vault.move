module account_actions::vault_intents;

// === Imports ===

use account_protocol::{
    account::{Account, Auth},
    executable::Executable,
    intents::Params,
    intent_interface,
};
use account_actions::{
    transfer::{Self as acc_transfer, TransferAction},
    vesting::{Self, VestAction},
    vault::{Self, SpendAction},
    version,
};

// === Aliases ===

use fun intent_interface::build_intent as Account.build_intent;
use fun intent_interface::process_intent as Account.process_intent;

// === Errors ===

const ENotSameLength: u64 = 0;
const EInsufficientFunds: u64 = 1;
const ECoinTypeDoesntExist: u64 = 2;
const ENotSameName: u64 = 3;

// === Structs ===

/// Intent Witness defining the vault spend and transfer intent, and associated role.
public struct SpendAndTransferIntent() has copy, drop;
/// Intent Witness defining the vault spend and vesting intent, and associated role.
public struct SpendAndVestIntent() has copy, drop;

// === Public Functions ===

/// Creates a SpendAndTransferIntent and adds it to an Account.
public fun request_spend_and_transfer<Config, Outcome: store, CoinType: drop>(
    auth: Auth,
    account: &mut Account<Config>, 
    params: Params,
    outcome: Outcome,
    spend_actions: vector<SpendAction<CoinType>>,
    transfer_actions: vector<TransferAction>,
    ctx: &mut TxContext
) {
    account.verify(auth);
    assert!(spend_actions.length() == transfer_actions.length(), ENotSameLength);
    assert!(spend_actions.all!(|spend_action| spend_action.name() == spend_actions[0].name()), ENotSameName);
    
    let vault = vault::borrow_vault(account, spend_actions[0].name());
    assert!(vault.coin_type_exists<CoinType>(), ECoinTypeDoesntExist);
    assert!(spend_actions.fold!(0, |sum, spend_action| sum + spend_action.amount()) <= vault.coin_type_value<CoinType>(), EInsufficientFunds);
    
    account.build_intent!(
        params,
        outcome,
        spend_actions[0].name(),
        version::current(),
        SpendAndTransferIntent(),
        ctx,
        |intent, iw| spend_actions.zip_do!(transfer_actions, |spend_action, transfer_action| {
            intent.add_action(spend_action, iw);
            intent.add_action(transfer_action, iw);
        })
    );
}

/// Executes a SpendAndTransferIntent, transfers coins from the vault to the recipients. Can be looped over.
public fun execute_spend_and_transfer<Config, Outcome: store, CoinType: drop>(
    executable: &mut Executable<Outcome>, 
    account: &mut Account<Config>, 
    ctx: &mut TxContext
) {
    account.process_intent!(
        executable,
        version::current(),
        SpendAndTransferIntent(),
        |executable, iw| {
            let coin = vault::do_spend<_, _, CoinType, _>(executable, account, version::current(), iw, ctx);
            acc_transfer::do_transfer(executable, coin, iw);
        }
    );
}

/// Creates a SpendAndVestIntent and adds it to an Account.
public fun request_spend_and_vest<Config, Outcome: store, CoinType: drop>(
    auth: Auth,
    account: &mut Account<Config>, 
    params: Params,
    outcome: Outcome,
    spend_action: SpendAction<CoinType>,
    vest_action: VestAction,
    ctx: &mut TxContext
) {
    account.verify(auth);
    params.assert_single_execution();

    let vault = vault::borrow_vault(account, spend_action.name());
    assert!(vault.coin_type_exists<CoinType>(), ECoinTypeDoesntExist);
    assert!(vault.coin_type_value<CoinType>() >= spend_action.amount(), EInsufficientFunds);

    account.build_intent!(
        params,
        outcome,
        spend_action.name(),
        version::current(),
        SpendAndVestIntent(),
        ctx,
        |intent, iw| {
            intent.add_action(spend_action, iw);
            intent.add_action(vest_action, iw);
        }
    );
}

/// Executes a SpendAndVestIntent, create a vesting from a coin in the vault.
public fun execute_spend_and_vest<Config, Outcome: store, CoinType: drop>(
    executable: &mut Executable<Outcome>, 
    account: &mut Account<Config>, 
    ctx: &mut TxContext
) {
    account.process_intent!(
        executable,
        version::current(),
        SpendAndVestIntent(),
        |executable, iw| {
            let coin = vault::do_spend<_, _, CoinType, _>(executable, account, version::current(), iw, ctx);
            vesting::do_vest(executable, coin, iw, ctx);
        }
    );
}