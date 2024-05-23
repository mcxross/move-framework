#[test_only]
module kraken::account_tests {
    use std::string;

    use sui::test_utils::assert_eq;
    use sui::test_scenario::take_from_address;

    use kraken::test_utils::start_world;
    use kraken::account::{Self, Account, Invite};

    const OWNER: address = @0xBABE;
    const ALICE: address = @0xA11CE;

    #[test]
    fun test_account_end_to_end() {
        let mut world = start_world();

        account::new(string::utf8(b"Sam"), string::utf8(b"Sam.png"), world.scenario().ctx());

        world.scenario().next_tx(OWNER);

        let mut user_account = take_from_address<Account>(world.scenario(), OWNER);

        assert_eq(user_account.username(), string::utf8(b"Sam"));
        assert_eq(user_account.profile_picture(), string::utf8(b"Sam.png"));
        assert_eq(user_account.multisigs(), vector[]);

        let id1 = object::new(world.scenario().ctx());
        let id2 = object::new(world.scenario().ctx());

        user_account.join_multisig(id1.uid_to_inner());
        user_account.join_multisig(id2.uid_to_inner());

        assert_eq(user_account.multisigs(), vector[id1.uid_to_inner(), id2.uid_to_inner()]);

        user_account.leave_multisig(id2.uid_to_inner());

        assert_eq(user_account.multisigs(), vector[id1.uid_to_inner()]);

        user_account.destroy();
        id1.delete();
        id2.delete();

        world.end();
    }

    #[test]
    fun test_accept_invite() {
        let mut world = start_world();

        // add Alice to the multisig
        world.propose_modify(
            string::utf8(b"modify"), 
            0, 
            0, 
            string::utf8(b""), 
            option::none(),
            option::none(),
            vector[ALICE],
            vector[]
        );
        world.approve_proposal(string::utf8(b"modify"));
        world.execute_modify(string::utf8(b"modify"));

        world.scenario().next_tx(ALICE);

        account::new(string::utf8(b"Sam"), string::utf8(b"Sam.png"), world.scenario().ctx());

        world.scenario().next_tx(ALICE);

        let mut user_account = take_from_address<Account>(world.scenario(), ALICE);

        world.send_invite(ALICE);

        world.scenario().next_tx(ALICE);

        let invite = take_from_address<Invite>(world.scenario(), ALICE);
        
        account::accept_invite(&mut user_account, invite);
        
        let multisig_id = object::id(world.multisig());

        assert_eq(user_account.multisigs(), vector[multisig_id]);

        user_account.destroy();

        world.end();
    }

    #[test]
    fun test_refuse_invite() {
        let mut world = start_world();

        // add Alice to the multisig
        world.propose_modify(
            string::utf8(b"modify"), 
            0, 
            0, 
            string::utf8(b""), 
            option::none(),
            option::none(),
            vector[ALICE],
            vector[]
        );
        world.approve_proposal(string::utf8(b"modify"));
        world.execute_modify(string::utf8(b"modify"));

        world.scenario().next_tx(ALICE);

        account::new(string::utf8(b"Sam"), string::utf8(b"Sam.png"), world.scenario().ctx());

        world.scenario().next_tx(ALICE);

        let user_account = take_from_address<Account>(world.scenario(), ALICE);

        world.send_invite(ALICE);

        world.scenario().next_tx(ALICE);

        let invite = take_from_address<Invite>(world.scenario(), ALICE);
        
        account::refuse_invite(invite);

        assert_eq(user_account.multisigs(), vector[]);

        user_account.destroy();

        world.end();        
    }

    #[test]
    #[expected_failure]
    fun test_send_invite_error_not_member() {
        let mut world = start_world();

        world.scenario().next_tx(ALICE);

        world.send_invite(@0x0);

        world.end();        
    }    
}