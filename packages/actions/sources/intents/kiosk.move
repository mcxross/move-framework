module account_actions::kiosk_intents;

// === Imports ===

use sui::{
    kiosk::{Kiosk, KioskOwnerCap},
    transfer_policy::{TransferPolicy, TransferRequest},
};
use account_protocol::{
    account::{Account, Auth},
    intents::Params,
    executable::Executable,
    intent_interface,
};
use account_actions::{
    kiosk::{Self as acc_kiosk, TakeAction, ListAction},
    version,
};

// === Aliases ===

use fun intent_interface::build_intent as Account.build_intent;
use fun intent_interface::process_intent as Account.process_intent;

// === Errors ===

const ENoLock: u64 = 0;
const ENftsPricesNotSameLength: u64 = 1;
const ENameNotSame: u64 = 2;

// === Structs ===

/// Intent Witness defining the intent to take nfts from a kiosk managed by a account to another kiosk.
public struct TakeNftsIntent() has copy, drop;
/// Intent Witness defining the intent to list nfts in a kiosk managed by a account.
public struct ListNftsIntent() has copy, drop;

// === Public functions ===

/// Creates a TakeNftsIntent and adds it to an Account.
public fun request_take_nfts<Config, Outcome: store>(
    auth: Auth,
    account: &mut Account<Config>,
    params: Params,
    outcome: Outcome,
    take_actions: vector<TakeAction>,
    ctx: &mut TxContext
) {
    account.verify(auth);
    params.assert_single_execution();

    assert!(acc_kiosk::has_lock(account, take_actions[0].name()), ENoLock);
    assert!(take_actions.all!(|action| action.name() == take_actions[0].name()), ENameNotSame);

    account.build_intent!(
        params,
        outcome, 
        take_actions[0].name(),
        version::current(),
        TakeNftsIntent(),
        ctx,
        |intent, iw| take_actions.do!(|take_action| intent.add_action(take_action, iw))
    );
}

/// Executes a TakeNftsIntent, takes nfts from a kiosk managed by a account to another kiosk. Can be looped over.
public fun execute_take_nfts<Config, Outcome: store, Nft: key + store>(
    executable: &mut Executable<Outcome>,
    account: &mut Account<Config>,
    account_kiosk: &mut Kiosk, 
    recipient_kiosk: &mut Kiosk, 
    recipient_cap: &KioskOwnerCap, 
    policy: &mut TransferPolicy<Nft>,
    ctx: &mut TxContext
): TransferRequest<Nft> {
    account.process_intent!(
        executable,
        version::current(),
        TakeNftsIntent(),
        |executable, iw| acc_kiosk::do_take<_, _, Nft, _>(
            executable, 
            account, 
            account_kiosk, 
            recipient_kiosk, 
            recipient_cap, 
            policy, 
            version::current(), 
            iw, 
            ctx
        ),
    )
}

/// Creates a ListNftsIntent and adds it to an Account.
public fun request_list_nfts<Config, Outcome: store>(
    auth: Auth,
    account: &mut Account<Config>,
    params: Params,
    outcome: Outcome,
    list_actions: vector<ListAction>,
    ctx: &mut TxContext
) {
    account.verify(auth);
    assert!(acc_kiosk::has_lock(account, list_actions[0].name()), ENoLock);
    assert!(list_actions.all!(|action| action.name() == list_actions[0].name()), ENameNotSame);

    account.build_intent!(
        params,
        outcome,
        list_actions[0].name(),
        version::current(),
        ListNftsIntent(),
        ctx,
        |intent, iw| list_actions.do!(|list_action| intent.add_action(list_action, iw))
    );
}

/// Executes a ListNftsIntent, lists nfts in a kiosk managed by a account. Can be looped over.
public fun execute_list_nfts<Config, Outcome: store, Nft: key + store>(
    executable: &mut Executable<Outcome>,
    account: &mut Account<Config>,
    kiosk: &mut Kiosk,
) {
    account.process_intent!(
        executable,
        version::current(),
        ListNftsIntent(),
        |executable, iw| acc_kiosk::do_list<_, _, Nft, _>(executable, account, kiosk, version::current(), iw),
    );
}