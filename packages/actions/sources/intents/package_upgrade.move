module account_actions::package_upgrade_intents;

// === Imports ===

use sui::{
    package::UpgradeTicket,
    clock::Clock,
};
use account_protocol::{
    account::{Account, Auth},
    executable::Executable,
    intents::Params,
    intent_interface,
};
use account_actions::{
    package_upgrade::{Self, UpgradeAction, RestrictAction},
    version,
};

// === Aliases ===

use fun intent_interface::build_intent as Account.build_intent;
use fun intent_interface::process_intent as Account.process_intent;

// === Errors ===

const EInvalidExecutionTime: u64 = 0;

// === Structs ===

/// Intent Witness defining the intent to upgrade a package.
public struct UpgradePackageIntent() has copy, drop;
/// Intent Witness defining the intent to restrict an UpgradeCap.
public struct RestrictPolicyIntent() has copy, drop;

// === Public Functions ===

/// Creates an UpgradePackageIntent and adds it to an Account.
public fun request_upgrade_package<Config, Outcome: store>(
    auth: Auth,
    account: &mut Account<Config>, 
    params: Params,
    outcome: Outcome,
    upgrade_action: UpgradeAction,
    ctx: &mut TxContext
) {
    account.verify(auth);
    params.assert_single_execution();
    assert!(params.execution_times()[0] >= upgrade_action.upgrade_time(), EInvalidExecutionTime);

    account.build_intent!(
        params,
        outcome,
        b"".to_string(),
        version::current(),
        UpgradePackageIntent(),
        ctx,
        |intent, iw| intent.add_action(upgrade_action, iw),
    );
}

/// Executes an UpgradePackageIntent, returns the UpgradeTicket for upgrading.
public fun execute_upgrade_package<Config, Outcome: store>(
    executable: &mut Executable<Outcome>,
    account: &mut Account<Config>,
    clock: &Clock,
): UpgradeTicket {
    account.process_intent!(
        executable,
        version::current(),
        UpgradePackageIntent(),
        |executable, iw| package_upgrade::do_upgrade(executable, account, clock, version::current(), iw)
    )
}    

/// Need to consume the ticket to upgrade the package before completing the intent.

/// Creates a RestrictPolicyIntent and adds it to an Account.
public fun request_restrict_policy<Config, Outcome: store>(
    auth: Auth,
    account: &mut Account<Config>, 
    params: Params,
    outcome: Outcome,
    restrict_action: RestrictAction,
    ctx: &mut TxContext
) {
    account.verify(auth);
    params.assert_single_execution();

    account.build_intent!(
        params,
        outcome,
        b"".to_string(),
        version::current(),
        RestrictPolicyIntent(),
        ctx,
        |intent, iw| intent.add_action(restrict_action, iw),
    );
}

/// Restricts the upgrade policy.
public fun execute_restrict_policy<Config, Outcome: store>(
    executable: &mut Executable<Outcome>,
    account: &mut Account<Config>,
) {
    account.process_intent!(
        executable,
        version::current(),
        RestrictPolicyIntent(),
        |executable, iw| package_upgrade::do_restrict(executable, account, version::current(), iw)
    );
}