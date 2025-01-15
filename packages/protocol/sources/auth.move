/// 

module account_protocol::auth;

// === Imports ===

use std::{
    string::String,
    type_name::{Self, TypeName},
};
use sui::{
    address,
    hex,
};
use account_extensions::extensions::Extensions;

// === Errors ===

#[error]
const EWrongAccount: vector<u8> = b"Account didn't create the auth";
#[error]
const EWrongRole: vector<u8> = b"Role doesn't match";

// === Structs ===

/// Protected type ensuring provenance
public struct Auth {
    // address of the account that created the auth
    account_addr: address,
    // type_name (+ opt name) of the witness that instantiated the auth
    role: String,
}

// === Public Functions ===

// === View Functions ===

public fun account_addr(auth: &Auth): address {
    auth.account_addr
}

public fun role(auth: &Auth): String {
    auth.role
}

// === Core extensions functions ===

public fun new(
    extensions: &Extensions,
    account_addr: address,
    role: String, 
    version: TypeName,
): Auth {
    let addr = address::from_bytes(hex::decode(version.get_address().into_bytes()));
    extensions.assert_is_core_extension(addr);

    Auth { account_addr, role }
}

public fun verify(
    auth: Auth,
    addr: address,
) {
    let Auth { account_addr, .. } = auth;

    assert!(addr == account_addr, EWrongAccount);
}

public fun verify_with_role<Role>(
    auth: Auth,
    addr: address,
    name: String,
) {
    let mut full_role = type_name::get<Role>().get_address().to_string();
    full_role.append_utf8(b"::");
    full_role.append(type_name::get<Role>().get_module().to_string());
    
    if (!name.is_empty()) {
        full_role.append_utf8(b"::");
        full_role.append(name);
    };
    
    let Auth { account_addr, role } = auth;

    assert!(addr == account_addr, EWrongAccount);
    assert!(role == full_role, EWrongRole);
}