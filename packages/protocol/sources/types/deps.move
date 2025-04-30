/// Dependencies are the packages that an Account object can call.
/// They are stored in a vector and can be modified through an intent.
/// AccountProtocol is the only mandatory dependency, found at index 0.
/// 
/// For improved security, we provide a whitelist of allowed packages in Extensions.
/// If unverified_allowed is false, then only these packages can be added.

module account_protocol::deps;

// === Imports ===

use std::string::String;
use account_extensions::extensions::Extensions;
use account_protocol::version_witness::VersionWitness;

// === Errors ===

const EDepNotFound: u64 = 0;
const EDepAlreadyExists: u64 = 1;
const ENotDep: u64 = 2;
const ENotExtension: u64 = 3;
const EAccountProtocolMissing: u64 = 4;
const EDepsNotSameLength: u64 = 5;
const EAccountConfigMissing: u64 = 6;

// === Structs ===

/// Parent struct protecting the deps
public struct Deps has copy, drop, store {
    inner: vector<Dep>,
    // can community extensions be added
    unverified_allowed: bool,
}

/// Child struct storing the name, package and version of a dependency
public struct Dep has copy, drop, store {
    // name of the package
    name: String,
    // id of the package
    addr: address,
    // version of the package
    version: u64,
}

// === Public functions ===

/// Creates a new Deps struct, AccountProtocol must be the first dependency.
public fun new(
    extensions: &Extensions,
    unverified_allowed: bool,
    names: vector<String>,
    addresses: vector<address>,
    mut versions: vector<u64>,
): Deps {
    assert!(names.length() == addresses.length() && addresses.length() == versions.length(), EDepsNotSameLength);
    assert!(
        names[0] == b"AccountProtocol".to_string() &&
        extensions.is_extension(names[0], addresses[0], versions[0]), 
        EAccountProtocolMissing
    );
    // second dependency must be AccountConfig (we don't know the name)
    assert!(names[1] != b"AccountActions".to_string(), EAccountConfigMissing);

    let mut inner = vector<Dep>[];

    names.zip_do!(addresses, |name, addr| {
        let version = versions.remove(0);
        
        assert!(!inner.any!(|dep| dep.name == name), EDepAlreadyExists);
        assert!(!inner.any!(|dep| dep.addr == addr), EDepAlreadyExists);
        if (!unverified_allowed) 
            assert!(extensions.is_extension(name, addr, version), ENotExtension);

        inner.push_back(Dep { name, addr, version });
    });

    Deps { inner, unverified_allowed }
}

/// Creates a new Deps struct from latest packages for names.
/// Unverified packages are not allowed after this operation.
public fun new_latest_extensions(
    extensions: &Extensions,
    names: vector<String>,
): Deps {
    assert!(names[0] == b"AccountProtocol".to_string(), EAccountProtocolMissing);

    let mut inner = vector<Dep>[];

    names.do!(|name| {
        assert!(!inner.any!(|dep| dep.name == name), EDepAlreadyExists);
        let (addr, version) = extensions.get_latest_for_name(name);
        
        inner.push_back(Dep { name, addr, version });
    });

    Deps { inner, unverified_allowed: false }
}

public fun new_inner(
    extensions: &Extensions,
    deps: &Deps,
    names: vector<String>,
    addresses: vector<address>,
    mut versions: vector<u64>,
): vector<Dep> {
    assert!(names.length() == addresses.length() && addresses.length() == versions.length(), EDepsNotSameLength);
    // AccountProtocol is mandatory and cannot be removed
    assert!(
        names[0] == b"AccountProtocol".to_string() &&
        extensions.is_extension(names[0], addresses[0], versions[0]), 
        EAccountProtocolMissing
    );
    // AccountConfig is mandatory and cannot be removed
    assert!(
        names[1] == deps.get_by_idx(1).name &&
        (deps.unverified_allowed || extensions.is_extension(names[1], addresses[1], versions[1])),
        EAccountConfigMissing
    );

    let mut inner = vector<Dep>[];
    names.zip_do!(addresses, |name, addr| {
        let version = versions.remove(0);
        
        assert!(!inner.any!(|dep| dep.name == name), EDepAlreadyExists);
        assert!(!inner.any!(|dep| dep.addr == addr), EDepAlreadyExists);
        if (!deps.unverified_allowed) 
            assert!(extensions.is_extension(name, addr, version), ENotExtension);

        inner.push_back(Dep { name, addr, version });
    });

    inner
}

/// Safe because deps_mut is only accessible in this package.
public fun inner_mut(deps: &mut Deps): &mut vector<Dep> {
    &mut deps.inner
}

// === View functions ===

/// Checks if a package is a dependency.
public fun check(deps: &Deps, version_witness: VersionWitness) {
    assert!(deps.contains_addr(version_witness.package_addr()), ENotDep);
}

/// Returns true if unverified packages are allowed.
public fun unverified_allowed(deps: &Deps): bool {
    deps.unverified_allowed
}

/// Returns a dependency by index.
public fun get_by_idx(deps: &Deps, idx: u64): &Dep {
    &deps.inner[idx]
}

/// Returns a dependency by name.
public fun get_by_name(deps: &Deps, name: String): &Dep {
    let opt = deps.inner.find_index!(|dep| dep.name == name);
    assert!(opt.is_some(), EDepNotFound);
    let idx = opt.destroy_some();

    &deps.inner[idx]
}

/// Returns a dependency by address.
public fun get_by_addr(deps: &Deps, addr: address): &Dep {
    let opt = deps.inner.find_index!(|dep| dep.addr == addr);
    assert!(opt.is_some(), EDepNotFound);
    let idx = opt.destroy_some();
    
    &deps.inner[idx]
}

/// Returns the number of dependencies.
public fun length(deps: &Deps): u64 {
    deps.inner.length()
}

/// Returns the name of a dependency.
public fun name(dep: &Dep): String {
    dep.name
}

/// Returns the address of a dependency.
public fun addr(dep: &Dep): address {
    dep.addr
}

/// Returns the version of a dependency.
public fun version(dep: &Dep): u64 {
    dep.version
}

/// Returns true if a dependency exists by name.
public fun contains_name(deps: &Deps, name: String): bool {
    deps.inner.any!(|dep| dep.name == name)
}

/// Returns true if a dependency exists by address.
public fun contains_addr(deps: &Deps, addr: address): bool {
    deps.inner.any!(|dep| dep.addr == addr)
}

// === Package functions ===

/// Toggles the unverified_allowed flag.
public(package) fun toggle_unverified_allowed(deps: &mut Deps) {
    deps.unverified_allowed = !deps.unverified_allowed;
}
