#[test_only]
module account_actions::kiosk_tests;

// === Imports ===

use sui::{
    test_utils::destroy,
    test_scenario::{Self as ts, Scenario},
    kiosk::{Self, Kiosk, KioskOwnerCap},
    package,
    clock::{Self, Clock},
    transfer_policy::{Self, TransferPolicy},
    coin::{Self, Coin},
    sui::SUI,
};
use kiosk::{kiosk_lock_rule, royalty_rule};
use account_extensions::extensions::{Self, Extensions, AdminCap};
use account_protocol::{
    account::{Self, Account},
    intents::{Self, Intent},
    deps,
};
use account_actions::{
    version,
    kiosk as acc_kiosk,
    kiosk_intents as acc_kiosk_intents,
};

// === Constants ===

const OWNER: address = @0xCAFE;
const ALICE: address = @0xA11CE;
// === Structs ===

public struct KIOSK_TESTS has drop {}

public struct Nft has key, store {
    id: UID
}

public struct DummyIntent() has copy, drop;
public struct WrongWitness() has copy, drop;

public struct Config has copy, drop, store {}
public struct Outcome has copy, drop, store {}

// === Helpers ===

fun start(): (Scenario, Extensions, Account<Config>, Clock, TransferPolicy<Nft>) {
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
    // instantiate TransferPolicy 
    let publisher = package::test_claim(KIOSK_TESTS {}, scenario.ctx());
    let (mut policy, policy_cap) = transfer_policy::new<Nft>(&publisher, scenario.ctx());
    royalty_rule::add(&mut policy, &policy_cap, 100, 0);
    kiosk_lock_rule::add(&mut policy, &policy_cap);
    // create world
    destroy(cap);
    destroy(policy_cap);
    destroy(publisher);
    (scenario, extensions, account, clock, policy)
}

fun end(scenario: Scenario, extensions: Extensions, account: Account<Config>, clock: Clock, policy: TransferPolicy<Nft>) {
    destroy(extensions);
    destroy(account);
    destroy(policy);
    destroy(clock);
    ts::end(scenario);
}

fun init_caller_kiosk_with_nfts(policy: &TransferPolicy<Nft>, amount: u64, scenario: &mut Scenario): (Kiosk, KioskOwnerCap, vector<ID>) {
    let (mut kiosk, kiosk_cap) = kiosk::new(scenario.ctx());
    let mut ids = vector[];

    amount.do!(|_| {
        let nft = Nft { id: object::new(scenario.ctx()) };
        ids.push_back(object::id(&nft));
        kiosk.lock(&kiosk_cap, policy, nft);
    });

    (kiosk, kiosk_cap, ids)
}

fun init_account_kiosk_with_nfts(account: &mut Account<Config>, policy: &mut TransferPolicy<Nft>, amount: u64, scenario: &mut Scenario): (Kiosk, vector<ID>) {
    let auth = account.new_auth(version::current(), DummyIntent());
    acc_kiosk::open(auth, account, b"Degen".to_string(), scenario.ctx());
    scenario.next_tx(OWNER);
    let mut acc_kiosk = scenario.take_shared<Kiosk>();
    
    let (mut kiosk, kiosk_cap, ids) = init_caller_kiosk_with_nfts(policy, amount, scenario);
    let mut nft_ids = ids;

    amount.do!(|_| {
        let auth = account.new_auth(version::current(), DummyIntent());
        let request = acc_kiosk::place(
            auth, 
            account, 
            &mut acc_kiosk, 
            &mut kiosk,
            &kiosk_cap, 
            policy,
            b"Degen".to_string(),
            nft_ids.pop_back(),
            scenario.ctx()
        );
        policy.confirm_request(request);
    });

    destroy(kiosk);
    destroy(kiosk_cap);
    (acc_kiosk, ids)
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
fun test_open_kiosk() {
    let (mut scenario, extensions, mut account, clock, policy) = start();

    assert!(!acc_kiosk::has_lock(&account, b"Degen".to_string()));
    let auth = account.new_auth(version::current(), DummyIntent());
    acc_kiosk::open(auth, &mut account, b"Degen".to_string(), scenario.ctx());
    assert!(acc_kiosk::has_lock(&account, b"Degen".to_string()));

    scenario.next_tx(OWNER);
    let kiosk = scenario.take_shared<Kiosk>();
    assert!(kiosk.owner() == account.addr());

    destroy(kiosk);
    end(scenario, extensions, account, clock, policy);
}

#[test]
fun test_place_into_kiosk() {
    let (mut scenario, extensions, mut account, clock, mut policy) = start();
    // open a Kiosk for the caller and for the Account
    let (mut acc_kiosk, _) = init_account_kiosk_with_nfts(&mut account, &mut policy, 0, &mut scenario);
    let (mut caller_kiosk, caller_cap, mut ids) = init_caller_kiosk_with_nfts(&policy, 1, &mut scenario);

    let auth = account.new_auth(version::current(), DummyIntent());
    let request = acc_kiosk::place(
        auth, 
        &mut account, 
        &mut acc_kiosk, 
        &mut caller_kiosk,
        &caller_cap, 
        &mut policy,
        b"Degen".to_string(),
        ids.pop_back(),
        scenario.ctx()
    );
    policy.confirm_request(request);

    destroy(acc_kiosk);
    destroy(caller_kiosk);
    destroy(caller_cap);
    end(scenario, extensions, account, clock, policy);
}

#[test]
fun test_place_into_kiosk_without_rules() {
    let (mut scenario, extensions, mut account, clock, mut policy) = start();
    // open a Kiosk for the caller and for the Account
    let (mut acc_kiosk, _) = init_account_kiosk_with_nfts(&mut account, &mut policy, 0, &mut scenario);
    let (mut caller_kiosk, caller_cap, mut ids) = init_caller_kiosk_with_nfts(&policy, 1, &mut scenario);
    
    let publisher = package::test_claim(KIOSK_TESTS {}, scenario.ctx());
    let (mut empty_policy, policy_cap) = transfer_policy::new<Nft>(&publisher, scenario.ctx());

    let auth = account.new_auth(version::current(), DummyIntent());
    let request = acc_kiosk::place(
        auth, 
        &mut account, 
        &mut acc_kiosk, 
        &mut caller_kiosk,
        &caller_cap, 
        &mut empty_policy,
        b"Degen".to_string(),
        ids.pop_back(),
        scenario.ctx()
    );
    empty_policy.confirm_request(request);

    destroy(acc_kiosk);
    destroy(caller_kiosk);
    destroy(caller_cap);
    destroy(empty_policy);
    destroy(policy_cap);
    destroy(publisher);
    end(scenario, extensions, account, clock, policy);
}

#[test]
fun test_delist_nfts() {
    let (mut scenario, extensions, mut account, clock, mut policy) = start();
    // open a Kiosk for the caller and for the Account
    let (mut acc_kiosk, mut ids) = init_account_kiosk_with_nfts(&mut account, &mut policy, 2, &mut scenario);

    // list nfts
    let auth = account.new_auth(version::current(), DummyIntent());
    let params = intents::new_params(
        b"dummy".to_string(), b"".to_string(), vector[0], 1, &clock, scenario.ctx()
    );
    acc_kiosk_intents::request_list_nfts(
        auth, 
        &mut account, 
        params,
        Outcome {},
        b"Degen".to_string(),
        ids,
        vector[1, 2],
        scenario.ctx()
    );

    let (_, mut executable) = account.create_executable<_, Outcome, _>(b"dummy".to_string(), &clock, version::current(), DummyIntent());
    acc_kiosk_intents::execute_list_nfts<_, Outcome, Nft>(&mut executable, &mut account, &mut acc_kiosk);
    acc_kiosk_intents::execute_list_nfts<_, Outcome, Nft>(&mut executable, &mut account, &mut acc_kiosk);
    account.confirm_execution(executable);

    // delist nfts
    let auth = account.new_auth(version::current(), DummyIntent());
    acc_kiosk::delist<_, Nft>(auth, &mut account, &mut acc_kiosk, b"Degen".to_string(), ids.pop_back());
    let auth = account.new_auth(version::current(), DummyIntent());
    acc_kiosk::delist<_, Nft>(auth, &mut account, &mut acc_kiosk, b"Degen".to_string(), ids.pop_back());

    destroy(acc_kiosk);
    end(scenario, extensions, account, clock, policy);
}

#[test]
fun test_withdraw_profits() {
    let (mut scenario, extensions, mut account, clock, mut policy) = start();
    // open a Kiosk for the caller and for the Account
    let (mut acc_kiosk, mut ids) = init_account_kiosk_with_nfts(&mut account, &mut policy, 2, &mut scenario);
    let (mut caller_kiosk, caller_cap, _) = init_caller_kiosk_with_nfts(&policy, 0, &mut scenario);
    
    // list nfts
    let auth = account.new_auth(version::current(), DummyIntent());
    let params = intents::new_params(
        b"dummy".to_string(), b"".to_string(), vector[0], 1, &clock, scenario.ctx()
    );
    acc_kiosk_intents::request_list_nfts(
        auth, 
        &mut account, 
        params,
        Outcome {},
        b"Degen".to_string(),
        ids,
        vector[100, 200],
        scenario.ctx()
    );

    let (_, mut executable) = account.create_executable<_, Outcome, _>(b"dummy".to_string(), &clock, version::current(), DummyIntent());
    acc_kiosk_intents::execute_list_nfts<_, Outcome, Nft>(&mut executable, &mut account, &mut acc_kiosk);
    acc_kiosk_intents::execute_list_nfts<_, Outcome, Nft>(&mut executable, &mut account, &mut acc_kiosk);
    account.confirm_execution(executable);

    // purchase nfts
    let (nft1, mut request1) = acc_kiosk.purchase<Nft>(ids.pop_back(), coin::mint_for_testing<SUI>(200, scenario.ctx()));
    caller_kiosk.lock(&caller_cap, &policy, nft1);
    kiosk_lock_rule::prove(&mut request1, &caller_kiosk);
    royalty_rule::pay(&mut policy, &mut request1, coin::mint_for_testing<SUI>(2, scenario.ctx()));
    policy.confirm_request(request1);

    let (nft2, mut request2) = acc_kiosk.purchase<Nft>(ids.pop_back(), coin::mint_for_testing<SUI>(100, scenario.ctx()));
    caller_kiosk.lock(&caller_cap, &policy, nft2);
    kiosk_lock_rule::prove(&mut request2, &caller_kiosk);
    royalty_rule::pay(&mut policy, &mut request2, coin::mint_for_testing<SUI>(1, scenario.ctx()));
    policy.confirm_request(request2);

    // withdraw profits
    let auth = account.new_auth(version::current(), DummyIntent());
    acc_kiosk::withdraw_profits(auth, &mut account, &mut acc_kiosk, b"Degen".to_string(), scenario.ctx());

    scenario.next_tx(OWNER);
    let coin = scenario.take_from_address<Coin<SUI>>(account.addr());
    assert!(coin.value() == 300);

    destroy(coin);
    destroy(acc_kiosk);
    destroy(caller_kiosk);
    destroy(caller_cap);
    end(scenario, extensions, account, clock, policy);
}

#[test]
fun test_close_kiosk() {
    let (mut scenario, extensions, mut account, clock, policy) = start();

    assert!(!acc_kiosk::has_lock(&account, b"Degen".to_string()));
    let auth = account.new_auth(version::current(), DummyIntent());
    acc_kiosk::open(auth, &mut account, b"Degen".to_string(), scenario.ctx());
    assert!(acc_kiosk::has_lock(&account, b"Degen".to_string()));

    scenario.next_tx(OWNER);
    let kiosk = scenario.take_shared<Kiosk>();
    assert!(kiosk.owner() == account.addr());

    let auth = account.new_auth(version::current(), DummyIntent());
    acc_kiosk::close(auth, &mut account, b"Degen".to_string(), kiosk, scenario.ctx());

    end(scenario, extensions, account, clock, policy);
}

#[test]
fun test_take_flow() {
    let (mut scenario, extensions, mut account, clock, mut policy) = start();
    let (mut acc_kiosk, mut ids) = init_account_kiosk_with_nfts(&mut account, &mut policy, 1, &mut scenario);
    let (mut caller_kiosk, caller_cap, _) = init_caller_kiosk_with_nfts(&policy, 0, &mut scenario);
    let key = b"dummy".to_string();

    let mut intent = create_dummy_intent(&mut scenario, &account, &clock);
    acc_kiosk::new_take(&mut intent, b"Degen".to_string(), ids.pop_back(), OWNER, DummyIntent());
    account.insert_intent(intent, version::current(), DummyIntent());

    let (_, mut executable) = account.create_executable<_, Outcome, _>(key, &clock, version::current(), DummyIntent());
    let request = acc_kiosk::do_take<_, Outcome, Nft, DummyIntent>(
        &mut executable, 
        &mut account, 
        &mut acc_kiosk,
        &mut caller_kiosk,
        &caller_cap,
        &mut policy,
        version::current(),
        DummyIntent(),
        scenario.ctx()
    );
    policy.confirm_request(request);
    account.confirm_execution(executable);

    destroy(acc_kiosk);
    destroy(caller_kiosk);
    destroy(caller_cap);
    end(scenario, extensions, account, clock, policy);
}

#[test]
fun test_list_flow() {
    let (mut scenario, extensions, mut account, clock, mut policy) = start();
    let (mut acc_kiosk, mut ids) = init_account_kiosk_with_nfts(&mut account, &mut policy, 1, &mut scenario);
    let key = b"dummy".to_string();

    let mut intent = create_dummy_intent(&mut scenario, &account, &clock);
    acc_kiosk::new_list(&mut intent, b"Degen".to_string(), ids.pop_back(), 100, DummyIntent());
    account.insert_intent(intent, version::current(), DummyIntent());

    let (_, mut executable) = account.create_executable<_, Outcome, _>(key, &clock, version::current(), DummyIntent());
    acc_kiosk::do_list<_, Outcome, Nft, DummyIntent>(
        &mut executable, 
        &mut account, 
        &mut acc_kiosk,
        version::current(),
        DummyIntent(),
    );
    account.confirm_execution(executable);

    destroy(acc_kiosk);
    end(scenario, extensions, account, clock, policy);
}

#[test]
fun test_take_expired() {
    let (mut scenario, extensions, mut account, mut clock, mut policy) = start();
    clock.increment_for_testing(1);
    let (acc_kiosk, mut ids) = init_account_kiosk_with_nfts(&mut account, &mut policy, 1, &mut scenario);
    let key = b"dummy".to_string();

    let mut intent = create_dummy_intent(&mut scenario, &account, &clock);
    acc_kiosk::new_take(&mut intent, b"Degen".to_string(), ids.pop_back(), OWNER, DummyIntent());
    account.insert_intent(intent, version::current(), DummyIntent());

    let mut expired = account.delete_expired_intent<_, Outcome>(key, &clock);
    acc_kiosk::delete_take(&mut expired);
    expired.destroy_empty();

    destroy(acc_kiosk);
    end(scenario, extensions, account, clock, policy);
}

#[test]
fun test_list_expired() {
    let (mut scenario, extensions, mut account, mut clock, mut policy) = start();
    clock.increment_for_testing(1);
    let (acc_kiosk, mut ids) = init_account_kiosk_with_nfts(&mut account, &mut policy, 1, &mut scenario);
    let key = b"dummy".to_string();

    let mut intent = create_dummy_intent(&mut scenario, &account, &clock);
    acc_kiosk::new_list(&mut intent, b"Degen".to_string(), ids.pop_back(), 100, DummyIntent());
    account.insert_intent(intent, version::current(), DummyIntent());
    
    let mut expired = account.delete_expired_intent<_, Outcome>(key, &clock);
    acc_kiosk::delete_list(&mut expired);
    expired.destroy_empty();

    destroy(acc_kiosk);
    end(scenario, extensions, account, clock, policy);
}

#[test, expected_failure(abort_code = acc_kiosk::EWrongReceiver)]
fun test_error_do_take_wrong_receiver() {
    let (mut scenario, extensions, mut account, clock, mut policy) = start();
    let (mut acc_kiosk, mut ids) = init_account_kiosk_with_nfts(&mut account, &mut policy, 1, &mut scenario);
    let (mut caller_kiosk, caller_cap, _) = init_caller_kiosk_with_nfts(&policy, 0, &mut scenario);
    let key = b"dummy".to_string();

    let mut intent = create_dummy_intent(&mut scenario, &account, &clock);
    acc_kiosk::new_take(&mut intent, b"Degen".to_string(), ids.pop_back(), ALICE, DummyIntent());
    account.insert_intent(intent, version::current(), DummyIntent());

    let (_, mut executable) = account.create_executable<_, Outcome, _>(key, &clock, version::current(), DummyIntent());
    let request = acc_kiosk::do_take<_, Outcome, Nft, _>(
        &mut executable, 
        &mut account, 
        &mut acc_kiosk,
        &mut caller_kiosk,
        &caller_cap,
        &mut policy,
        version::current(),
        DummyIntent(),
        scenario.ctx()
    );

    destroy(request);
    destroy(executable);
    destroy(acc_kiosk);
    destroy(caller_kiosk);
    destroy(caller_cap);
    end(scenario, extensions, account, clock, policy);
}

// sanity checks as these are tested in AccountProtocol tests

#[test, expected_failure(abort_code = intents::EWrongAccount)]
fun test_error_do_take_from_wrong_account() {
    let (mut scenario, extensions, mut account, clock, mut policy) = start();
    let deps = deps::new_latest_extensions(&extensions, vector[b"AccountProtocol".to_string(), b"AccountActions".to_string()]);
    let mut account2 = account::new(Config {}, deps, version::current(), DummyIntent(), scenario.ctx());
    
    let (mut acc_kiosk, mut ids) = init_account_kiosk_with_nfts(&mut account, &mut policy, 1, &mut scenario);
    let (mut caller_kiosk, caller_cap, _) = init_caller_kiosk_with_nfts(&policy, 0, &mut scenario);
    let key = b"dummy".to_string();

    let mut intent = create_dummy_intent(&mut scenario, &account2, &clock);
    acc_kiosk::new_take(&mut intent, b"Degen".to_string(), ids.pop_back(), OWNER, DummyIntent());
    account2.insert_intent(intent, version::current(), DummyIntent());

    let (_, mut executable) = account2.create_executable<_, Outcome, _>(key, &clock, version::current(), DummyIntent());
    let request = acc_kiosk::do_take<_, Outcome, Nft, _>(
        &mut executable, 
        &mut account, 
        &mut acc_kiosk,
        &mut caller_kiosk,
        &caller_cap,
        &mut policy,
        version::current(),
        DummyIntent(),
        scenario.ctx()
    );

    destroy(account2);
    destroy(request);
    destroy(executable);
    destroy(acc_kiosk);
    destroy(caller_kiosk);
    destroy(caller_cap);
    end(scenario, extensions, account, clock, policy);
}

#[test, expected_failure(abort_code = intents::EWrongWitness)]
fun test_error_do_take_from_wrong_constructor_witness() {
    let (mut scenario, extensions, mut account, clock, mut policy) = start();
    let (mut acc_kiosk, mut ids) = init_account_kiosk_with_nfts(&mut account, &mut policy, 1, &mut scenario);
    let (mut caller_kiosk, caller_cap, _) = init_caller_kiosk_with_nfts(&policy, 0, &mut scenario);
    let key = b"dummy".to_string();

    let mut intent = create_dummy_intent(&mut scenario, &account, &clock);
    acc_kiosk::new_take(&mut intent, b"Degen".to_string(), ids.pop_back(), OWNER, DummyIntent());
    account.insert_intent(intent, version::current(), DummyIntent());

    let (_, mut executable) = account.create_executable<_, Outcome, _>(key, &clock, version::current(), DummyIntent());
    let request = acc_kiosk::do_take<_, Outcome, Nft, _>(
        &mut executable, 
        &mut account, 
        &mut acc_kiosk,
        &mut caller_kiosk,
        &caller_cap,
        &mut policy,
        version::current(),
        WrongWitness(),
        scenario.ctx()
    );

    destroy(request);
    destroy(executable);
    destroy(acc_kiosk);
    destroy(caller_kiosk);
    destroy(caller_cap);
    end(scenario, extensions, account, clock, policy);
}

#[test, expected_failure(abort_code = intents::EWrongAccount)]
fun test_error_do_list_from_wrong_account() {
    let (mut scenario, extensions, mut account, clock, mut policy) = start();
    let deps = deps::new_latest_extensions(&extensions, vector[b"AccountProtocol".to_string(), b"AccountActions".to_string()]);
    let mut account2 = account::new(Config {}, deps, version::current(), DummyIntent(), scenario.ctx());
    
    let (mut acc_kiosk, mut ids) = init_account_kiosk_with_nfts(&mut account, &mut policy, 1, &mut scenario);
    let key = b"dummy".to_string();

    let mut intent = create_dummy_intent(&mut scenario, &account2, &clock);
    acc_kiosk::new_take(&mut intent, b"Degen".to_string(), ids.pop_back(), OWNER, DummyIntent());
    account2.insert_intent(intent, version::current(), DummyIntent());

    let (_, mut executable) = account2.create_executable<_, Outcome, _>(key, &clock, version::current(), DummyIntent());
    acc_kiosk::do_list<_, Outcome, Nft, _>(
        &mut executable, 
        &mut account, 
        &mut acc_kiosk,
        version::current(),
        DummyIntent(),
    );

    destroy(account2);
    destroy(executable);
    destroy(acc_kiosk);
    end(scenario, extensions, account, clock, policy);
}

#[test, expected_failure(abort_code = intents::EWrongWitness)]
fun test_error_do_list_from_wrong_constructor_witness() {
    let (mut scenario, extensions, mut account, clock, mut policy) = start();
    let (mut acc_kiosk, mut ids) = init_account_kiosk_with_nfts(&mut account, &mut policy, 1, &mut scenario);
    let key = b"dummy".to_string();

    let mut intent = create_dummy_intent(&mut scenario, &account, &clock);
    acc_kiosk::new_take(&mut intent, b"Degen".to_string(), ids.pop_back(), OWNER, DummyIntent());
    account.insert_intent(intent, version::current(), DummyIntent());

    let (_, mut executable) = account.create_executable<_, Outcome, _>(key, &clock, version::current(), DummyIntent());
    acc_kiosk::do_list<_, Outcome, Nft, _>(
        &mut executable, 
        &mut account, 
        &mut acc_kiosk,
        version::current(),
        WrongWitness(),
    );

    destroy(executable);
    destroy(acc_kiosk);
    end(scenario, extensions, account, clock, policy);
}