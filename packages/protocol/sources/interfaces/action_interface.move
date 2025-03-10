/// [Action Interface] - Functions to stack and execute actions from an executable intent.
///
/// 1. Stack an action into an Intent.
/// 2. Execute an action from an executable intent.

module account_protocol::action_interface;

// === Imports ===

use account_protocol::{
    intents::Intent,
    executable::Executable,
};

// === Public functions ===

/// Example implementation:
/// 
/// ```move
/// 
/// public fun new_action_name<Config, Outcome, IW: drop>(
///     intent: &mut Intent<Outcome>, 
///     <ACTION_ARGS>,
///     intent_witness: IW,
/// ) {
///     intent.init_action!(intent_witness, || Action { <ACTION_ARGS> });
/// } 
/// 
/// ```

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

/// Example implementation:
/// 
/// ```move
/// 
/// public fun do_action_name<Outcome: store, IW: drop>(
///     executable: &mut Executable<Outcome>,
///     intent_witness: IW,
/// ): T {
///     executable.do_action!( 
///         intent_witness,
///         |action: &Action| <DO_SOMETHING_WITH_ACTION>,
///     );
/// }
/// 
/// ```

/// Execute an action using the Executable hot potato.
public macro fun do_action<$Outcome, $Action: store, $IW: drop>(
    $executable: &mut Executable<$Outcome>,
    $intent_witness: $IW,
    $do_action: |&$Action| -> (),
) {
    let executable = $executable;

    let action = executable.next_action($intent_witness);
    $do_action(action);
}