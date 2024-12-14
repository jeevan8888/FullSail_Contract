module fullsail::token_whitelist {
    use std::string::String;
    use std::vector;
    use aptos_framework::smart_table::{Self, SmartTable};
    use aptos_framework::smart_vector::{Self, SmartVector};
    use aptos_framework::object::Object;
    use aptos_framework::fungible_asset::Metadata;
    use aptos_framework::type_info;

    // --- freinds modules ---
    friend fullsail::vote_manager;

    // --- errors ---
    const E_MAX_WHITELIST_EXCEEDED: u64 = 1;

    // --- structs ---
    struct RewardTokenWhitelistPerPool has key {
        whitelist: SmartTable<address, SmartVector<String>>,
    }

    struct TokenWhitelist has key {
        tokens: SmartVector<String>,
    }

    // init
    public entry fun initialize() {
        if (is_initialized()) {
            return
        };
        let signer = fullsail::package_manager::get_signer();
        let whitelist = TokenWhitelist{tokens: smart_vector::new()};
        move_to<TokenWhitelist>(&signer, whitelist);
    }

    public fun is_initialized() : bool {
        exists<TokenWhitelist>(@fullsail)
    }

    fun add_to_whitelist(new_tokens: vector<String>) acquires TokenWhitelist {
        let whitelist = &mut borrow_global_mut<TokenWhitelist>(@fullsail).tokens;
        vector::reverse(&mut new_tokens);

        let new_tokens_length = vector::length<String>(&new_tokens);
        while (new_tokens_length > 0) {
            let token = vector::pop_back(&mut new_tokens);
            if (!smart_vector::contains(whitelist, &token)) {
                smart_vector::push_back(whitelist, token);
            };
            new_tokens_length = new_tokens_length - 1;
        };

        vector::destroy_empty(new_tokens);
    }

    public fun are_whitelisted(tokens: vector<String>) : bool acquires TokenWhitelist {
        let whitelist = &borrow_global<TokenWhitelist>(@fullsail).tokens;

        let all_whitelisted = true;
        let i = 0;
        while (i < vector::length<String>(&tokens)) {
            let is_token_whitelisted = smart_vector::contains(whitelist, vector::borrow(&tokens, i));
            all_whitelisted = is_token_whitelisted;
            if (!is_token_whitelisted) {
                break
            };
            i = i + 1;
        };
        all_whitelisted
    }

    public fun is_reward_token_whitelisted_on_pool(token: String, pool_address: address) : bool acquires RewardTokenWhitelistPerPool {
        if (!exists<RewardTokenWhitelistPerPool>(@fullsail)) {
            let signer = fullsail::package_manager::get_signer();
            let pool_whitelist = RewardTokenWhitelistPerPool{whitelist: smart_table::new<address, smart_vector::SmartVector<String>>()};
            move_to<RewardTokenWhitelistPerPool>(&signer, pool_whitelist);
        };
        let pool_whitelist = &borrow_global_mut<RewardTokenWhitelistPerPool>(@fullsail).whitelist;
        smart_vector::contains(smart_table::borrow(pool_whitelist, pool_address), &token)
    }

    public(friend) fun set_whitelist_reward_token<T>(pool_address: address, is_whitelisted: bool) acquires RewardTokenWhitelistPerPool {
        let tokens = vector::empty<String>();
        vector::push_back(&mut tokens, type_info::type_name<T>());
        set_whitelist_reward_tokens(tokens, pool_address, is_whitelisted);
    }

    public(friend) fun set_whitelist_reward_tokens(tokens: vector<String>, pool_address: address, is_whitelisted: bool) acquires RewardTokenWhitelistPerPool {
        let whitelist_len = whitelist_length(pool_address);
        assert!(whitelist_len <= 15, E_MAX_WHITELIST_EXCEEDED);

        if (!exists<RewardTokenWhitelistPerPool>(@fullsail)) {
            let signer = fullsail::package_manager::get_signer();
            let pool_whitelist = RewardTokenWhitelistPerPool{whitelist: smart_table::new<address, smart_vector::SmartVector<String>>()};
            move_to<RewardTokenWhitelistPerPool>(&signer, pool_whitelist);
        };

        let whitelist_table = &mut borrow_global_mut<RewardTokenWhitelistPerPool>(@fullsail).whitelist;
        if (!smart_table::contains<address, SmartVector<String>>(whitelist_table, pool_address)) {
            smart_table::add(whitelist_table, pool_address, smart_vector::new<String>());
        };

        let pool_whitelist = smart_table::borrow_mut<address, SmartVector<String>>(whitelist_table, pool_address);

        let i = 0;
        while (i < vector::length<String>(&tokens)) {
            let token = vector::borrow<String>(&tokens, i);
            if (is_whitelisted == true) {
                if (!smart_vector::contains<String>(pool_whitelist, token)) {
                    assert!(smart_vector::length<String>(pool_whitelist) < 15, E_MAX_WHITELIST_EXCEEDED);
                    smart_vector::push_back<String>(pool_whitelist, *token);
                };
            } else {
                let (found, index) = smart_vector::index_of<String>(pool_whitelist, token);
                if (found) {
                    smart_vector::remove<String>(pool_whitelist, index);
                };
            };
            i = i + 1;
        };
    }

    public(friend) fun whitelist_coin<T>() acquires TokenWhitelist {
        let coins = vector::empty<String>();
        vector::push_back<String>(&mut coins, type_info::type_name<T>());
        add_to_whitelist(coins);
    }

   public fun whitelist_length(pool_address: address) : u64 acquires RewardTokenWhitelistPerPool {
        if (!exists<RewardTokenWhitelistPerPool>(@fullsail)) {
            let signer = fullsail::package_manager::get_signer();
            let pool_whitelist = RewardTokenWhitelistPerPool{whitelist: smart_table::new<address, SmartVector<String>>()};
            move_to<RewardTokenWhitelistPerPool>(&signer, pool_whitelist);
        };
        let whitelist_table = &borrow_global_mut<RewardTokenWhitelistPerPool>(@fullsail).whitelist;
        if (smart_table::contains<address, smart_vector::SmartVector<String>>(whitelist_table, pool_address) == false) {
            return 0
        };
        smart_vector::length<String>(smart_table::borrow<address, smart_vector::SmartVector<String>>(whitelist_table, pool_address))
    }

    public(friend) fun whitelist_native_fungible_assets(assets: vector<Object<Metadata>>) acquires TokenWhitelist {
        let asset_names = vector::empty<String>();
        vector::reverse(&mut assets);
        let assets_len = vector::length(&assets);
        while (assets_len > 0) {
            vector::push_back(&mut asset_names, fullsail::coin_wrapper::format_fungible_asset(vector::pop_back(&mut assets)));
            assets_len = assets_len - 1;
        };
        vector::destroy_empty(assets);
        add_to_whitelist(asset_names);
    }

    public fun whitelisted_reward_token_per_pool(pool_address: address) : vector<String> acquires RewardTokenWhitelistPerPool {
        if (!exists<RewardTokenWhitelistPerPool>(@fullsail)) {
            let signer = fullsail::package_manager::get_signer();
            let pool_whitelist = RewardTokenWhitelistPerPool{whitelist: smart_table::new<address, SmartVector<String>>()};
            move_to<RewardTokenWhitelistPerPool>(&signer, pool_whitelist);
        };
        smart_vector::to_vector(smart_table::borrow(&borrow_global_mut<RewardTokenWhitelistPerPool>(@fullsail).whitelist, pool_address))
    }

    public fun whitelisted_tokens() : vector<String> acquires TokenWhitelist {
        let whitelist = &borrow_global<TokenWhitelist>(@fullsail).tokens;
        let result = vector::empty<String>();
        let i = 0;
        while (i < smart_vector::length(whitelist)) {
            vector::push_back(&mut result, *smart_vector::borrow(whitelist, i));
            i = i + 1;
        };
        result
    }

    // --- tests helper ---
    #[test_only]
    public fun initialize_for_test() {
        initialize();
    }
    #[test_only]
    public fun is_initialized_test(addr: address): bool {
        exists<TokenWhitelist>(addr)
    }
    #[test_only]
    public fun add_to_whitelist_test(new_tokens: vector<String>) acquires TokenWhitelist {
        add_to_whitelist(new_tokens)
    }

    #[test_only]
    public fun set_whitelist_reward_tokens_test(tokens: vector<String>, pool_address: address, is_whitelisted: bool) acquires RewardTokenWhitelistPerPool {
        set_whitelist_reward_tokens(tokens, pool_address, is_whitelisted)
    }

    #[test_only]
    public fun whitelist_coin_test<T>() acquires TokenWhitelist {
        whitelist_coin<T>()
    }
    
    #[test_only]
    public fun whitelist_native_fungible_assets_test(assets: vector<Object<Metadata>>) acquires TokenWhitelist {
        whitelist_native_fungible_assets(assets)
    }

    #[test_only]
    struct TestCoin {}

}