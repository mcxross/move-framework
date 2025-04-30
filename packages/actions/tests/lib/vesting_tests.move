#[test_only]
module account_actions::vesting_tests;

// === Imports ===

use sui::{
    test_utils::destroy,
    test_scenario::{Self as ts, Scenario},
    clock::{Self, Clock},
    coin::{Self, Coin},
    sui::SUI,
};
use account_extensions::extensions::{Self, Extensions, AdminCap};
use account_protocol::{
    account::{Self, Account},
    intents::{Self, Intent},
    deps,
};
use account_actions::{
    version,
    vesting,
};

// === Constants ===

const OWNER: address = @0xCAFE;

// === Structs ===

public struct DummyIntent() has copy, drop;
public struct WrongWitness() has copy, drop;

public struct Config has copy, drop, store {}
public struct Outcome has copy, drop, store {}

// === Helpers ===

fun start(): (Scenario, Extensions, Account<Config>, Clock) {
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

    let deps = deps::new_latest_extensions(&extensions, vector[b"AccountProtocol".to_string(), b"AccountActions".to_string()]);
    let account = account::new(Config {}, deps, version::current(), DummyIntent(), scenario.ctx());
    let clock = clock::create_for_testing(scenario.ctx());
    // create world
    destroy(cap);
    (scenario, extensions, account, clock)
}

fun end(scenario: Scenario, extensions: Extensions, account: Account<Config>, clock: Clock) {
    destroy(extensions);
    destroy(account);
    destroy(clock);
    ts::end(scenario);
}

fun create_dummy_intent(
    scenario: &mut Scenario,
    account: &Account<Config>, 
    clock: &Clock,
): Intent<Outcome> {
    let params = intents::new_params(
        b"dummy".to_string(), b"".to_string(), vector[0], 1, clock, scenario.ctx()
    );
    account.create_intent(
        params,
        Outcome {}, 
        b"Degen".to_string(), 
        version::current(), 
        DummyIntent(), 
        scenario.ctx()
    )
}

// === Tests ===

#[test]
fun test_create_vesting_claim_and_destroy() {
    let (mut scenario, extensions, account, mut clock) = start();

    let (cap, mut vesting) = vesting::create_vesting_for_testing(
        coin::mint_for_testing<SUI>(6, scenario.ctx()), 
        0, 
        6, 
        OWNER, 
        scenario.ctx()
    );

    clock.increment_for_testing(1);
    vesting.claim(&cap, &clock, scenario.ctx());
    scenario.next_tx(OWNER);
    let coin1 = scenario.take_from_address<Coin<SUI>>(OWNER);
    assert!(coin1.value() == 1);

    clock.increment_for_testing(2);
    vesting.claim(&cap, &clock, scenario.ctx());
    scenario.next_tx(OWNER);
    let coin2 = scenario.take_from_address<Coin<SUI>>(OWNER);
    assert!(coin2.value() == 2);
    
    clock.increment_for_testing(3);
    vesting.claim(&cap, &clock, scenario.ctx());
    scenario.next_tx(OWNER);
    let coin3 = scenario.take_from_address<Coin<SUI>>(OWNER);
    assert!(coin3.value() == 3);

    vesting.destroy_empty();
    cap.destroy();

    destroy(coin1);
    destroy(coin2);
    destroy(coin3);
    end(scenario, extensions, account, clock);
}

#[test]
fun test_create_vesting_claim_and_cancel() {
    let (mut scenario, extensions, account, mut clock) = start();

    let (cap, mut vesting) = vesting::create_vesting_for_testing(
        coin::mint_for_testing<SUI>(6, scenario.ctx()), 
        0, 
        6, 
        OWNER, 
        scenario.ctx()
    );

    clock.increment_for_testing(1);
    vesting.claim(&cap, &clock, scenario.ctx());
    scenario.next_tx(OWNER);
    let coin1 = scenario.take_from_address<Coin<SUI>>(OWNER);
    assert!(coin1.value() == 1);

    clock.increment_for_testing(2);
    vesting.claim(&cap, &clock, scenario.ctx());
    scenario.next_tx(OWNER);
    let coin2 = scenario.take_from_address<Coin<SUI>>(OWNER);
    assert!(coin2.value() == 2);
    
    clock.increment_for_testing(3);
    vesting.claim(&cap, &clock, scenario.ctx());
    scenario.next_tx(OWNER);
    let coin3 = scenario.take_from_address<Coin<SUI>>(OWNER);
    assert!(coin3.value() == 3);

    let auth = account.new_auth(version::current(), DummyIntent());
    vesting::cancel_payment(auth, vesting, &account, scenario.ctx());

    destroy(cap);
    destroy(coin1);
    destroy(coin2);
    destroy(coin3);
    end(scenario, extensions, account, clock);
}

#[test]
fun test_create_vesting_claim_after_end() {
    let (mut scenario, extensions, account, mut clock) = start();

    let (cap, mut vesting) = vesting::create_vesting_for_testing(
        coin::mint_for_testing<SUI>(6, scenario.ctx()), 
        0, 
        6, 
        OWNER, 
        scenario.ctx()
    );

    clock.increment_for_testing(10);
    vesting.claim(&cap, &clock, scenario.ctx());
    vesting.destroy_empty();
    
    scenario.next_tx(OWNER);
    let coin = scenario.take_from_address<Coin<SUI>>(OWNER);
    assert!(coin.value() == 6);

    destroy(cap);
    destroy(coin);
    end(scenario, extensions, account, clock);
}

#[test]
fun test_create_vesting_claim_same_time() {
    let (mut scenario, extensions, account, mut clock) = start();

    let (cap, mut vesting) = vesting::create_vesting_for_testing(
        coin::mint_for_testing<SUI>(6, scenario.ctx()), 
        0, 
        6, 
        OWNER, 
        scenario.ctx()
    );

    clock.increment_for_testing(3);
    
    vesting.claim(&cap, &clock, scenario.ctx());
    scenario.next_tx(OWNER);
    let coin1 = scenario.take_from_address<Coin<SUI>>(OWNER);
    assert!(coin1.value() == 3);
    vesting.claim(&cap, &clock, scenario.ctx());
    scenario.next_tx(OWNER);
    let coin2 = scenario.take_from_address<Coin<SUI>>(OWNER);
    assert!(coin2.value() == 0);

    destroy(vesting);
    destroy(cap);
    destroy(coin1);
    destroy(coin2);
    end(scenario, extensions, account, clock);
}

#[test]
fun test_vesting_flow() {
    let (mut scenario, extensions, mut account, clock) = start();
    let key = b"dummy".to_string();

    let mut intent = create_dummy_intent(&mut scenario, &account, &clock);
    vesting::new_vest(
        &mut intent, 
        0, 
        6,
        OWNER, 
        DummyIntent(), 
    );
    account.insert_intent(intent, version::current(), DummyIntent());

    let (_, mut executable) = account.create_executable(key, &clock, version::current(), DummyIntent());
    vesting::do_vest<Outcome, _, _>(
        &mut executable, 
        coin::mint_for_testing<SUI>(6, scenario.ctx()),
        DummyIntent(),
        scenario.ctx()
    );
    account.confirm_execution(executable);

    end(scenario, extensions, account, clock);
}

#[test]
fun test_vesting_expired() {
    let (mut scenario, extensions, mut account, mut clock) = start();
    clock.increment_for_testing(1);
    let key = b"dummy".to_string();

    let mut intent = create_dummy_intent(&mut scenario, &account, &clock);
    vesting::new_vest(
        &mut intent, 
        0, 
        6,
        OWNER, 
        DummyIntent(), 
    );
    account.insert_intent(intent, version::current(), DummyIntent());
    
    let mut expired = account.delete_expired_intent<_, Outcome>(key, &clock);
    vesting::delete_vest(&mut expired);
    expired.destroy_empty();

    end(scenario, extensions, account, clock);
}

#[test]
fun test_vesting_getters() {
    let (mut scenario, extensions, account, clock) = start();

    let (cap, vesting) = vesting::create_vesting_for_testing(
        coin::mint_for_testing<SUI>(6, scenario.ctx()), 
        0, 
        6, 
        OWNER, 
        scenario.ctx()
    );

    assert!(vesting.balance_value() == 6);
    assert!(vesting.last_claimed() == 0);
    assert!(vesting.start_timestamp() == 0);
    assert!(vesting.end_timestamp() == 6);
    assert!(vesting.recipient() == OWNER);

    destroy(cap);
    destroy(vesting);
    end(scenario, extensions, account, clock);
}

#[test, expected_failure(abort_code = vesting::EWrongStream)]
fun test_error_claim_wrong_vesting() {
    let (mut scenario, extensions, account, mut clock) = start();

    let (cap1, mut vesting1) = vesting::create_vesting_for_testing(
        coin::mint_for_testing<SUI>(6, scenario.ctx()), 
        0, 
        6, 
        OWNER, 
        scenario.ctx()
    );
    let (cap2, vesting2) = vesting::create_vesting_for_testing(
        coin::mint_for_testing<SUI>(6, scenario.ctx()), 
        0, 
        6, 
        OWNER, 
        scenario.ctx()
    );

    clock.increment_for_testing(1);
    vesting1.claim(&cap2, &clock, scenario.ctx());

    destroy(cap1);
    destroy(cap2);
    destroy(vesting1);
    destroy(vesting2);
    end(scenario, extensions, account, clock);
}

#[test, expected_failure(abort_code = vesting::ETooEarly)]
fun test_error_claim_too_early() {
    let (mut scenario, extensions, account, clock) = start();

    let (cap, mut vesting) = vesting::create_vesting_for_testing(
        coin::mint_for_testing<SUI>(6, scenario.ctx()), 
        0, 
        6, 
        OWNER, 
        scenario.ctx()
    );

    vesting.claim(&cap, &clock, scenario.ctx());

    destroy(cap);
    destroy(vesting);
    end(scenario, extensions, account, clock);
}

#[test, expected_failure(abort_code = vesting::EVestingOver)]
fun test_error_vesting_over() {
    let (mut scenario, extensions, account, mut clock) = start();

    let (cap, mut vesting) = vesting::create_vesting_for_testing(
        coin::mint_for_testing<SUI>(6, scenario.ctx()), 
        0, 
        6, 
        OWNER, 
        scenario.ctx()
    );

    clock.increment_for_testing(6);
    
    vesting.claim(&cap, &clock, scenario.ctx());
    scenario.next_tx(OWNER);
    let coin1 = scenario.take_from_address<Coin<SUI>>(OWNER);
    assert!(coin1.value() == 6);
    vesting.claim(&cap, &clock, scenario.ctx());
    scenario.next_tx(OWNER);
    let coin2 = scenario.take_from_address<Coin<SUI>>(OWNER);
    assert!(coin2.value() == 0);

    vesting.destroy_empty();
    destroy(cap);
    destroy(coin1);
    destroy(coin2);
    end(scenario, extensions, account, clock);
}

#[test, expected_failure(abort_code = vesting::EBalanceNotEmpty)]
fun test_error_destroy_non_empty_vesting() {
    let (mut scenario, extensions, account, clock) = start();

    let (cap, vesting) = vesting::create_vesting_for_testing(
        coin::mint_for_testing<SUI>(6, scenario.ctx()), 
        0, 
        6, 
        OWNER, 
        scenario.ctx()
    );

    vesting.destroy_empty();

    destroy(cap);
    end(scenario, extensions, account, clock);
}

// sanity checks as these are tested in AccountProtocol tests

#[test, expected_failure(abort_code = intents::EWrongWitness)]
fun test_error_do_vesting_from_wrong_constructor_witness() {
    let (mut scenario, extensions, mut account, clock) = start();
    let key = b"dummy".to_string();

    let mut intent = create_dummy_intent(&mut scenario, &account, &clock);
    vesting::new_vest(&mut intent, 0, 1, OWNER, DummyIntent());
    account.insert_intent(intent, version::current(), DummyIntent());

    let (_, mut executable) = account.create_executable(key, &clock, version::current(), DummyIntent());
    // try to disable with the wrong witness that didn't approve the intent
    vesting::do_vest<Outcome, _, _>(
        &mut executable, 
        coin::mint_for_testing<SUI>(6, scenario.ctx()),
        WrongWitness(),
        scenario.ctx()
    );

    destroy(executable);
    end(scenario, extensions, account, clock);
}