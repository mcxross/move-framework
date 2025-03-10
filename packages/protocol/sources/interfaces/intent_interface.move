/// [Intent Interface] - Functions to create intents and add actions to them.
///
/// 1. Build an intent by stacking actions into it.
/// 2. Process an intent by executing the actions sequentially.

module account_protocol::intent_interface;

// === Imports ===

use std::string::String;
use account_protocol::{
    account::Account,
    intents::{Intent, Params},
    version_witness::VersionWitness,
    executable::Executable,
};

// === Public functions ===

/// Example implementation:
/// 
/// ```move
/// 
/// public fun request_intent_name<Config, Outcome: store>(
///     auth: Auth,
///     account: &mut Account<Config>, 
///     params: Params,
///     outcome: Outcome,
///     <ACTION_ARGS>,
///     ctx: &mut TxContext
/// ) {
///     account.verify(auth);
///     params.assert_single_execution(); // if not a recurring intent
/// 
///     account.build_intent!(
///         params,
///         outcome, 
///         b"".to_string(),
///         version::current(),
///         IntentWitness(),   
///         ctx,
///         |intent| {
///             new_action(intent, <ACTION_ARGS>)
///             new_other_action(intent)
///         }
///     );
/// }
/// 
/// ```

/// Creates an intent with actions and adds it to the account.
public macro fun build_intent<$Config, $Outcome, $IW: drop>(
    $account: &mut Account<$Config>,
    $params: Params,
    $outcome: $Outcome,
    $managed_name: String,
    $version_witness: VersionWitness,
    $intent_witness: $IW,
    $ctx: &mut TxContext,
    $add_actions: |&mut Intent<$Outcome>| -> (),
) {
    let account = $account;

    let mut intent = account.create_intent(
        $params,
        $outcome,
        $managed_name,
        $version_witness,
        $intent_witness,
        $ctx 
    );

    $add_actions(&mut intent);

    account.add_intent(intent, $version_witness, $intent_witness);
}

/// Example implementation:
/// 
/// ```move
/// 
/// public fun execute_intent_name<Config, Outcome: store>(
///     executable: &mut Executable<Outcome>,
///     account: &mut Account<Config>,  
/// ) {
///     account.process_intent!(
///         executable, 
///         version::current(),   
///         ConfigDepsIntent(), 
///         |executable| {
///             do_action(executable, <ADDITIONAL_ARG>)
///             do_other_action(executable)
///         }
///     ); 
/// } 
/// 
/// ```

/// Executes the actions from the executable intent.
public macro fun process_intent<$Config, $Outcome: store, $IW: drop>(
    $account: &Account<$Config>, 
    $executable: &mut Executable<$Outcome>,
    $version_witness: VersionWitness,
    $intent_witness: $IW,
    $do_actions: |&mut Executable<$Outcome>| -> ()
) {
    let account = $account;
    let executable = $executable;
    // let version_witness = $version_witness;
    // let intent_witness = $intent_witness;
    // ensures the package address is a dependency for this account
    account.deps().check($version_witness);
    // ensures the right account is passed
    executable.intent().assert_is_account(account.addr());
    // ensures the intent is created by the same package that creates the action
    executable.intent().assert_is_intent($intent_witness);

    $do_actions(executable);
}