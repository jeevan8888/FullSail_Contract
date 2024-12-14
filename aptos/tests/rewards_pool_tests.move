#[test_only]
module fullsail::rewards_pool_tests {
    use std::vector;
    use aptos_framework::signer;
    use aptos_framework::account;
    use aptos_framework::coin;
    use aptos_framework::string;
    use aptos_framework::resource_account;
    use aptos_framework::primary_fungible_store;
    use aptos_framework::fungible_asset::{FungibleAsset, Metadata};
    use aptos_framework::object::{Object};
    use fullsail::package_manager;
    use fullsail::rewards_pool;
    use fullsail::coin_wrapper;
    use fullsail::my_token::{MyToken};
    use aptos_framework::timestamp;
    use aptos_framework::genesis;   

    struct TokenManager has key {
        burn_cap: coin::BurnCapability<MyToken>,
        freeze_cap: coin::FreezeCapability<MyToken>,
        mint_cap: coin::MintCapability<MyToken>,
    }

    #[test_only]
    fun setup(source: &signer, resource_acc: &signer) {
        account::create_account_for_test(signer::address_of(source));
        resource_account::create_resource_account(source, vector::empty(), vector::empty());
        package_manager::init_module_test(resource_acc);
        coin_wrapper::initialize();
        genesis::setup();
    }

    #[test(source = @0xcafe, resource_acc = @0xc3bb8488ab1a5815a9d543d7e41b0e0df46a7396f89b22821f07a4362f75ddc5)]
    public fun create_rewards_pool_test(source: &signer, resource_acc: &signer) {
        setup(source, resource_acc);
        let (burn_cap, freeze_cap, mint_cap) = coin::initialize<MyToken>(
            resource_acc,
            string::utf8(b"MyToken"),
            string::utf8(b"MTK"),
            8,
            true
        );

        move_to<TokenManager>(resource_acc, TokenManager {
            burn_cap,
            freeze_cap,
            mint_cap,
        });

        let metadata = coin_wrapper::create_fungible_asset_test<MyToken>();
        let reward_tokens = vector::empty<Object<Metadata>>();
        vector::push_back(&mut reward_tokens, metadata);
        let _rewards_pool = rewards_pool::create_test(reward_tokens);
        let _rewards_pool_tokens = rewards_pool::default_reward_tokens(_rewards_pool);
        assert!(vector::length<Object<Metadata>>(&_rewards_pool_tokens) == 0, 1);
    }

    #[test(source = @0xcafe, resource_acc = @0xc3bb8488ab1a5815a9d543d7e41b0e0df46a7396f89b22821f07a4362f75ddc5)]
    public fun add_rewards_test(source: &signer, resource_acc: &signer) : (coin::BurnCapability<MyToken>, coin::FreezeCapability<MyToken>, coin::MintCapability<MyToken>) {
        setup(source, resource_acc);
        let (burn_cap, freeze_cap, mint_cap) = coin::initialize<MyToken>(
            resource_acc,
            string::utf8(b"MyToken"),
            string::utf8(b"MTK"),
            8,
            true
        );

        move_to<TokenManager>(resource_acc, TokenManager {
            burn_cap,
            freeze_cap,
            mint_cap,
        });

        let initial_amount = 100;
        let my_token_coin = coin::mint<MyToken>(initial_amount, &mint_cap);
        let my_token_coin1 = coin::mint<MyToken>(initial_amount, &mint_cap);
        let _fungible_asset = coin_wrapper::wrap_test<MyToken>(my_token_coin);
        let _fungible_asset1 = coin_wrapper::wrap_test<MyToken>(my_token_coin1);
        primary_fungible_store::deposit(signer::address_of(resource_acc), _fungible_asset1);

        let _fungible_assets = vector::empty<FungibleAsset>();
        vector::push_back(&mut _fungible_assets, _fungible_asset);
        let metadata = coin_wrapper::create_fungible_asset_test<MyToken>();
        let reward_tokens = vector::empty<Object<Metadata>>();
        vector::push_back(&mut reward_tokens, metadata);
        let _rewards_pool = rewards_pool::create_test(reward_tokens);
        rewards_pool::add_rewards_test(_rewards_pool, _fungible_assets, 10);
        (burn_cap, freeze_cap, mint_cap)
    }

    #[test(source = @0xcafe, resource_acc = @0xc3bb8488ab1a5815a9d543d7e41b0e0df46a7396f89b22821f07a4362f75ddc5)]
    public fun claim_rewards_test(source: &signer, resource_acc: &signer) : (vector<FungibleAsset>, coin::BurnCapability<MyToken>, coin::FreezeCapability<MyToken>, coin::MintCapability<MyToken>) {
        setup(source, resource_acc);
        let (burn_cap, freeze_cap, mint_cap) = coin::initialize<MyToken>(
            resource_acc,
            string::utf8(b"MyToken"),
            string::utf8(b"MTK"),
            8,
            true
        );

        move_to<TokenManager>(resource_acc, TokenManager {
            burn_cap,
            freeze_cap,
            mint_cap,
        });

        let initial_amount = 100;
        let my_token_coin = coin::mint<MyToken>(initial_amount, &mint_cap);
        let my_token_coin1 = coin::mint<MyToken>(initial_amount, &mint_cap);
        let _fungible_asset = coin_wrapper::wrap_test<MyToken>(my_token_coin);
        let _fungible_asset1 = coin_wrapper::wrap_test<MyToken>(my_token_coin1);
        primary_fungible_store::deposit(signer::address_of(resource_acc), _fungible_asset1);
        
        let _fungible_assets = vector::empty<FungibleAsset>();
        vector::push_back(&mut _fungible_assets, _fungible_asset);
        let metadata = coin_wrapper::create_fungible_asset_test<MyToken>();
        let reward_tokens = vector::empty<Object<Metadata>>();
        vector::push_back(&mut reward_tokens, metadata);
        let _rewards_pool = rewards_pool::create_test(reward_tokens);
        rewards_pool::add_rewards_test(_rewards_pool, _fungible_assets, 2);
        timestamp::update_global_time_for_test_secs(3600*24*7*3);
        let claimed_rewards = rewards_pool::claim_rewards_test(signer::address_of(resource_acc), _rewards_pool, 2);
        assert!(vector::length<FungibleAsset>(&claimed_rewards) > 0, 2);
        (claimed_rewards, burn_cap, freeze_cap, mint_cap)
    }

    #[test(source = @0xcafe, resource_acc = @0xc3bb8488ab1a5815a9d543d7e41b0e0df46a7396f89b22821f07a4362f75ddc5)]
    public fun allocation_test(source: &signer, resource_acc: &signer) {
        setup(source, resource_acc);
        let (burn_cap, freeze_cap, mint_cap) = coin::initialize<MyToken>(
            resource_acc,
            string::utf8(b"MyToken"),
            string::utf8(b"MTK"),
            8,
            true
        );

        move_to<TokenManager>(resource_acc, TokenManager {
            burn_cap,
            freeze_cap,
            mint_cap,
        });

        let metadata = coin_wrapper::create_fungible_asset_test<MyToken>();
        let reward_tokens = vector::empty<Object<Metadata>>();
        vector::push_back(&mut reward_tokens, metadata);
        let _rewards_pool = rewards_pool::create_test(reward_tokens);

        let token_amount_change = 50;
        rewards_pool::increase_allocation_test(signer::address_of(resource_acc), _rewards_pool, token_amount_change);
        let (user_shares, _) = rewards_pool::claimer_shares(signer::address_of(resource_acc), _rewards_pool, 0);
        assert!(user_shares == token_amount_change, 3);

        rewards_pool::decrease_allocation_test(signer::address_of(resource_acc), _rewards_pool, token_amount_change / 2);
        let (user_shares_after_decrease, _) = rewards_pool::claimer_shares(signer::address_of(resource_acc), _rewards_pool, 0);
        assert!(user_shares_after_decrease == token_amount_change / 2, 4);
    }
}