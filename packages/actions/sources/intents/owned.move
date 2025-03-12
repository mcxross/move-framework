module account_actions::owned_intents;

// === Imports ===

use sui::{
    transfer::Receiving,
    coin::Coin,
};
use account_protocol::{
    account::{Account, Auth},
    executable::Executable,
    owned::{Self, WithdrawAction},
    intents::Params,
    intent_interface,
};
use account_actions::{
    transfer::{Self as acc_transfer, TransferAction},
    vesting::{Self, VestAction},
    vault::{Self, DepositAction},
    version,
};

// === Aliases ===

use fun intent_interface::build_intent as Account.build_intent;
use fun intent_interface::process_intent as Account.process_intent;

// === Errors ===

const EObjectsRecipientsNotSameLength: u64 = 0;

// === Structs ===

/// Intent Witness defining the intent to withdraw a coin and deposit it into a vault.
public struct WithdrawAndTransferToVaultIntent() has copy, drop;
/// Intent Witness defining the intent to withdraw and transfer multiple objects.
public struct WithdrawAndTransferIntent() has copy, drop;
/// Intent Witness defining the intent to withdraw a coin and create a vesting.
public struct WithdrawAndVestIntent() has copy, drop;

// === Public functions ===

/// Creates a WithdrawAndTransferToVaultIntent and adds it to an Account.
public fun request_withdraw_and_transfer_to_vault<Config, Outcome: store, CoinType: drop>(
    auth: Auth,
    account: &mut Account<Config>, 
    params: Params,
    outcome: Outcome,
    withdraw_action: WithdrawAction,
    deposit_action: DepositAction<CoinType>,
    ctx: &mut TxContext
) {
    account.verify(auth);
    params.assert_single_execution();

    account.build_intent!(
        params,
        outcome,
        b"".to_string(),
        version::current(),
        WithdrawAndTransferToVaultIntent(),
        ctx,
        |intent, iw| {
            intent.add_action(withdraw_action, iw);
            intent.add_action(deposit_action, iw);
        }
    );
}

/// Executes a WithdrawAndTransferToVaultIntent, deposits a coin owned by the account into a vault.
public fun execute_withdraw_and_transfer_to_vault<Config, Outcome: store, CoinType: drop>(
    executable: &mut Executable<Outcome>, 
    account: &mut Account<Config>, 
    receiving: Receiving<Coin<CoinType>>,
) {
    account.process_intent!(
        executable,
        version::current(),
        WithdrawAndTransferToVaultIntent(),
        |executable, iw| {
            let object = owned::do_withdraw(executable, account, receiving, iw);
            vault::do_deposit<_, _, CoinType, _>(executable, account, object, version::current(), iw);
        }
    );
}

/// Creates a WithdrawAndTransferIntent and adds it to an Account.
public fun request_withdraw_and_transfer<Config, Outcome: store>(
    auth: Auth,
    account: &mut Account<Config>, 
    params: Params,
    outcome: Outcome,
    withdraw_actions: vector<WithdrawAction>,
    transfer_actions: vector<TransferAction>,
    ctx: &mut TxContext
) {
    account.verify(auth);
    params.assert_single_execution();
    assert!(withdraw_actions.length() == transfer_actions.length(), EObjectsRecipientsNotSameLength);

    account.build_intent!(
        params,
        outcome,
        b"".to_string(),
        version::current(),
        WithdrawAndTransferIntent(),
        ctx,
        |intent, iw| withdraw_actions.zip_do!(transfer_actions, |withdraw_action, transfer_action| {
            intent.add_action(withdraw_action, iw);
            intent.add_action(transfer_action, iw);
        })
    );
}

/// Executes a WithdrawAndTransferIntent, transfers an object owned by the account. Can be looped over.
public fun execute_withdraw_and_transfer<Config, Outcome: store, T: key + store>(
    executable: &mut Executable<Outcome>, 
    account: &mut Account<Config>, 
    receiving: Receiving<T>,
) {
    account.process_intent!(
        executable,
        version::current(),
        WithdrawAndTransferIntent(),
        |executable, iw| {
            let object = owned::do_withdraw(executable, account, receiving, iw);
            acc_transfer::do_transfer(executable, object, iw);
        }
    );
}

/// Creates a WithdrawAndVestIntent and adds it to an Account.
public fun request_withdraw_and_vest<Config, Outcome: store>(
    auth: Auth,
    account: &mut Account<Config>, 
    params: Params,
    outcome: Outcome,
    withdraw_action: WithdrawAction,
    vest_action: VestAction,
    ctx: &mut TxContext
) {
    account.verify(auth);
    params.assert_single_execution();

    account.build_intent!(
        params,
        outcome,
        b"".to_string(),
        version::current(),
        WithdrawAndVestIntent(),
        ctx,
        |intent, iw| {
            intent.add_action(withdraw_action, iw);
            intent.add_action(vest_action, iw);
        }
    );
}

/// Executes a WithdrawAndVestIntent, withdraws a coin and creates a vesting.
public fun execute_withdraw_and_vest<Config, Outcome: store, C: drop>(
    executable: &mut Executable<Outcome>, 
    account: &mut Account<Config>, 
    receiving: Receiving<Coin<C>>,
    ctx: &mut TxContext
) {
    account.process_intent!(
        executable,
        version::current(),
        WithdrawAndVestIntent(),
        |executable, iw| {
            let coin = owned::do_withdraw(executable, account, receiving, iw);
            vesting::do_vest(executable, coin, iw, ctx);
        }
    );
}