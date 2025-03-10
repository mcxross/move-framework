/// [Action Interface] - Functions to stack and execute actions from an executable intent.
///
/// 1. Stack an action into an Intent.
/// 2. Execute an action from an executable intent.

module account_protocol::action_interface;

// === Imports ===

use account_protocol::{
    account::Account,
    intents::Intent,
    executable::Executable,
};

// === Public functions ===

/// Adds an instantiated action into an Intent.
public macro fun init_action<$Outcome, $Action: store, $IW: drop>(
    $intent: &mut Intent<$Outcome>,
    $intent_witness: $IW,
    $new_action: || -> $Action,
) {
    let intent = $intent;
    let action = $new_action();
    intent.add_action(action, $intent_witness);
}

/// Execute an action using the Executable hot potato.
public macro fun do_action<$Config, $Outcome, $Action: store>(
    $executable: &mut Executable<$Outcome>,
    $account: &Account<$Config>,
    $do_action: |&$Action| -> (),
) {
    let account = $account;
    let executable = $executable;

    executable.intent().issuer().assert_is_account(account.addr());
    let action = executable.get_action();
    $do_action(action);
}