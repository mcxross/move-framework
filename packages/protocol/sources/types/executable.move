/// The Executable struct is hot potato constructed from an Intent that has been resolved.
/// It ensures that the actions are executed as intended as it can't be stored.
/// Action index is tracked to ensure each action is executed exactly once.

module account_protocol::executable;

// === Imports ===

use account_protocol::intents::Intent;

// === Structs ===

/// Hot potato ensuring the actions in the intent are executed as intended.
public struct Executable<Outcome: store> {
    // intent to return or destroy (if execution_times empty) after execution
    intent: Intent<Outcome>,
    // current action index
    action_idx: u64,
}

// === View functions ===

/// Returns the issuer of the corresponding intent
public fun intent<Outcome: store>(executable: &Executable<Outcome>): &Intent<Outcome> {
    &executable.intent
}

/// Returns the current action index
public fun action_idx<Outcome: store>(executable: &Executable<Outcome>): u64 {
    executable.action_idx
}

public fun contains_action<Outcome: store, Action: store>(
    executable: &mut Executable<Outcome>,
): bool {
    let actions_length = executable.intent().actions().length();
    let mut contains = false;
    
    actions_length.do!<u64>(|i| {
        if (executable.intent.actions().contains_with_type<u64, Action>(i)) contains = true;
    });

    contains
}

// === Package functions ===

/// Creates a new executable from an intent
public(package) fun new<Outcome: store>(intent: Intent<Outcome>): Executable<Outcome> {
    Executable { intent, action_idx: 0 }
}

/// Returns the next action 
public fun next_action<Outcome: store, Action: store, IW: drop>(
    executable: &mut Executable<Outcome>,
    intent_witness: IW,
): &Action {
    executable.intent.assert_is_witness(intent_witness);

    let action_idx = executable.action_idx;
    executable.action_idx = executable.action_idx + 1;
    
    executable.intent().actions().borrow(action_idx)
}

/// Destroys the executable
public(package) fun destroy<Outcome: store>(executable: Executable<Outcome>): Intent<Outcome> {
    let Executable { intent, .. } = executable;
    intent
}