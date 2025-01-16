#[test_only]
module account_actions::config_tests;

// === Imports ===

use std::type_name::{Self, TypeName};
use sui::{
    test_utils::destroy,
    test_scenario::{Self as ts, Scenario},
    clock::{Self, Clock},
    package,
};
use account_extensions::extensions::{Self, Extensions, AdminCap};
use account_protocol::{
    account::Account,
    intents::Intent,
    issuer,
    deps,
};
use account_config::multisig::{Self, Multisig, Approvals};
use account_actions::{
    version,
    config,
    upgrade_policies,
};

// === Constants ===

const OWNER: address = @0xCAFE;

// === Structs ===

public struct DummyIntent() has copy, drop;

public struct Cap has key, store { id: UID }
public struct WrongCap has store {}

// === Helpers ===

fun start(): (Scenario, Extensions, Account<Multisig, Approvals>, Clock) {
    let mut scenario = ts::begin(OWNER);
    // publish package
    extensions::init_for_testing(scenario.ctx());
    // retrieve objects
    scenario.next_tx(OWNER);
    let mut extensions = scenario.take_shared<Extensions>();
    let cap = scenario.take_from_sender<AdminCap>();
    // add core deps
    extensions.add(&cap, b"AccountProtocol".to_string(), @account_protocol, 1);
    extensions.add(&cap, b"AccountConfig".to_string(), @account_config, 1);
    extensions.add(&cap, b"AccountActions".to_string(), @account_actions, 1);
    // add external dep
    extensions.add(&cap, b"External".to_string(), @0xABC, 1);
    // Account generic types are dummy types (bool, bool)
    let account = multisig::new_account(&extensions, scenario.ctx());
    let clock = clock::create_for_testing(scenario.ctx());
    // create world
    destroy(cap);
    (scenario, extensions, account, clock)
}

fun end(scenario: Scenario, extensions: Extensions, account: Account<Multisig, Approvals>, clock: Clock) {
    destroy(extensions);
    destroy(account);
    destroy(clock);
    ts::end(scenario);
}

fun wrong_version(): TypeName {
    type_name::get<Extensions>()
}

fun create_dummy_intent(
    scenario: &mut Scenario,
    account: &mut Account<Multisig, Approvals>, 
    extensions: &Extensions, 
): Intent<Approvals> {
    let auth = multisig::authenticate(extensions, account, scenario.ctx());
    let outcome = multisig::empty_outcome(account, scenario.ctx());
    account.create_intent(
        auth, 
        b"dummy".to_string(), 
        b"".to_string(), 
        vector[0],
        1, 
        outcome, 
        version::current(), 
        DummyIntent(), 
        b"".to_string(), 
        scenario.ctx()
    )
}

// === Tests ===

#[test]
fun test_edit_config_metadata() {
    let (mut scenario, extensions, mut account, clock) = start();    
    assert!(account.metadata().size() == 0);

    let auth = multisig::authenticate(&extensions, &account, scenario.ctx());
    config::edit_metadata(
        auth, 
        &mut account, 
        vector[b"name".to_string()], 
        vector[b"New Name".to_string()], 
    );

    assert!(account.metadata().get(b"name".to_string()) == b"New Name".to_string());
    end(scenario, extensions, account, clock);
}

#[test]
fun test_request_execute_config_deps() {
    let (mut scenario, extensions, mut account, clock) = start();    
    let key = b"dummy".to_string();

    let auth = multisig::authenticate(&extensions, &account, scenario.ctx());
    let outcome = multisig::empty_outcome(&account, scenario.ctx());
    config::request_config_deps(
        auth, 
        outcome, 
        &mut account, 
        key, 
        b"".to_string(), 
        0, 
        1, 
        &extensions,
        vector[b"External".to_string()], 
        vector[@0xABC], 
        vector[1], 
        scenario.ctx()
    );
    assert!(!account.deps().contains_name(b"External".to_string()));

    multisig::approve_intent(&mut account, key, scenario.ctx());
    let executable = multisig::execute_intent(&mut account, key, &clock);
    config::execute_config_deps(executable, &mut account);

    let mut expired = account.destroy_empty_intent(key);
    config::delete_config_deps(&mut expired);
    expired.destroy_empty();
    
    let package = account.deps().get_from_name(b"External".to_string());
    assert!(package.addr() == @0xABC);
    assert!(package.version() == 1);

    end(scenario, extensions, account, clock);
}

#[test]
fun test_config_deps_flow() {
    let (mut scenario, extensions, mut account, clock) = start();
    let key = b"dummy".to_string();

    let mut intent = create_dummy_intent(&mut scenario, &mut account, &extensions);  assert!(!account.deps().contains_name(b"External".to_string()));
    
    config::new_config_deps(
        &mut intent, 
        &account, 
        &extensions, 
        vector[b"External".to_string()], 
        vector[@0xABC], 
        vector[1], 
        DummyIntent()
    );
    account.add_intent(intent, version::current(), DummyIntent());

    multisig::approve_intent(&mut account, key, scenario.ctx());
    let mut executable = multisig::execute_intent(&mut account, key, &clock);
    config::do_config_deps(&mut executable, &mut account, version::current(), DummyIntent());
    assert!(account.deps().get_from_name(b"External".to_string()).addr() == @0xABC);
    assert!(account.deps().get_from_name(b"External".to_string()).version() == 1);

    account.confirm_execution(executable, version::current(), DummyIntent());

    end(scenario, extensions, account, clock);
}

#[test]
fun test_config_deps_from_upgrade_cap() {
    let (mut scenario, extensions, mut account, clock) = start();
    let key = b"dummy".to_string();

    let upgrade_cap = package::test_publish(@0xdee9.to_id(), scenario.ctx());
    let auth = multisig::authenticate(&extensions, &account, scenario.ctx());
    upgrade_policies::lock_cap(auth, &mut account, upgrade_cap, b"DeepPackage".to_string(), 0);

    let mut intent = create_dummy_intent(&mut scenario, &mut account, &extensions);  assert!(!account.deps().contains_name(b"DeepPackage".to_string()));
    
    config::new_config_deps(
        &mut intent, 
        &account, 
        &extensions, 
        vector[b"DeepPackage".to_string()], 
        vector[@0xdee9], 
        vector[1], 
        DummyIntent()
    );
    account.add_intent(intent, version::current(), DummyIntent());

    multisig::approve_intent(&mut account, key, scenario.ctx());
    let mut executable = multisig::execute_intent(&mut account, key, &clock);
    config::do_config_deps(&mut executable, &mut account, version::current(), DummyIntent());
    assert!(account.deps().get_from_name(b"DeepPackage".to_string()).addr() == @0xdee9);
    assert!(account.deps().get_from_name(b"DeepPackage".to_string()).version() == 1);

    account.confirm_execution(executable, version::current(), DummyIntent());

    end(scenario, extensions, account, clock);
}

#[test]
fun test_config_deps_expired() {
    let (mut scenario, extensions, mut account, mut clock) = start();
    clock.increment_for_testing(1);
    let key = b"dummy".to_string();

    let mut intent = create_dummy_intent(&mut scenario, &mut account, &extensions);  
    config::new_config_deps(
        &mut intent, 
        &account, 
        &extensions, 
        vector[b"External".to_string()], 
        vector[@0xABC], 
        vector[1], 
        DummyIntent()
    );
    account.add_intent(intent, version::current(), DummyIntent());
    
    let mut expired = account.delete_expired_intent(key, &clock);
    config::delete_config_deps(&mut expired);
    expired.destroy_empty();

    end(scenario, extensions, account, clock);
}

#[test, expected_failure(abort_code = config::EMetadataNotSameLength)]
fun test_error_new_config_metadata_not_same_length() {
    let (mut scenario, extensions, mut account, clock) = start();

    let auth = multisig::authenticate(&extensions, &account, scenario.ctx());
    config::edit_metadata(auth, &mut account, vector[b"name".to_string()], vector[]);

    end(scenario, extensions, account, clock);
}

#[test, expected_failure(abort_code = config::EMetadataNameMissing)]
fun test_error_new_config_metadata_name_missing() {
    let (mut scenario, extensions, mut account, clock) = start();

    let auth = multisig::authenticate(&extensions, &account, scenario.ctx());
    config::edit_metadata(auth, &mut account, vector[b"nam".to_string()], vector[b"".to_string()]);

    end(scenario, extensions, account, clock);
}

#[test, expected_failure(abort_code = config::ENameCannotBeEmpty)]
fun test_error_new_config_metadata_name_empty() {
    let (mut scenario, extensions, mut account, clock) = start();

    let auth = multisig::authenticate(&extensions, &account, scenario.ctx());
    config::edit_metadata(auth, &mut account, vector[b"name".to_string()], vector[b"".to_string()]);

    end(scenario, extensions, account, clock);
}

#[test, expected_failure(abort_code = config::ENoExtensionOrUpgradeCap)]
fun test_error_config_deps_not_extension_name() {
    let (mut scenario, extensions, mut account, clock) = start();

    let mut intent = create_dummy_intent(&mut scenario, &mut account, &extensions);  assert!(!account.deps().contains_name(b"External".to_string()));
    
    config::new_config_deps(
        &mut intent, 
        &account, 
        &extensions, 
        vector[b"Other".to_string()], 
        vector[@0xABC], 
        vector[1], 
        DummyIntent()
    );
    account.add_intent(intent, version::current(), DummyIntent());

    end(scenario, extensions, account, clock);
}

#[test, expected_failure(abort_code = config::ENoExtensionOrUpgradeCap)]
fun test_error_config_deps_not_extension_addr() {
    let (mut scenario, extensions, mut account, clock) = start();

    let mut intent = create_dummy_intent(&mut scenario, &mut account, &extensions);  assert!(!account.deps().contains_name(b"External".to_string()));
    
    config::new_config_deps(
        &mut intent, 
        &account, 
        &extensions, 
        vector[b"External".to_string()], 
        vector[@0xDEF], 
        vector[1], 
        DummyIntent()
    );
    account.add_intent(intent, version::current(), DummyIntent());

    end(scenario, extensions, account, clock);
}

#[test, expected_failure(abort_code = config::ENoExtensionOrUpgradeCap)]
fun test_error_config_deps_not_extension_version() {
    let (mut scenario, extensions, mut account, clock) = start();

    let mut intent = create_dummy_intent(&mut scenario, &mut account, &extensions);  assert!(!account.deps().contains_name(b"External".to_string()));
    
    config::new_config_deps(
        &mut intent, 
        &account, 
        &extensions, 
        vector[b"External".to_string()], 
        vector[@0xABC], 
        vector[2], 
        DummyIntent()
    );
    account.add_intent(intent, version::current(), DummyIntent());

    end(scenario, extensions, account, clock);
}

#[test, expected_failure(abort_code = config::ENoExtensionOrUpgradeCap)]
fun test_error_config_deps_from_not_upgrade_cap() {
    let (mut scenario, extensions, mut account, clock) = start();

    let mut intent = create_dummy_intent(&mut scenario, &mut account, &extensions);  assert!(!account.deps().contains_name(b"DeepPackage".to_string()));
    
    config::new_config_deps(
        &mut intent, 
        &account, 
        &extensions, 
        vector[b"DeepPackage".to_string()], 
        vector[@0xdee9], 
        vector[1], 
        DummyIntent()
    );
    account.add_intent(intent, version::current(), DummyIntent());

    end(scenario, extensions, account, clock);
}

// sanity checks as these are tested in AccountProtocol tests

#[test, expected_failure(abort_code = issuer::EWrongAccount)]
fun test_error_do_config_deps_for_wrong_account() {
    let (mut scenario, extensions, mut account, clock) = start();
    let key = b"dummy".to_string();

    let mut intent = create_dummy_intent(&mut scenario, &mut account, &extensions);  config::new_config_deps(&mut intent, &account, &extensions, vector[b"External".to_string()], vector[@0xABC], vector[1], DummyIntent());
    account.add_intent(intent, version::current(), DummyIntent());

    multisig::approve_intent(&mut account, key, scenario.ctx());
    let mut executable = multisig::execute_intent(&mut account, key, &clock);

    let mut account2 = multisig::new_account(&extensions, scenario.ctx());
    config::do_config_deps(&mut executable, &mut account2, version::current(), DummyIntent());

    destroy(account2);
    destroy(executable);
    end(scenario, extensions, account, clock);
}

#[test, expected_failure(abort_code = issuer::EWrongWitness)]
fun test_error_do_config_deps_from_wrong_constructor_witness() {
    let (mut scenario, extensions, mut account, clock) = start();
    let key = b"dummy".to_string();

    let mut intent = create_dummy_intent(&mut scenario, &mut account, &extensions);  config::new_config_deps(&mut intent, &account, &extensions, vector[b"External".to_string()], vector[@0xABC], vector[1], DummyIntent());
    account.add_intent(intent, version::current(), DummyIntent());

    multisig::approve_intent(&mut account, key, scenario.ctx());
    let mut executable = multisig::execute_intent(&mut account, key, &clock);
    // wrong witness used here
    config::do_config_deps(&mut executable, &mut account, version::current(), issuer::wrong_witness());

    destroy(executable);
    end(scenario, extensions, account, clock);
}

#[test, expected_failure(abort_code = deps::ENotDep)]
fun test_error_do_config_deps_not_from_dep() {
    let (mut scenario, extensions, mut account, clock) = start();
    let key = b"dummy".to_string();

    let mut intent = create_dummy_intent(&mut scenario, &mut account, &extensions);  config::new_config_deps(&mut intent, &account, &extensions, vector[b"External".to_string()], vector[@0xABC], vector[1], DummyIntent());
    account.add_intent(intent, version::current(), DummyIntent());
    // wrong version dep used here
    multisig::approve_intent(&mut account, key, scenario.ctx());
    let mut executable = multisig::execute_intent(&mut account, key, &clock);
    config::do_config_deps(&mut executable, &mut account, wrong_version(), DummyIntent());

    destroy(executable);
    end(scenario, extensions, account, clock);
}
