module account_actions::currency_intents;

// === Imports ===

use std::{
    type_name,
    string::String,
};
use sui::{
    transfer::Receiving,
    coin::{Coin, CoinMetadata},
};
use account_protocol::{
    account::{Account, Auth},
    executable::Executable,
    intents::Params,
    owned::{Self, WithdrawAction},
    intent_interface
};
use account_actions::{
    transfer::{Self as acc_transfer, TransferAction},
    vesting::{Self, VestAction},
    version,
    currency::{Self, DisableAction, UpdateAction, MintAction, BurnAction},
};

// === Aliases ===

use fun intent_interface::build_intent as Account.build_intent;
use fun intent_interface::process_intent as Account.process_intent;

// === Errors ===

const EAmountsRecipentsNotSameLength: u64 = 0;
const EMaxSupply: u64 = 1;

// === Structs ===

/// Intent Witness defining the intent to disable one or more permissions.
public struct DisableRulesIntent() has copy, drop;
/// Intent Witness defining the intent to update the CoinMetadata associated with a locked TreasuryCap.
public struct UpdateMetadataIntent() has copy, drop;
/// Intent Witness defining the intent to transfer a minted coin.
public struct MintAndTransferIntent() has copy, drop;
/// Intent Witness defining the intent to pay from a minted coin.
public struct MintAndVestIntent() has copy, drop;
/// Intent Witness defining the intent to burn coins from the account using a locked TreasuryCap.
public struct WithdrawAndBurnIntent() has copy, drop;

// === Public functions ===

/// Creates a DisableRulesIntent and adds it to an Account.
public fun request_disable_rules<Config, Outcome: store, CoinType>(
    auth: Auth,
    account: &mut Account<Config>,
    params: Params,
    outcome: Outcome,
    disable_action: DisableAction<CoinType>,
    ctx: &mut TxContext
) {
    account.verify(auth);
    params.assert_single_execution();

    account.build_intent!(
        params,
        outcome, 
        type_to_name<CoinType>(),
        version::current(),
        DisableRulesIntent(),   
        ctx,
        |intent, iw| intent.add_action(disable_action, iw),
    );
}

/// Executes a DisableRulesIntent, disables rules for the coin forever.
public fun execute_disable_rules<Config, Outcome: store, CoinType>(
    executable: &mut Executable<Outcome>,
    account: &mut Account<Config>,
) {
    account.process_intent!(
        executable,
        version::current(),
        DisableRulesIntent(),
        |executable, iw| currency::do_disable<_, _, CoinType, _>(executable, account, version::current(), iw)
    );
}

/// Creates an UpdateMetadataIntent and adds it to an Account.
public fun request_update_metadata<Config, Outcome: store, CoinType>(
    auth: Auth,
    account: &mut Account<Config>,
    params: Params,
    outcome: Outcome,
    update_action: UpdateAction<CoinType>,
    ctx: &mut TxContext
) {
    account.verify(auth);
    params.assert_single_execution();
    
    account.build_intent!(
        params,
        outcome, 
        type_to_name<CoinType>(),
        version::current(),
        UpdateMetadataIntent(),
        ctx,
        |intent, iw| intent.add_action(update_action, iw),
    );
}

/// Executes an UpdateMetadataIntent, updates the CoinMetadata.
public fun execute_update_metadata<Config, Outcome: store, CoinType>(
    executable: &mut Executable<Outcome>,
    account: &mut Account<Config>,
    metadata: &mut CoinMetadata<CoinType>,
) {
    account.process_intent!(
        executable,
        version::current(),
        UpdateMetadataIntent(),
        |executable, iw| currency::do_update<_, _, CoinType, _>(executable, account, metadata, version::current(), iw)
    );
}

/// Creates a MintAndTransferIntent and adds it to an Account.
public fun request_mint_and_transfer<Config, Outcome: store, CoinType>(
    auth: Auth,
    account: &mut Account<Config>,
    params: Params,
    outcome: Outcome,
    mint_actions: vector<MintAction<CoinType>>,
    transfer_actions: vector<TransferAction>,
    ctx: &mut TxContext
) {
    account.verify(auth);
    assert!(mint_actions.length() == transfer_actions.length(), EAmountsRecipentsNotSameLength);

    let rules = currency::borrow_rules<_, CoinType>(account);
    let sum = mint_actions.fold!(0, |sum, mint_action| sum + mint_action.amount());
    if (rules.max_supply().is_some()) assert!(sum <= *rules.max_supply().borrow(), EMaxSupply);

    account.build_intent!(
        params,
        outcome, 
        type_to_name<CoinType>(),
        version::current(),
        MintAndTransferIntent(),
        ctx,
        |intent, iw| mint_actions.zip_do!(transfer_actions, |mint_action, transfer_action| {
            intent.add_action(mint_action, iw);
            intent.add_action(transfer_action, iw);
        })
    );
}

/// Executes a MintAndTransferIntent, sends managed coins. Can be looped over.
public fun execute_mint_and_transfer<Config, Outcome: store, CoinType>(
    executable: &mut Executable<Outcome>, 
    account: &mut Account<Config>, 
    ctx: &mut TxContext
) {
    account.process_intent!(
        executable,
        version::current(),
        MintAndTransferIntent(),
        |executable, iw| {
            let coin = currency::do_mint<_, _, CoinType, _>(executable, account, version::current(), iw, ctx);
            acc_transfer::do_transfer(executable, coin, iw);
        }
    );
}

/// Creates a MintAndVestIntent and adds it to an Account.
public fun request_mint_and_vest<Config, Outcome: store, CoinType>(
    auth: Auth,
    account: &mut Account<Config>, 
    params: Params,
    outcome: Outcome,
    mint_action: MintAction<CoinType>,
    vest_action: VestAction,
    ctx: &mut TxContext
) {
    account.verify(auth);
    params.assert_single_execution();

    let rules = currency::borrow_rules<_, CoinType>(account);
    if (rules.max_supply().is_some()) assert!(mint_action.amount() <= *rules.max_supply().borrow(), EMaxSupply);

    account.build_intent!(
        params,
        outcome, 
        type_to_name<CoinType>(),
        version::current(),
        MintAndVestIntent(),
        ctx,
        |intent, iw| {
            intent.add_action(mint_action, iw);
            intent.add_action(vest_action, iw);
        }
    );
}

/// Executes a MintAndVestIntent, sends managed coins and creates a vesting.
public fun execute_mint_and_vest<Config, Outcome: store, CoinType>(
    executable: &mut Executable<Outcome>, 
    account: &mut Account<Config>, 
    ctx: &mut TxContext
) {
    account.process_intent!(
        executable,
        version::current(),
        MintAndVestIntent(),
        |executable, iw| {
            let coin = currency::do_mint<_, _, CoinType, _>(executable, account, version::current(), iw, ctx);
            vesting::do_vest(executable, coin, iw, ctx);
        }
    );
}

/// Creates a WithdrawAndBurnIntent and adds it to an Account.
public fun request_withdraw_and_burn<Config, Outcome: store, CoinType>(
    auth: Auth,
    account: &mut Account<Config>,
    params: Params,
    outcome: Outcome,
    withdraw_action: WithdrawAction,
    burn_action: BurnAction<CoinType>,
    ctx: &mut TxContext
) {
    account.verify(auth);
    params.assert_single_execution();

    account.build_intent!(
        params,
        outcome, 
        type_to_name<CoinType>(),
        version::current(),
        WithdrawAndBurnIntent(), 
        ctx,
        |intent, iw| {
            intent.add_action(burn_action, iw);
            intent.add_action(withdraw_action, iw);
        }
    );
}


/// Executes a WithdrawAndBurnIntent, burns a coin owned by the account.
public fun execute_withdraw_and_burn<Config, Outcome: store, CoinType>(
    executable: &mut Executable<Outcome>,
    account: &mut Account<Config>,
    receiving: Receiving<Coin<CoinType>>,
) {
    account.process_intent!(
        executable,
        version::current(),
        WithdrawAndBurnIntent(),
        |executable, iw| {
            let coin = owned::do_withdraw(executable, account, receiving, iw);
            currency::do_burn<_, _, CoinType, _>(executable, account, coin, version::current(), iw);
        }
    );
}

// === Private functions ===

fun type_to_name<T>(): String {
    type_name::get<T>().into_string().to_string()
}