#[test_only]
module account_actions::package_upgrade_tests;

// === Imports ===

use sui::{
    test_utils::destroy,
    test_scenario::{Self as ts, Scenario},
    clock::{Self, Clock},
    package::{Self, UpgradeCap},
};
use account_extensions::extensions::{Self, Extensions, AdminCap};
use account_protocol::{
    account::{Self, Account},
    intents::Intent,
    issuer,
    deps,
    version_witness,
};
use account_actions::{
    version,
    package_upgrade,
};

// === Constants ===

const OWNER: address = @0xCAFE;

// === Structs ===

public struct DummyIntent() has copy, drop;
public struct WrongWitness() has copy, drop;

public struct Config has copy, drop, store {}
public struct Outcome has copy, drop, store {}

// === Helpers ===

fun start(): (Scenario, Extensions, Account<Config, Outcome>, Clock, UpgradeCap) {
    let mut scenario = ts::begin(OWNER);
    // publish package
    extensions::init_for_testing(scenario.ctx());
    // retrieve objects
    scenario.next_tx(OWNER);
    let mut extensions = scenario.take_shared<Extensions>();
    let cap = scenario.take_from_sender<AdminCap>();
    // add core deps
    extensions.add(&cap, b"AccountProtocol".to_string(), @account_protocol, 1);
    extensions.add(&cap, b"AccountActions".to_string(), @account_actions, 1);

    let mut account = account::new(&extensions, Config {}, false, vector[b"AccountProtocol".to_string()], vector[@account_protocol], vector[1], scenario.ctx());
    account.deps_mut_for_testing().add_for_testing(&extensions, b"AccountActions".to_string(), @account_actions, 1);
    let clock = clock::create_for_testing(scenario.ctx());
    let upgrade_cap = package::test_publish(@0x1.to_id(), scenario.ctx());
    // create world
    destroy(cap);
    (scenario, extensions, account, clock, upgrade_cap)
}

fun end(scenario: Scenario, extensions: Extensions, account: Account<Config, Outcome>, clock: Clock) {
    destroy(extensions);
    destroy(account);
    destroy(clock);
    ts::end(scenario);
}

fun create_dummy_intent(
    scenario: &mut Scenario,
    account: &mut Account<Config, Outcome>, 
): Intent<Outcome> {
    account.create_intent(
        b"dummy".to_string(), 
        b"".to_string(), 
        vector[0],
        1,
        b"Degen".to_string(), 
        Outcome {}, 
        version::current(), 
        DummyIntent(), 
        scenario.ctx()
    )
}

// === Tests ===

#[test]
fun test_lock() {
    let (mut scenario, extensions, mut account, clock, upgrade_cap) = start();

    let auth = account.new_auth(version::current(), DummyIntent());
    package_upgrade::lock_cap(auth, &mut account, upgrade_cap, b"Degen".to_string(), 1000);

    assert!(package_upgrade::has_cap(&account, b"Degen".to_string()));
    let cap = package_upgrade::borrow_cap(&account, @0x1);
    assert!(cap.package() == @0x1.to_id());

    let time_delay = package_upgrade::get_time_delay(&account, b"Degen".to_string());
    assert!(time_delay == 1000);

    end(scenario, extensions, account, clock);
}

#[test]
fun test_upgrade_flow() {
    let (mut scenario, extensions, mut account, mut clock, upgrade_cap) = start();
    let key = b"dummy".to_string();

    let auth = account.new_auth(version::current(), DummyIntent());
    package_upgrade::lock_cap(auth, &mut account, upgrade_cap, b"Degen".to_string(), 1000);

    let mut intent = create_dummy_intent(&mut scenario, &mut account);
    package_upgrade::new_upgrade(&mut intent, &account, b"Degen".to_string(), b"", &clock, version::current(), DummyIntent());
    account.add_intent(intent, version::current(), DummyIntent());
    clock.increment_for_testing(1000);

    let (mut executable, _) = account.execute_intent(key, &clock, version::current(), DummyIntent());
    let ticket = package_upgrade::do_upgrade(
        &mut executable, 
        &mut account, 
        &clock,
        version::current(), 
        DummyIntent(),
    );

    let receipt = ticket.test_upgrade();
    package_upgrade::confirm_upgrade(
        &executable, 
        &mut account, 
        receipt, 
        version::current(), 
        DummyIntent(),
    );
    account.confirm_execution(executable, version::current(), DummyIntent());

    end(scenario, extensions, account, clock);
}

#[test]
fun test_restrict_flow_additive() {
    let (mut scenario, extensions, mut account, clock, upgrade_cap) = start();
    let key = b"dummy".to_string();

    let auth = account.new_auth(version::current(), DummyIntent());
    package_upgrade::lock_cap(auth, &mut account, upgrade_cap, b"Degen".to_string(), 1000);

    let mut intent = create_dummy_intent(&mut scenario, &mut account);
    package_upgrade::new_restrict(&mut intent, &account, b"Degen".to_string(), 128, version::current(), DummyIntent());
    account.add_intent(intent, version::current(), DummyIntent());

    let (mut executable, _) = account.execute_intent(key, &clock, version::current(), DummyIntent());
    package_upgrade::do_restrict(
        &mut executable, 
        &mut account, 
        version::current(), 
        DummyIntent(),
    );
    account.confirm_execution(executable, version::current(), DummyIntent());

    let cap = package_upgrade::borrow_cap(&account, @0x1);
    assert!(cap.policy() == 128);

    end(scenario, extensions, account, clock);
}

#[test]
fun test_restrict_flow_deps_only() {
    let (mut scenario, extensions, mut account, clock, upgrade_cap) = start();
    let key = b"dummy".to_string();

    let auth = account.new_auth(version::current(), DummyIntent());
    package_upgrade::lock_cap(auth, &mut account, upgrade_cap, b"Degen".to_string(), 1000);

    let mut intent = create_dummy_intent(&mut scenario, &mut account);
    package_upgrade::new_restrict(&mut intent, &account, b"Degen".to_string(), 192, version::current(), DummyIntent());
    account.add_intent(intent, version::current(), DummyIntent());

    let (mut executable, _) = account.execute_intent(key, &clock, version::current(), DummyIntent());
    package_upgrade::do_restrict(
        &mut executable, 
        &mut account, 
        version::current(), 
        DummyIntent(),
    );
    account.confirm_execution(executable, version::current(), DummyIntent());

    let cap = package_upgrade::borrow_cap(&account, @0x1);
    assert!(cap.policy() == 192);

    end(scenario, extensions, account, clock);
}

#[test]
fun test_restrict_flow_immutable() {
    let (mut scenario, extensions, mut account, clock, upgrade_cap) = start();
    let key = b"dummy".to_string();

    let auth = account.new_auth(version::current(), DummyIntent());
    package_upgrade::lock_cap(auth, &mut account, upgrade_cap, b"Degen".to_string(), 1000);

    let mut intent = create_dummy_intent(&mut scenario, &mut account);
    package_upgrade::new_restrict(&mut intent, &account, b"Degen".to_string(), 255, version::current(), DummyIntent());
    account.add_intent(intent, version::current(), DummyIntent());

    let (mut executable, _) = account.execute_intent(key, &clock, version::current(), DummyIntent());
    package_upgrade::do_restrict(
        &mut executable, 
        &mut account, 
        version::current(), 
        DummyIntent(),
    );
    account.confirm_execution(executable, version::current(), DummyIntent());

    assert!(!package_upgrade::has_cap(&account, b"Degen".to_string()));

    end(scenario, extensions, account, clock);
}

#[test]
fun test_upgrade_expired() {
    let (mut scenario, extensions, mut account, mut clock, upgrade_cap) = start();
    clock.increment_for_testing(1);
    let key = b"dummy".to_string();

    let auth = account.new_auth(version::current(), DummyIntent());
    package_upgrade::lock_cap(auth, &mut account, upgrade_cap, b"Degen".to_string(), 1000);

    let mut intent = create_dummy_intent(&mut scenario, &mut account);
    package_upgrade::new_upgrade(&mut intent, &account, b"Degen".to_string(), b"", &clock, version::current(), DummyIntent());
    account.add_intent(intent, version::current(), DummyIntent());
    
    let mut expired = account.delete_expired_intent(key, &clock);
    package_upgrade::delete_upgrade(&mut expired);
    expired.destroy_empty();

    end(scenario, extensions, account, clock);
}

#[test]
fun test_restrict_expired() {
    let (mut scenario, extensions, mut account, mut clock, upgrade_cap) = start();
    clock.increment_for_testing(1);
    let key = b"dummy".to_string();

    let auth = account.new_auth(version::current(), DummyIntent());
    package_upgrade::lock_cap(auth, &mut account, upgrade_cap, b"Degen".to_string(), 1000);

    let mut intent = create_dummy_intent(&mut scenario, &mut account);
    package_upgrade::new_restrict(&mut intent, &account, b"Degen".to_string(), 128, version::current(), DummyIntent());
    account.add_intent(intent, version::current(), DummyIntent());
    
    let mut expired = account.delete_expired_intent(key, &clock);
    package_upgrade::delete_restrict(&mut expired);
    expired.destroy_empty();

    end(scenario, extensions, account, clock);
}

#[test, expected_failure(abort_code = package_upgrade::ELockAlreadyExists)]
fun test_error_lock_name_already_exists() {
    let (mut scenario, extensions, mut account, clock, upgrade_cap) = start();
    let upgrade_cap1 = package::test_publish(@0x1.to_id(), scenario.ctx());

    let auth = account.new_auth(version::current(), DummyIntent());
    package_upgrade::lock_cap(auth, &mut account, upgrade_cap, b"Degen".to_string(), 1000);
    let auth = account.new_auth(version::current(), DummyIntent());
    package_upgrade::lock_cap(auth, &mut account, upgrade_cap1, b"Degen".to_string(), 1000);

    end(scenario, extensions, account, clock);
}

#[test, expected_failure(abort_code = package_upgrade::ENoLock)]
fun test_error_new_upgrade_no_lock() {
    let (mut scenario, extensions, mut account, clock, upgrade_cap) = start();

    let mut intent = create_dummy_intent(&mut scenario, &mut account);
    package_upgrade::new_upgrade(
        &mut intent, 
        &account, 
        b"Degen".to_string(), 
        b"", 
        &clock, 
        version::current(), 
        DummyIntent()
    );

    destroy(intent);
    destroy(upgrade_cap);
    end(scenario, extensions, account, clock);
}

#[test, expected_failure(abort_code = package_upgrade::ENoLock)]
fun test_error_new_restrict_no_lock() {
    let (mut scenario, extensions, mut account, clock, upgrade_cap) = start();

    let mut intent = create_dummy_intent(&mut scenario, &mut account);
    package_upgrade::new_restrict(
        &mut intent, 
        &account, 
        b"Degen".to_string(), 
        128, 
        version::current(), 
        DummyIntent()
    );

    destroy(intent);
    destroy(upgrade_cap);
    end(scenario, extensions, account, clock);
}

#[test, expected_failure(abort_code = package_upgrade::EPolicyShouldRestrict)]
fun test_error_new_restrict_not_restrictive() {
    let (mut scenario, extensions, mut account, clock, upgrade_cap) = start();

    let auth = account.new_auth(version::current(), DummyIntent());
    package_upgrade::lock_cap(auth, &mut account, upgrade_cap, b"Degen".to_string(), 1000);

    let mut intent = create_dummy_intent(&mut scenario, &mut account);
    package_upgrade::new_restrict(&mut intent, &account, b"Degen".to_string(), 0, version::current(), DummyIntent());
    account.add_intent(intent, version::current(), DummyIntent());
    
    end(scenario, extensions, account, clock);
}

#[test, expected_failure(abort_code = package_upgrade::EInvalidPolicy)]
fun test_error_new_restrict_invalid_policy() {
    let (mut scenario, extensions, mut account, clock, upgrade_cap) = start();

    let auth = account.new_auth(version::current(), DummyIntent());
    package_upgrade::lock_cap(auth, &mut account, upgrade_cap, b"Degen".to_string(), 1000);

    let mut intent = create_dummy_intent(&mut scenario, &mut account);
    package_upgrade::new_restrict(&mut intent, &account, b"Degen".to_string(), 1, version::current(), DummyIntent());
    account.add_intent(intent, version::current(), DummyIntent());
    
    end(scenario, extensions, account, clock);
}

// sanity checks as these are tested in AccountProtocol tests

#[test, expected_failure(abort_code = issuer::EWrongAccount)]
fun test_error_do_upgrade_from_wrong_account() {
    let (mut scenario, extensions, mut account, clock, upgrade_cap) = start();
    let mut account2 = account::new(&extensions, Config {}, false, vector[b"AccountProtocol".to_string()], vector[@account_protocol], vector[1], scenario.ctx());
    account2.deps_mut_for_testing().add_for_testing(&extensions, b"AccountActions".to_string(), @account_actions, 1);
    let key = b"dummy".to_string();

    let auth = account.new_auth(version::current(), DummyIntent());
    package_upgrade::lock_cap(auth, &mut account, upgrade_cap, b"Degen".to_string(), 1000);
    // intent is submitted to other account
    let mut intent = create_dummy_intent(&mut scenario, &mut account2);
    package_upgrade::new_upgrade(&mut intent, &account, b"Degen".to_string(), b"", &clock, version::current(), DummyIntent());
    account2.add_intent(intent, version::current(), DummyIntent());

    let (mut executable, _) = account2.execute_intent(key, &clock, version::current(), DummyIntent());
    // try to burn from the right account that didn't approve the intent
    let ticket = package_upgrade::do_upgrade(
        &mut executable, 
        &mut account, 
        &clock,
        version::current(), 
        DummyIntent(),
    );

    destroy(account2);
    destroy(executable);
    destroy(ticket);
    end(scenario, extensions, account, clock);
}

#[test, expected_failure(abort_code = issuer::EWrongWitness)]
fun test_error_do_upgrade_from_wrong_constructor_witness() {
    let (mut scenario, extensions, mut account, clock, upgrade_cap) = start();
    let key = b"dummy".to_string();

    let auth = account.new_auth(version::current(), DummyIntent());
    package_upgrade::lock_cap(auth, &mut account, upgrade_cap, b"Degen".to_string(), 1000);

    let mut intent = create_dummy_intent(&mut scenario, &mut account);
    package_upgrade::new_upgrade(&mut intent, &account, b"Degen".to_string(), b"", &clock, version::current(), DummyIntent());
    account.add_intent(intent, version::current(), DummyIntent());

    let (mut executable, _) = account.execute_intent(key, &clock, version::current(), DummyIntent());
    // try to mint with the wrong witness that didn't approve the intent
    let ticket = package_upgrade::do_upgrade(
        &mut executable, 
        &mut account, 
        &clock,
        version::current(), 
        WrongWitness(),
    );

    destroy(executable);
    destroy(ticket);
    end(scenario, extensions, account, clock);
}

#[test, expected_failure(abort_code = deps::ENotDep)]
fun test_error_do_upgrade_from_not_dep() {
    let (mut scenario, extensions, mut account, clock, upgrade_cap) = start();
    let key = b"dummy".to_string();

    let auth = account.new_auth(version::current(), DummyIntent());
    package_upgrade::lock_cap(auth, &mut account, upgrade_cap, b"Degen".to_string(), 1000);

    let mut intent = create_dummy_intent(&mut scenario, &mut account);
    package_upgrade::new_upgrade(&mut intent, &account, b"Degen".to_string(), b"", &clock, version::current(), DummyIntent());
    account.add_intent(intent, version::current(), DummyIntent());

    let (mut executable, _) = account.execute_intent(key, &clock, version::current(), DummyIntent());
    // try to mint with the wrong version TypeName that didn't approve the intent
    let ticket = package_upgrade::do_upgrade(
        &mut executable, 
        &mut account, 
        &clock,
        version_witness::new_for_testing(@0xFA153), 
        DummyIntent(),
    );

    destroy(executable);
    destroy(ticket);
    end(scenario, extensions, account, clock);
}

#[test, expected_failure(abort_code = issuer::EWrongAccount)]
fun test_error_confirm_upgrade_from_wrong_account() {
    let (mut scenario, extensions, mut account, clock, upgrade_cap) = start();
    let mut account2 = account::new(&extensions, Config {}, false, vector[b"AccountProtocol".to_string()], vector[@account_protocol], vector[1], scenario.ctx());
    account2.deps_mut_for_testing().add_for_testing(&extensions, b"AccountActions".to_string(), @account_actions, 1);
    let key = b"dummy".to_string();

    let auth = account.new_auth(version::current(), DummyIntent());
    package_upgrade::lock_cap(auth, &mut account, upgrade_cap, b"Degen".to_string(), 0);
    let auth = account2.new_auth(version::current(), DummyIntent());
    package_upgrade::lock_cap(auth, &mut account2, package::test_publish(@0x1.to_id(), scenario.ctx()), b"Degen".to_string(), 1000);
    // intent is submitted to other account
    let mut intent = create_dummy_intent(&mut scenario, &mut account2);
    package_upgrade::new_upgrade(&mut intent, &account, b"Degen".to_string(), b"", &clock, version::current(), DummyIntent());
    account2.add_intent(intent, version::current(), DummyIntent());

    let (mut executable, _) = account2.execute_intent(key, &clock, version::current(), DummyIntent());
    // try to burn from the right account that didn't approve the intent
    let ticket = package_upgrade::do_upgrade(
        &mut executable, 
        &mut account2, 
        &clock,
        version::current(), 
        DummyIntent(),
    );

    let receipt = ticket.test_upgrade();
    package_upgrade::confirm_upgrade(
        &executable, 
        &mut account, 
        receipt, 
        version::current(), 
        DummyIntent(),
    );

    destroy(account2);
    destroy(executable);
    end(scenario, extensions, account, clock);
}

#[test, expected_failure(abort_code = issuer::EWrongWitness)]
fun test_error_confirm_upgrade_from_wrong_constructor_witness() {
    let (mut scenario, extensions, mut account, clock, upgrade_cap) = start();
    let key = b"dummy".to_string();

    let auth = account.new_auth(version::current(), DummyIntent());
    package_upgrade::lock_cap(auth, &mut account, upgrade_cap, b"Degen".to_string(), 0);

    let mut intent = create_dummy_intent(&mut scenario, &mut account);
    package_upgrade::new_upgrade(&mut intent, &account, b"Degen".to_string(), b"", &clock, version::current(), DummyIntent());
    account.add_intent(intent, version::current(), DummyIntent());

    let (mut executable, _) = account.execute_intent(key, &clock, version::current(), DummyIntent());
    // try to mint with the wrong witness that didn't approve the intent
    let ticket = package_upgrade::do_upgrade(
        &mut executable, 
        &mut account, 
        &clock,
        version::current(), 
        DummyIntent(),
    );

    let receipt = ticket.test_upgrade();
    package_upgrade::confirm_upgrade(
        &executable, 
        &mut account, 
        receipt, 
        version::current(), 
        WrongWitness(),
    );

    destroy(executable);
    end(scenario, extensions, account, clock);
}

#[test, expected_failure(abort_code = deps::ENotDep)]
fun test_error_confirm_upgrade_from_not_dep() {
    let (mut scenario, extensions, mut account, clock, upgrade_cap) = start();
    let key = b"dummy".to_string();

    let auth = account.new_auth(version::current(), DummyIntent());
    package_upgrade::lock_cap(auth, &mut account, upgrade_cap, b"Degen".to_string(), 0);

    let mut intent = create_dummy_intent(&mut scenario, &mut account);
    package_upgrade::new_upgrade(&mut intent, &account, b"Degen".to_string(), b"", &clock, version::current(), DummyIntent());
    account.add_intent(intent, version::current(), DummyIntent());

    let (mut executable, _) = account.execute_intent(key, &clock, version::current(), DummyIntent());
    // try to mint with the wrong version TypeName that didn't approve the intent
    let ticket = package_upgrade::do_upgrade(
        &mut executable, 
        &mut account, 
        &clock,
        version::current(), 
        DummyIntent(),
    );

    let receipt = ticket.test_upgrade();
    package_upgrade::confirm_upgrade(
        &executable, 
        &mut account, 
        receipt, 
        version_witness::new_for_testing(@0xFA153), 
        DummyIntent(),
    );

    destroy(executable);
    end(scenario, extensions, account, clock);
}

#[test, expected_failure(abort_code = issuer::EWrongAccount)]
fun test_error_do_restrict_from_wrong_account() {
    let (mut scenario, extensions, mut account, clock, upgrade_cap) = start();
    let mut account2 = account::new(&extensions, Config {}, false, vector[b"AccountProtocol".to_string()], vector[@account_protocol], vector[1], scenario.ctx());
    account2.deps_mut_for_testing().add_for_testing(&extensions, b"AccountActions".to_string(), @account_actions, 1);
    let key = b"dummy".to_string();

    let auth = account.new_auth(version::current(), DummyIntent());
    package_upgrade::lock_cap(auth, &mut account, upgrade_cap, b"Degen".to_string(), 1000);
    // intent is submitted to other account
    let mut intent = create_dummy_intent(&mut scenario, &mut account2);
    package_upgrade::new_upgrade(&mut intent, &account, b"Degen".to_string(), b"", &clock, version::current(), DummyIntent());
    account2.add_intent(intent, version::current(), DummyIntent());

    let (mut executable, _) = account2.execute_intent(key, &clock, version::current(), DummyIntent());
    // try to burn from the right account that didn't approve the intent
    package_upgrade::do_restrict(
        &mut executable, 
        &mut account, 
        version::current(), 
        DummyIntent(),
    );

    destroy(account2);
    destroy(executable);
    end(scenario, extensions, account, clock);
}

#[test, expected_failure(abort_code = issuer::EWrongWitness)]
fun test_error_do_restrict_from_wrong_constructor_witness() {
    let (mut scenario, extensions, mut account, clock, upgrade_cap) = start();
    let key = b"dummy".to_string();

    let auth = account.new_auth(version::current(), DummyIntent());
    package_upgrade::lock_cap(auth, &mut account, upgrade_cap, b"Degen".to_string(), 1000);

    let mut intent = create_dummy_intent(&mut scenario, &mut account);
    package_upgrade::new_upgrade(&mut intent, &account, b"Degen".to_string(), b"", &clock, version::current(), DummyIntent());
    account.add_intent(intent, version::current(), DummyIntent());

    let (mut executable, _) = account.execute_intent(key, &clock, version::current(), DummyIntent());
    // try to mint with the wrong witness that didn't approve the intent
    package_upgrade::do_restrict(
        &mut executable, 
        &mut account, 
        version::current(), 
        WrongWitness(),
    );

    destroy(executable);
    end(scenario, extensions, account, clock);
}

#[test, expected_failure(abort_code = deps::ENotDep)]
fun test_error_do_restrict_from_not_dep() {
    let (mut scenario, extensions, mut account, clock, upgrade_cap) = start();
    let key = b"dummy".to_string();

    let auth = account.new_auth(version::current(), DummyIntent());
    package_upgrade::lock_cap(auth, &mut account, upgrade_cap, b"Degen".to_string(), 1000);

    let mut intent = create_dummy_intent(&mut scenario, &mut account);
    package_upgrade::new_upgrade(&mut intent, &account, b"Degen".to_string(), b"", &clock, version::current(), DummyIntent());
    account.add_intent(intent, version::current(), DummyIntent());

    let (mut executable, _) = account.execute_intent(key, &clock, version::current(), DummyIntent());
    // try to mint with the wrong version TypeName that didn't approve the intent
    package_upgrade::do_restrict(
        &mut executable, 
        &mut account, 
        version_witness::new_for_testing(@0xFA153), 
        DummyIntent(),
    );

    destroy(executable);
    end(scenario, extensions, account, clock);
}