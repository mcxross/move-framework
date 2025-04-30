#[test_only]
module account_actions::kiosk_intents_tests;

// === Imports ===

use sui::{
    test_utils::destroy,
    test_scenario::{Self as ts, Scenario},
    kiosk::{Self, Kiosk, KioskOwnerCap},
    package,
    clock::{Self, Clock},
    transfer_policy::{Self, TransferPolicy},
};
use kiosk::{kiosk_lock_rule, royalty_rule};
use account_extensions::extensions::{Self, Extensions, AdminCap};
use account_protocol::{
    account::{Self as account, Account},
    deps,
    intents,
};
use account_actions::{
    kiosk as acc_kiosk,
    kiosk_intents as acc_kiosk_intents,
    version,
};

// === Constants ===

const OWNER: address = @0xCAFE;

// === Structs ===

public struct KIOSK_TESTS has drop {}

public struct Nft has key, store {
    id: UID
}

public struct Witness() has drop;

// Define Config and Outcome structs

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
    let account = account::new(Config {}, deps, version::current(), Witness(), scenario.ctx());
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
    let auth = account.new_auth(version::current(), Witness());
    acc_kiosk::open(auth, account, b"Degen".to_string(), scenario.ctx());
    scenario.next_tx(OWNER);
    let mut acc_kiosk = scenario.take_shared<Kiosk>();
    
    let (mut kiosk, kiosk_cap, ids) = init_caller_kiosk_with_nfts(policy, amount, scenario);
    let mut nft_ids = ids;

    amount.do!(|_| {
        let auth = account.new_auth(version::current(), Witness());
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

// === Tests ===

#[test]
fun test_request_execute_take() {
    let (mut scenario, extensions, mut account, clock, mut policy) = start();
    // open a Kiosk for the caller and for the Account
    let (mut acc_kiosk, mut ids) = init_account_kiosk_with_nfts(&mut account, &mut policy, 2, &mut scenario);
    let (mut caller_kiosk, caller_cap, _) = init_caller_kiosk_with_nfts(&policy, 0, &mut scenario);

    let auth = account.new_auth(version::current(), Witness());
    let outcome = Outcome {};
    let params = intents::new_params(
        b"dummy".to_string(), b"".to_string(), vector[0], 1, &clock, scenario.ctx()
    );
    acc_kiosk_intents::request_take_nfts(
        auth, 
        &mut account, 
        params,
        outcome,
        b"Degen".to_string(),
        ids,
        OWNER,
        scenario.ctx()
    );

    let (_, mut executable) = account.create_executable<_, Outcome, _>(b"dummy".to_string(), &clock, version::current(), Witness());
    let request = acc_kiosk_intents::execute_take_nfts<Config, Outcome, Nft>(
        &mut executable, 
        &mut account, 
        &mut acc_kiosk,
        &mut caller_kiosk,
        &caller_cap,
        &mut policy,
        scenario.ctx()
    );
    policy.confirm_request(request);
    let request = acc_kiosk_intents::execute_take_nfts<Config, Outcome, Nft>(
        &mut executable, 
        &mut account, 
        &mut acc_kiosk,
        &mut caller_kiosk,
        &caller_cap,
        &mut policy,
        scenario.ctx()
    );
    policy.confirm_request(request); 
    account.confirm_execution(executable);

    let mut expired = account.destroy_empty_intent<_, Outcome>(b"dummy".to_string());
    acc_kiosk::delete_take(&mut expired);
    acc_kiosk::delete_take(&mut expired);
    expired.destroy_empty();

    assert!(caller_kiosk.has_item(ids.pop_back()));
    assert!(caller_kiosk.has_item(ids.pop_back()));

    destroy(acc_kiosk);
    destroy(caller_kiosk);
    destroy(caller_cap);
    end(scenario, extensions, account, clock, policy);
}

#[test]
fun test_request_execute_list() {
    let (mut scenario, extensions, mut account, clock, mut policy) = start();
    // open a Kiosk for the caller and for the Account
    let (mut acc_kiosk, mut ids) = init_account_kiosk_with_nfts(&mut account, &mut policy, 2, &mut scenario);
    
    // list nfts
    let auth = account.new_auth(version::current(), Witness());
    let outcome = Outcome {};
    let params = intents::new_params(
        b"dummy".to_string(), b"".to_string(), vector[0], 1, &clock, scenario.ctx()
    );
    acc_kiosk_intents::request_list_nfts(
        auth, 
        &mut account, 
        params,
        outcome,
        b"Degen".to_string(),
        ids,
        vector[100, 200],
        scenario.ctx() 
    );

    let (_, mut executable) = account.create_executable<_, Outcome, _>(b"dummy".to_string(), &clock, version::current(), Witness());
    acc_kiosk_intents::execute_list_nfts<Config, Outcome, Nft>(&mut executable, &mut account, &mut acc_kiosk);
    acc_kiosk_intents::execute_list_nfts<Config, Outcome, Nft>(&mut executable, &mut account, &mut acc_kiosk);
    account.confirm_execution(executable);

    let mut expired = account.destroy_empty_intent<_, Outcome>(b"dummy".to_string());
    acc_kiosk::delete_list(&mut expired);
    acc_kiosk::delete_list(&mut expired);
    expired.destroy_empty();

    assert!(acc_kiosk.is_listed(ids.pop_back()));
    assert!(acc_kiosk.is_listed(ids.pop_back()));

    destroy(acc_kiosk);
    end(scenario, extensions, account, clock, policy);
}

#[test, expected_failure(abort_code = acc_kiosk_intents::ENoLock)]
fun test_error_request_take_from_kiosk_doesnt_exist() {
    let (mut scenario, extensions, mut account, clock, policy) = start();
    
    let auth = account.new_auth(version::current(), Witness());
    let outcome = Outcome {};
    let params = intents::new_params(
        b"dummy".to_string(), b"".to_string(), vector[0], 1, &clock, scenario.ctx()
    );
    acc_kiosk_intents::request_take_nfts(
        auth, 
        &mut account, 
        params,
        outcome,
        b"dummy".to_string(),
        vector[@0x0.to_id()],
        OWNER,
        scenario.ctx()
    );

    end(scenario, extensions, account, clock, policy);
}

#[test, expected_failure(abort_code = acc_kiosk_intents::ENoLock)]
fun test_error_request_list_from_kiosk_doesnt_exist() {
    let (mut scenario, extensions, mut account, clock, policy) = start();
    
    let auth = account.new_auth(version::current(), Witness());
    let outcome = Outcome {};
    let params = intents::new_params(
        b"dummy".to_string(), b"".to_string(), vector[0], 1, &clock, scenario.ctx()
    );
    acc_kiosk_intents::request_list_nfts(
        auth, 
        &mut account, 
        params,
        outcome,
        b"NotDegen".to_string(),
        vector[@0x0.to_id()],
        vector[100],
        scenario.ctx()
    ); 

    end(scenario, extensions, account, clock, policy);
}

#[test, expected_failure(abort_code = acc_kiosk_intents::ENftsPricesNotSameLength)]
fun test_error_request_list_nfts_prices_not_same_length() {
    let (mut scenario, extensions, mut account, clock, mut policy) = start();
    let (acc_kiosk, _) = init_account_kiosk_with_nfts(&mut account, &mut policy, 1, &mut scenario);

    let auth = account.new_auth(version::current(), Witness());
    let outcome = Outcome {};
    let params = intents::new_params(
        b"dummy".to_string(), b"".to_string(), vector[0], 1, &clock, scenario.ctx()
    );
    acc_kiosk_intents::request_list_nfts(
        auth, 
        &mut account, 
        params,
        outcome,
        b"Degen".to_string(),
        vector[@0x0.to_id()],
        vector[100, 200],
        scenario.ctx()
    );

    destroy(acc_kiosk);
    end(scenario, extensions, account, clock, policy);
}
