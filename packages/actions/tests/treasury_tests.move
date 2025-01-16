#[test_only]
module account_actions::treasury_tests;

// === Imports ===

use std::type_name::{Self, TypeName};
use sui::{
    test_utils::destroy,
    test_scenario::{Self as ts, Scenario},
    clock::{Self, Clock},
    coin::{Self, Coin},
    sui::SUI,
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
    treasury,
    vesting::{Self, Stream},
    transfer as acc_transfer,
};

// === Constants ===

const OWNER: address = @0xCAFE;

// === Structs ===

public struct TREASURY_TESTS has drop {}

public struct DummyIntent() has copy, drop;

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

fun keep_coin(addr: address, amount: u64, scenario: &mut Scenario): ID {
    let coin = coin::mint_for_testing<SUI>(amount, scenario.ctx());
    let id = object::id(&coin);
    transfer::public_transfer(coin, addr);
    
    scenario.next_tx(OWNER);
    id
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
        b"Degen".to_string(), 
        scenario.ctx()
    )
}

// === Tests ===

#[test]
fun test_open_treasury() {
    let (mut scenario, extensions, mut account, clock) = start();

    assert!(!treasury::has_treasury(&account, b"Degen".to_string()));
    let auth = multisig::authenticate(&extensions, &account, scenario.ctx());
    treasury::open(auth, &mut account, b"Degen".to_string(), scenario.ctx());
    assert!(treasury::has_treasury(&account, b"Degen".to_string()));

    end(scenario, extensions, account, clock);
}

#[test]
fun test_deposit_owned() {
    let (mut scenario, extensions, mut account, clock) = start();

    let auth = multisig::authenticate(&extensions, &account, scenario.ctx());
    treasury::open(auth, &mut account, b"Degen".to_string(), scenario.ctx());

    let id = keep_coin(account.addr(), 5, &mut scenario);
    let auth = multisig::authenticate(&extensions, &account, scenario.ctx());
    treasury::deposit_owned<Multisig, Approvals, SUI>(
        auth, 
        &mut account, 
        b"Degen".to_string(), 
        ts::receiving_ticket_by_id(id)
    );

    let treasury = treasury::borrow_treasury(&account, b"Degen".to_string());
    assert!(treasury.coin_type_exists<SUI>());
    assert!(treasury.coin_type_value<SUI>() == 5);

    end(scenario, extensions, account, clock);
}

#[test]
fun test_deposit() {
    let (mut scenario, extensions, mut account, clock) = start();

    let auth = multisig::authenticate(&extensions, &account, scenario.ctx());
    treasury::open(auth, &mut account, b"Degen".to_string(), scenario.ctx());

    let auth = multisig::authenticate(&extensions, &account, scenario.ctx());
    treasury::deposit<Multisig, Approvals, SUI>(
        auth, 
        &mut account, 
        b"Degen".to_string(), 
        coin::mint_for_testing<SUI>(5, scenario.ctx())
    );
    let auth = multisig::authenticate(&extensions, &account, scenario.ctx());
    treasury::deposit<Multisig, Approvals, SUI>(
        auth, 
        &mut account, 
        b"Degen".to_string(), 
        coin::mint_for_testing<SUI>(5, scenario.ctx())
    );
    let auth = multisig::authenticate(&extensions, &account, scenario.ctx());
    treasury::deposit<Multisig, Approvals, TREASURY_TESTS>(
        auth, 
        &mut account, 
        b"Degen".to_string(), 
        coin::mint_for_testing<TREASURY_TESTS>(5, scenario.ctx())
    );

    let treasury = treasury::borrow_treasury(&account, b"Degen".to_string());
    assert!(treasury.coin_type_exists<SUI>());
    assert!(treasury.coin_type_value<SUI>() == 10);
    assert!(treasury.coin_type_exists<TREASURY_TESTS>());
    assert!(treasury.coin_type_value<TREASURY_TESTS>() == 5);

    end(scenario, extensions, account, clock);
}

#[test]
fun test_close_treasury() {
    let (mut scenario, extensions, mut account, clock) = start();

    let auth = multisig::authenticate(&extensions, &account, scenario.ctx());
    treasury::open(auth, &mut account, b"Degen".to_string(), scenario.ctx());
    assert!(treasury::has_treasury(&account, b"Degen".to_string()));

    let auth = multisig::authenticate(&extensions, &account, scenario.ctx());
    treasury::deposit<Multisig, Approvals, SUI>(
        auth, 
        &mut account, 
        b"Degen".to_string(), 
        coin::mint_for_testing<SUI>(5, scenario.ctx())
    );

    let mut intent = create_dummy_intent(&mut scenario, &mut account, &extensions);
    treasury::new_spend<Approvals, SUI, DummyIntent>(
        &mut intent, 
        5,
        DummyIntent(),
    );
    account.add_intent(intent, version::current(), DummyIntent());
    multisig::approve_intent(&mut account, b"dummy".to_string(), scenario.ctx());
    let mut executable = multisig::execute_intent(&mut account, b"dummy".to_string(), &clock);
    let coin = treasury::do_spend<Multisig, Approvals, SUI, DummyIntent>(
        &mut executable, 
        &mut account, 
        version::current(), 
        DummyIntent(),
        scenario.ctx()
    );
    account.confirm_execution(executable, version::current(), DummyIntent());

    let auth = multisig::authenticate(&extensions, &account, scenario.ctx());
    treasury::close(auth, &mut account, b"Degen".to_string());
    assert!(!treasury::has_treasury(&account, b"Degen".to_string()));

    destroy(coin);
    end(scenario, extensions, account, clock);
}

#[test]
fun test_request_execute_transfer() {
    let (mut scenario, extensions, mut account, clock) = start();
    let auth = multisig::authenticate(&extensions, &account, scenario.ctx());
    treasury::open(auth, &mut account, b"Degen".to_string(), scenario.ctx());
    let key = b"dummy".to_string();

    let auth = multisig::authenticate(&extensions, &account, scenario.ctx());
    treasury::deposit<Multisig, Approvals, SUI>(
        auth, 
        &mut account, 
        b"Degen".to_string(), 
        coin::mint_for_testing<SUI>(5, scenario.ctx())
    );

    let auth = multisig::authenticate(&extensions, &account, scenario.ctx());
    let outcome = multisig::empty_outcome(&account, scenario.ctx());
    treasury::request_transfer<Multisig, Approvals, SUI>(
        auth, 
        outcome, 
        &mut account, 
        key, 
        b"".to_string(), 
        vector[0], 
        1, 
        b"Degen".to_string(),
        vector[1, 2],
        vector[@0x1, @0x2],
        scenario.ctx()
    );

    multisig::approve_intent(&mut account, key, scenario.ctx());
    let mut executable = multisig::execute_intent(&mut account, key, &clock);
    // loop over execute_transfer to execute each action
    treasury::execute_transfer<Multisig, Approvals, SUI>(&mut executable, &mut account, scenario.ctx());
    treasury::execute_transfer<Multisig, Approvals, SUI>(&mut executable, &mut account, scenario.ctx());
    treasury::complete_transfer(executable, &account);

    let mut expired = account.destroy_empty_intent(key);
    treasury::delete_spend<SUI>(&mut expired);
    acc_transfer::delete_transfer(&mut expired);
    treasury::delete_spend<SUI>(&mut expired);
    acc_transfer::delete_transfer(&mut expired);
    expired.destroy_empty();

    scenario.next_tx(OWNER);
    let coin1 = scenario.take_from_address<Coin<SUI>>(@0x1);
    assert!(coin1.value() == 1);
    let coin2 = scenario.take_from_address<Coin<SUI>>(@0x2);
    assert!(coin2.value() == 2);

    destroy(coin1);
    destroy(coin2);
    end(scenario, extensions, account, clock);
}

#[test]
fun test_request_execute_vesting() {
    let (mut scenario, extensions, mut account, clock) = start();
    let auth = multisig::authenticate(&extensions, &account, scenario.ctx());
    treasury::open(auth, &mut account, b"Degen".to_string(), scenario.ctx());
    let key = b"dummy".to_string();

    let auth = multisig::authenticate(&extensions, &account, scenario.ctx());
    treasury::deposit<Multisig, Approvals, SUI>(
        auth, 
        &mut account, 
        b"Degen".to_string(), 
        coin::mint_for_testing<SUI>(5, scenario.ctx())
    );

    let auth = multisig::authenticate(&extensions, &account, scenario.ctx());
    let outcome = multisig::empty_outcome(&account, scenario.ctx());
    treasury::request_vesting<Multisig, Approvals, SUI>(
        auth, 
        outcome, 
        &mut account, 
        key, 
        b"".to_string(), 
        0, 
        1,
        b"Degen".to_string(),
        5, 
        1,
        2,
        @0x1,
        scenario.ctx()
    );

    multisig::approve_intent(&mut account, key, scenario.ctx());
    let executable = multisig::execute_intent(&mut account, key, &clock);
    treasury::execute_vesting<Multisig, Approvals, SUI>(executable, &mut account, scenario.ctx());

    let mut expired = account.destroy_empty_intent(key);
    treasury::delete_spend<SUI>(&mut expired);
    vesting::delete_vesting(&mut expired);
    expired.destroy_empty();

    scenario.next_tx(OWNER);
    let stream = scenario.take_shared<Stream<SUI>>();
    assert!(stream.balance_value() == 5);
    assert!(stream.last_claimed() == 0);
    assert!(stream.start_timestamp() == 1);
    assert!(stream.end_timestamp() == 2);
    assert!(stream.recipient() == @0x1);

    destroy(stream);
    end(scenario, extensions, account, clock);
}

#[test]
fun test_spend_flow() {
    let (mut scenario, extensions, mut account, clock) = start();
    let auth = multisig::authenticate(&extensions, &account, scenario.ctx());
    treasury::open(auth, &mut account, b"Degen".to_string(), scenario.ctx());
    let key = b"dummy".to_string();

    let auth = multisig::authenticate(&extensions, &account, scenario.ctx());
    treasury::deposit<Multisig, Approvals, SUI>(
        auth, 
        &mut account, 
        b"Degen".to_string(), 
        coin::mint_for_testing<SUI>(5, scenario.ctx())
    );

    let mut intent = create_dummy_intent(&mut scenario, &mut account, &extensions);
    treasury::new_spend<Approvals, SUI, DummyIntent>(
        &mut intent, 
        2,
        DummyIntent(),
    );
    account.add_intent(intent, version::current(), DummyIntent());

    multisig::approve_intent(&mut account, key, scenario.ctx());
    let mut executable = multisig::execute_intent(&mut account, key, &clock);
    let coin = treasury::do_spend<Multisig, Approvals, SUI, DummyIntent>(
        &mut executable, 
        &mut account, 
        version::current(), 
        DummyIntent(),
        scenario.ctx()
    );
    account.confirm_execution(executable, version::current(), DummyIntent());

    let treasury = treasury::borrow_treasury(&account, b"Degen".to_string());
    assert!(treasury.coin_type_value<SUI>() == 3);
    assert!(coin.value() == 2);

    destroy(coin);
    end(scenario, extensions, account, clock);
}

#[test]
fun test_disable_expired() {
    let (mut scenario, extensions, mut account, mut clock) = start();
    clock.increment_for_testing(1);
    let key = b"dummy".to_string();

    let mut intent = create_dummy_intent(&mut scenario, &mut account, &extensions);
    treasury::new_spend<Approvals, SUI, DummyIntent>(
        &mut intent, 
        2,
        DummyIntent(),
    );
    account.add_intent(intent, version::current(), DummyIntent());
    
    let mut expired = account.delete_expired_intent(key, &clock);
    treasury::delete_spend<SUI>(&mut expired);
    expired.destroy_empty();

    end(scenario, extensions, account, clock);
}

#[test, expected_failure(abort_code = treasury::EAlreadyExists)]
fun test_error_open_treasury_already_exists() {
    let (mut scenario, extensions, mut account, clock) = start();

    let auth = multisig::authenticate(&extensions, &account, scenario.ctx());
    treasury::open(auth, &mut account, b"Degen".to_string(), scenario.ctx());
    let auth = multisig::authenticate(&extensions, &account, scenario.ctx());
    treasury::open(auth, &mut account, b"Degen".to_string(), scenario.ctx());

    end(scenario, extensions, account, clock);
}

#[test, expected_failure(abort_code = treasury::ETreasuryDoesntExist)]
fun test_error_deposit_treasury_doesnt_exist() {
    let (mut scenario, extensions, mut account, clock) = start();

    let auth = multisig::authenticate(&extensions, &account, scenario.ctx());
    treasury::deposit<Multisig, Approvals, SUI>(
        auth, 
        &mut account, 
        b"Degen".to_string(), 
        coin::mint_for_testing<SUI>(5, scenario.ctx())
    );

    end(scenario, extensions, account, clock);
}

#[test, expected_failure(abort_code = treasury::ENotEmpty)]
fun test_error_close_not_empty() {
    let (mut scenario, extensions, mut account, clock) = start();

    let auth = multisig::authenticate(&extensions, &account, scenario.ctx());
    treasury::open(auth, &mut account, b"Degen".to_string(), scenario.ctx());

    let auth = multisig::authenticate(&extensions, &account, scenario.ctx());
    treasury::deposit<Multisig, Approvals, SUI>(
        auth, 
        &mut account, 
        b"Degen".to_string(), 
        coin::mint_for_testing<SUI>(5, scenario.ctx())
    );

    let auth = multisig::authenticate(&extensions, &account, scenario.ctx());
    treasury::close(auth, &mut account, b"Degen".to_string());

    end(scenario, extensions, account, clock);
}

#[test, expected_failure(abort_code = treasury::ENotSameLength)]
fun test_error_request_transfer_not_same_length() {
    let (mut scenario, extensions, mut account, clock) = start();
    let auth = multisig::authenticate(&extensions, &account, scenario.ctx());
    treasury::open(auth, &mut account, b"Degen".to_string(), scenario.ctx());
    let key = b"dummy".to_string();

    let auth = multisig::authenticate(&extensions, &account, scenario.ctx());
    treasury::deposit<Multisig, Approvals, SUI>(
        auth, 
        &mut account, 
        b"Degen".to_string(), 
        coin::mint_for_testing<SUI>(5, scenario.ctx())
    );

    let auth = multisig::authenticate(&extensions, &account, scenario.ctx());
    let outcome = multisig::empty_outcome(&account, scenario.ctx());
    treasury::request_transfer<Multisig, Approvals, SUI>(
        auth, 
        outcome, 
        &mut account, 
        key, 
        b"".to_string(), 
        vector[0], 
        1, 
        b"Degen".to_string(),
        vector[1, 2],
        vector[@0x1],
        scenario.ctx()
    );

    end(scenario, extensions, account, clock);
}

#[test, expected_failure(abort_code = treasury::ECoinTypeDoesntExist)]
fun test_error_request_transfer_coin_type_doesnt_exist() {
    let (mut scenario, extensions, mut account, clock) = start();
    let auth = multisig::authenticate(&extensions, &account, scenario.ctx());
    treasury::open(auth, &mut account, b"Degen".to_string(), scenario.ctx());
    let key = b"dummy".to_string();

    let auth = multisig::authenticate(&extensions, &account, scenario.ctx());
    treasury::deposit<Multisig, Approvals, TREASURY_TESTS>(
        auth, 
        &mut account, 
        b"Degen".to_string(), 
        coin::mint_for_testing<TREASURY_TESTS>(5, scenario.ctx())
    );

    let auth = multisig::authenticate(&extensions, &account, scenario.ctx());
    let outcome = multisig::empty_outcome(&account, scenario.ctx());
    treasury::request_transfer<Multisig, Approvals, SUI>(
        auth, 
        outcome, 
        &mut account, 
        key, 
        b"".to_string(), 
        vector[0], 
        1, 
        b"Degen".to_string(),
        vector[1, 2],
        vector[@0x1, @0x2],
        scenario.ctx()
    );

    end(scenario, extensions, account, clock);
}

#[test, expected_failure(abort_code = treasury::EInsufficientFunds)]
fun test_error_request_transfer_insufficient_funds() {
    let (mut scenario, extensions, mut account, clock) = start();
    let auth = multisig::authenticate(&extensions, &account, scenario.ctx());
    treasury::open(auth, &mut account, b"Degen".to_string(), scenario.ctx());
    let key = b"dummy".to_string();

    let auth = multisig::authenticate(&extensions, &account, scenario.ctx());
    treasury::deposit<Multisig, Approvals, SUI>(
        auth, 
        &mut account, 
        b"Degen".to_string(), 
        coin::mint_for_testing<SUI>(1, scenario.ctx())
    );

    let auth = multisig::authenticate(&extensions, &account, scenario.ctx());
    let outcome = multisig::empty_outcome(&account, scenario.ctx());
    treasury::request_transfer<Multisig, Approvals, SUI>(
        auth, 
        outcome, 
        &mut account, 
        key, 
        b"".to_string(), 
        vector[0], 
        1, 
        b"Degen".to_string(),
        vector[1, 2],
        vector[@0x1, @0x2],
        scenario.ctx()
    );

    end(scenario, extensions, account, clock);
}

#[test, expected_failure(abort_code = treasury::ECoinTypeDoesntExist)]
fun test_error_request_vesting_coin_type_doesnt_exist() {
    let (mut scenario, extensions, mut account, clock) = start();
    let auth = multisig::authenticate(&extensions, &account, scenario.ctx());
    treasury::open(auth, &mut account, b"Degen".to_string(), scenario.ctx());
    let key = b"dummy".to_string();

    let auth = multisig::authenticate(&extensions, &account, scenario.ctx());
    treasury::deposit<Multisig, Approvals, TREASURY_TESTS>(
        auth, 
        &mut account, 
        b"Degen".to_string(), 
        coin::mint_for_testing<TREASURY_TESTS>(5, scenario.ctx())
    );

    let auth = multisig::authenticate(&extensions, &account, scenario.ctx());
    let outcome = multisig::empty_outcome(&account, scenario.ctx());
    treasury::request_vesting<Multisig, Approvals, SUI>(
        auth, 
        outcome, 
        &mut account, 
        key, 
        b"".to_string(), 
        0, 
        1,
        b"Degen".to_string(),
        5, 
        1,
        2,
        @0x1,
        scenario.ctx()
    );

    end(scenario, extensions, account, clock);
}

#[test, expected_failure(abort_code = treasury::EInsufficientFunds)]
fun test_error_request_vesting_insufficient_funds() {
    let (mut scenario, extensions, mut account, clock) = start();
    let auth = multisig::authenticate(&extensions, &account, scenario.ctx());
    treasury::open(auth, &mut account, b"Degen".to_string(), scenario.ctx());
    let key = b"dummy".to_string();

    let auth = multisig::authenticate(&extensions, &account, scenario.ctx());
    treasury::deposit<Multisig, Approvals, SUI>(
        auth, 
        &mut account, 
        b"Degen".to_string(), 
        coin::mint_for_testing<SUI>(4, scenario.ctx())
    );

    let auth = multisig::authenticate(&extensions, &account, scenario.ctx());
    let outcome = multisig::empty_outcome(&account, scenario.ctx());
    treasury::request_vesting<Multisig, Approvals, SUI>(
        auth, 
        outcome, 
        &mut account, 
        key, 
        b"".to_string(), 
        0, 
        1,
        b"Degen".to_string(),
        5, 
        1,
        2,
        @0x1,
        scenario.ctx()
    );

    end(scenario, extensions, account, clock);
}

// sanity checks as these are tested in AccountProtocol tests

#[test, expected_failure(abort_code = issuer::EWrongAccount)]
fun test_error_do_update_from_wrong_account() {
    let (mut scenario, extensions, mut account, clock) = start();
    let auth = multisig::authenticate(&extensions, &account, scenario.ctx());
    treasury::open(auth, &mut account, b"Degen".to_string(), scenario.ctx());
    let key = b"dummy".to_string();

    let mut account2 = multisig::new_account(&extensions, scenario.ctx());
    // intent is submitted to other account
    let mut intent = create_dummy_intent(&mut scenario, &mut account2, &extensions);
    treasury::new_spend<Approvals, SUI, DummyIntent>(
        &mut intent, 
        2,
        DummyIntent(),
    );
    account2.add_intent(intent, version::current(), DummyIntent());

    multisig::approve_intent(&mut account2, key, scenario.ctx());
    let mut executable = multisig::execute_intent(&mut account2, key, &clock);
    // try to burn from the right account that didn't approve the intent
    let coin = treasury::do_spend<Multisig, Approvals, SUI, DummyIntent>(
        &mut executable, 
        &mut account, 
        version::current(), 
        DummyIntent(),
        scenario.ctx()
    );

    destroy(coin);
    destroy(account2);
    destroy(executable);
    end(scenario, extensions, account, clock);
}

#[test, expected_failure(abort_code = issuer::EWrongWitness)]
fun test_error_do_update_from_wrong_constructor_witness() {
    let (mut scenario, extensions, mut account, clock) = start();
    let auth = multisig::authenticate(&extensions, &account, scenario.ctx());
    treasury::open(auth, &mut account, b"Degen".to_string(), scenario.ctx());
    let key = b"dummy".to_string();

    let mut intent = create_dummy_intent(&mut scenario, &mut account, &extensions);
    treasury::new_spend<Approvals, SUI, DummyIntent>(
        &mut intent, 
        2,
        DummyIntent(),
    );
    account.add_intent(intent, version::current(), DummyIntent());

    multisig::approve_intent(&mut account, key, scenario.ctx());
    let mut executable = multisig::execute_intent(&mut account, key, &clock);
    // try to mint with the wrong witness that didn't approve the intent
    let coin = treasury::do_spend<Multisig, Approvals, SUI, issuer::WrongWitness>(
        &mut executable, 
        &mut account, 
        version::current(), 
        issuer::wrong_witness(),
        scenario.ctx()
    );

    destroy(coin);
    destroy(executable);
    end(scenario, extensions, account, clock);
}

#[test, expected_failure(abort_code = deps::ENotDep)]
fun test_error_do_update_from_not_dep() {
    let (mut scenario, extensions, mut account, clock) = start();
    let auth = multisig::authenticate(&extensions, &account, scenario.ctx());
    treasury::open(auth, &mut account, b"Degen".to_string(), scenario.ctx());
    let key = b"dummy".to_string();

    let mut intent = create_dummy_intent(&mut scenario, &mut account, &extensions);
    treasury::new_spend<Approvals, SUI, DummyIntent>(
        &mut intent, 
        2,
        DummyIntent(),
    );
    account.add_intent(intent, version::current(), DummyIntent());

    multisig::approve_intent(&mut account, key, scenario.ctx());
    let mut executable = multisig::execute_intent(&mut account, key, &clock);
    // try to mint with the wrong version TypeName that didn't approve the intent
    let coin = treasury::do_spend<Multisig, Approvals, SUI, DummyIntent>(
        &mut executable, 
        &mut account, 
        wrong_version(), 
        DummyIntent(),
        scenario.ctx()
    );

    destroy(coin);
    destroy(executable);
    end(scenario, extensions, account, clock);
}