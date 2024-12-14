module fullsail::package_manager {
    use std::string::String;
    use aptos_framework::account::{Self, SignerCapability};
    use aptos_framework::resource_account;
    use aptos_std::smart_table::{Self, SmartTable};

    // --- friends modules ---
    friend fullsail::cellana_token;
    friend fullsail::voting_escrow;
    friend fullsail::vote_manager;
    friend fullsail::token_whitelist;
    friend fullsail::coin_wrapper;
    friend fullsail::rewards_pool;
    friend fullsail::liquidity_pool;
    friend fullsail::gauge;
    friend fullsail::rewards_pool_continuous;
    friend fullsail::minter;

    // --- addresses ---
    const RESOURCE_ACCOUNT: address = @0xcafe;

    // --- errors ---
    const EADDRESS_NOT_FOUND: u64 = 1;
    const EADDRESS_ALREADY_EXISTS: u64 = 2;

    // --- structs ---
    struct PermissionConfig has key {
        signer_cap: SignerCapability,
        addresses: SmartTable<String, address>,
    }

    // init
    fun init_module(resource_signer: &signer) {
        let permission_config = PermissionConfig{
            signer_cap: resource_account::retrieve_resource_account_cap(
                resource_signer, 
                RESOURCE_ACCOUNT
            ),
            addresses: smart_table::new<String, address>(),
        };
        move_to<PermissionConfig>(resource_signer, permission_config);
    }

    public(friend) fun add_address(identifier: String, addr: address) acquires PermissionConfig {
        let config = borrow_global_mut<PermissionConfig>(@fullsail);
        smart_table::add(&mut config.addresses, identifier, addr);
    }

    public fun address_exists(identifier: String) : bool acquires PermissionConfig {
        let config = borrow_global_mut<PermissionConfig>(@fullsail);
        smart_table::contains(&config.addresses, identifier)
    }

    public fun get_address(identifier: String) : address acquires PermissionConfig {
        let config = borrow_global_mut<PermissionConfig>(@fullsail);
        *smart_table::borrow(&config.addresses, identifier)
    }

    public(friend) fun get_signer() : signer acquires PermissionConfig {
        let config = borrow_global_mut<PermissionConfig>(@fullsail);
        account::create_signer_with_capability(&config.signer_cap)
    }

    #[test_only]
    public fun init_module_test(resource_signer: &signer) {
        init_module(resource_signer);
    }

    #[test_only]
    public fun is_initialized(account: address): bool {
        exists<PermissionConfig>(account)
    }

    #[test_only]
    public fun add_address_test(identifier: String, addr: address) acquires PermissionConfig {
        add_address(identifier, addr)
    }

    #[test_only]
    public fun get_signer_test() : signer acquires PermissionConfig {
        get_signer()
    }
}
