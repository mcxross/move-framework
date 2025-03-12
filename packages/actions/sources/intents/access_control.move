module account_actions::access_control_intents;

// === Imports ===

use account_protocol::{
    account::{Account, Auth},
    executable::Executable,
    intents::Params,
    intent_interface,
};
use account_actions::{
    access_control::{Self as ac, Borrowed, BorrowAction},
    version,
};

// === Aliases ===

use fun intent_interface::build_intent as Account.build_intent;
use fun intent_interface::process_intent as Account.process_intent;

// === Errors ===

const ENoLock: u64 = 0;

// === Structs ===    

/// Intent Witness defining the intent to borrow an access cap.
public struct BorrowCapIntent() has copy, drop;

// === Public functions ===

/// Creates a BorrowCapIntent and adds it to an Account.
public fun request_borrow_cap<Config, Outcome: store, Cap>(
    auth: Auth,
    account: &mut Account<Config>,
    params: Params,
    outcome: Outcome,
    borrow_action: BorrowAction<Cap>,
    ctx: &mut TxContext
) {
    account.verify(auth);
    assert!(ac::has_lock<_, Cap>(account), ENoLock);

    account.build_intent!(
        params,
        outcome, 
        b"".to_string(),
        version::current(),
        BorrowCapIntent(),
        ctx,
        |intent, iw| intent.add_action(borrow_action, iw),
    );
}

/// Executes a BorrowCapIntent, returns a cap and a hot potato.
public fun execute_borrow_cap<Config, Outcome: store, Cap: key + store>(
    executable: &mut Executable<Outcome>,
    account: &mut Account<Config>,
): (Borrowed<Cap>, Cap) {
    account.process_intent!(
        executable, 
        version::current(), 
        BorrowCapIntent(), 
        |executable, iw| ac::do_borrow(executable, account, version::current(), iw),
    )
}

/// Completes a BorrowCapIntent, destroys the executable and returns the cap to the account if the matching hot potato is returned.
public fun complete_borrow_cap<Config, Cap: key + store>(
    account: &mut Account<Config>,
    borrowed: Borrowed<Cap>, 
    cap: Cap
) {
    ac::return_borrowed(account, borrowed, cap, version::current());
}