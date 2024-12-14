#[test_only]
module fullsail::vote_manager_tests {
    use aptos_framework::account;
    use aptos_framework::signer;
    use aptos_framework::resource_account;
    use aptos_framework::timestamp;
    use aptos_framework::coin;
    use aptos_framework::primary_fungible_store;
    use aptos_framework::genesis;
    use std::string;
    use std::vector;

    use fullsail::coin_wrapper;
    use fullsail::liquidity_pool;
    use fullsail::package_manager;
    use fullsail::cellana_token;
    use fullsail::my_token::{MyToken, MyToken1};
    use fullsail::vote_manager;
    use fullsail::voting_escrow;

    struct TokenManager has key {
        burn_cap: coin::BurnCapability<MyToken>,
        freeze_cap: coin::FreezeCapability<MyToken>,
        mint_cap: coin::MintCapability<MyToken>,
    }

    struct TokenManager1 has key {
        burn_cap1: coin::BurnCapability<MyToken1>,
        freeze_cap1: coin::FreezeCapability<MyToken1>,
        mint_cap1: coin::MintCapability<MyToken1>,
    }

    #[test_only]
    fun setup(source: &signer, resource_acc: &signer) {
        account::create_account_for_test(signer::address_of(source));
        resource_account::create_resource_account(source, vector::empty(), vector::empty());
        package_manager::init_module_test(resource_acc);
        coin_wrapper::initialize();
        liquidity_pool::initialize();
        cellana_token::initialize();
        genesis::setup();
        vote_manager::initialize();
    }

    #[test(source = @0xcafe, resource_acc = @0xc3bb8488ab1a5815a9d543d7e41b0e0df46a7396f89b22821f07a4362f75ddc5)]
    public fun voting_manager_initialized_test(source: &signer, resource_acc: &signer) {
        setup(source, resource_acc);
        assert!(vote_manager::is_initialized(), 1);
    }

    #[test(source = @0xcafe, resource_acc = @0xc3bb8488ab1a5815a9d543d7e41b0e0df46a7396f89b22821f07a4362f75ddc5)]
    public fun create_gauge_test(source: &signer, resource_acc: &signer) {
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

        let (burn_cap1, freeze_cap1, mint_cap1) = coin::initialize<MyToken1>(
            resource_acc,
            string::utf8(b"MyToken1"),
            string::utf8(b"MTK1"),
            8,
            true
        );

        move_to<TokenManager1>(resource_acc, TokenManager1 {
            burn_cap1,
            freeze_cap1,
            mint_cap1,
        });

        let metadata = coin_wrapper::create_fungible_asset_test<MyToken>();
        let metadata1 = coin_wrapper::create_fungible_asset_test<MyToken1>();
        let _liquidity_pool = liquidity_pool::create_test(metadata, metadata1, false);
        let _gauge = vote_manager::create_gauge(resource_acc, _liquidity_pool);
        assert!(vote_manager::is_gauge_active(_gauge), 2);
    }

    #[test(source = @0xcafe, resource_acc = @0xc3bb8488ab1a5815a9d543d7e41b0e0df46a7396f89b22821f07a4362f75ddc5)]
    public fun disable_and_enable_gauge_test(source: &signer, resource_acc: &signer) {
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

        let (burn_cap1, freeze_cap1, mint_cap1) = coin::initialize<MyToken1>(
            resource_acc,
            string::utf8(b"MyToken1"),
            string::utf8(b"MTK1"),
            8,
            true
        );

        move_to<TokenManager1>(resource_acc, TokenManager1 {
            burn_cap1,
            freeze_cap1,
            mint_cap1,
        });

        let metadata = coin_wrapper::create_fungible_asset_test<MyToken>();
        let metadata1 = coin_wrapper::create_fungible_asset_test<MyToken1>();
        let _liquidity_pool = liquidity_pool::create_test(metadata, metadata1, false);
        let _gauge = vote_manager::create_gauge(resource_acc, _liquidity_pool);
        vote_manager::disable_gauge(resource_acc, _gauge);
        assert!(!vote_manager::is_gauge_active(_gauge), 3);
        vote_manager::enable_gauge(resource_acc, _gauge);
        assert!(vote_manager::is_gauge_active(_gauge), 4);
    }

    #[test(source = @0xcafe, resource_acc = @0xc3bb8488ab1a5815a9d543d7e41b0e0df46a7396f89b22821f07a4362f75ddc5)]
    public fun vote_test(source: &signer, resource_acc: &signer) {
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

        let (burn_cap1, freeze_cap1, mint_cap1) = coin::initialize<MyToken1>(
            resource_acc,
            string::utf8(b"MyToken1"),
            string::utf8(b"MTK1"),
            8,
            true
        );

        move_to<TokenManager1>(resource_acc, TokenManager1 {
            burn_cap1,
            freeze_cap1,
            mint_cap1,
        });

        let metadata = coin_wrapper::create_fungible_asset_test<MyToken>();
        let metadata1 = coin_wrapper::create_fungible_asset_test<MyToken1>();
        let _liquidity_pool = liquidity_pool::create_test(metadata, metadata1, false);
        let _gauge = vote_manager::create_gauge(resource_acc, _liquidity_pool);

        let mint_amount = 1000;
        let lock_amount = 100;
        let duration = 10;
        let token = cellana_token::mint_test(mint_amount);
        primary_fungible_store::deposit(signer::address_of(resource_acc), token);
        let _ve_token = voting_escrow::create_lock(resource_acc, lock_amount, duration);
        
        let _weights = vector::empty<u64>();
        vector::push_back(&mut _weights, 100);
        let liquidity_pools = vector::empty();
        vector::push_back(&mut liquidity_pools, _liquidity_pool);
        
        timestamp::update_global_time_for_test_secs(3600*24*7*3);
        vote_manager::vote(resource_acc, _ve_token, liquidity_pools, _weights);
        assert!(vote_manager::last_voted_epoch(_ve_token) > 0, 5);
    }

    #[test(source = @0xcafe, resource_acc = @0xc3bb8488ab1a5815a9d543d7e41b0e0df46a7396f89b22821f07a4362f75ddc5)]
    public fun vote_batch_test(source: &signer, resource_acc: &signer) {
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

        let (burn_cap1, freeze_cap1, mint_cap1) = coin::initialize<MyToken1>(
            resource_acc,
            string::utf8(b"MyToken1"),
            string::utf8(b"MTK1"),
            8,
            true
        );

        move_to<TokenManager1>(resource_acc, TokenManager1 {
            burn_cap1,
            freeze_cap1,
            mint_cap1,
        });

        let metadata = coin_wrapper::create_fungible_asset_test<MyToken>();
        let metadata1 = coin_wrapper::create_fungible_asset_test<MyToken1>();
        let _liquidity_pool = liquidity_pool::create_test(metadata, metadata1, false);
        let _gauge = vote_manager::create_gauge(resource_acc, _liquidity_pool);

        let mint_amount = 1000;
        let lock_amount = 100;
        let duration = 10;
        let token = cellana_token::mint_test(mint_amount);
        primary_fungible_store::deposit(signer::address_of(resource_acc), token);
        let _ve_token = voting_escrow::create_lock(resource_acc, lock_amount, duration);
        let _ve_token1 = voting_escrow::create_lock(resource_acc, lock_amount, duration + 1);
        
        let _ve_tokens = vector::empty();
        vector::push_back(&mut _ve_tokens, _ve_token);
        vector::push_back(&mut _ve_tokens, _ve_token1);
        let _weights = vector::empty<u64>();
        vector::push_back(&mut _weights, 100);
        let liquidity_pools = vector::empty();
        vector::push_back(&mut liquidity_pools, _liquidity_pool);
        
        timestamp::update_global_time_for_test_secs(3600*24*7*3);
        vote_manager::vote_batch(resource_acc, _ve_tokens, liquidity_pools, _weights);
        assert!(vote_manager::last_voted_epoch(vector::pop_back(&mut _ve_tokens)) > 0, 6);
        assert!(vote_manager::last_voted_epoch(vector::pop_back(&mut _ve_tokens)) > 0, 7);
    }

    #[test(source = @0xcafe, resource_acc = @0xc3bb8488ab1a5815a9d543d7e41b0e0df46a7396f89b22821f07a4362f75ddc5)]
    public fun claim_rewards_test(source: &signer, resource_acc: &signer) {
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

        let (burn_cap1, freeze_cap1, mint_cap1) = coin::initialize<MyToken1>(
            resource_acc,
            string::utf8(b"MyToken1"),
            string::utf8(b"MTK1"),
            8,
            true
        );

        move_to<TokenManager1>(resource_acc, TokenManager1 {
            burn_cap1,
            freeze_cap1,
            mint_cap1,
        });

        let metadata = coin_wrapper::create_fungible_asset_test<MyToken>();
        let metadata1 = coin_wrapper::create_fungible_asset_test<MyToken1>();
        let _liquidity_pool = liquidity_pool::create_test(metadata, metadata1, false);
        let _gauge = vote_manager::create_gauge(resource_acc, _liquidity_pool);

        let mint_amount = 1000;
        let lock_amount = 100;
        let duration = 2;
        let token = cellana_token::mint_test(mint_amount);
        primary_fungible_store::deposit(signer::address_of(resource_acc), token);
        let _ve_token = voting_escrow::create_lock(resource_acc, lock_amount, duration);
        timestamp::update_global_time_for_test_secs(3600*24*7*20);
        vote_manager::claim_rewards<MyToken, MyToken, MyToken, MyToken, MyToken, MyToken, MyToken, MyToken, MyToken, MyToken, MyToken, MyToken, MyToken, MyToken, MyToken>(resource_acc, _ve_token, _liquidity_pool, 2);
        assert!(voting_escrow::locked_amount(_ve_token) > 0, 8);
    }

    #[test(source = @0xcafe, resource_acc = @0xc3bb8488ab1a5815a9d543d7e41b0e0df46a7396f89b22821f07a4362f75ddc5)]
    public fun advance_epoch_test(source: &signer, resource_acc: &signer) {
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

        let (burn_cap1, freeze_cap1, mint_cap1) = coin::initialize<MyToken1>(
            resource_acc,
            string::utf8(b"MyToken1"),
            string::utf8(b"MTK1"),
            8,
            true
        );

        move_to<TokenManager1>(resource_acc, TokenManager1 {
            burn_cap1,
            freeze_cap1,
            mint_cap1,
        });

        let metadata = coin_wrapper::create_fungible_asset_test<MyToken>();
        let metadata1 = coin_wrapper::create_fungible_asset_test<MyToken1>();
        let _liquidity_pool = liquidity_pool::create_test(metadata, metadata1, false);
        
        let inital_epoch = vote_manager::pending_distribution_epoch();
        timestamp::update_global_time_for_test_secs(3600*24*7*3);
        vote_manager::advance_epoch();
        let new_epoch = vote_manager::pending_distribution_epoch();
        assert!(new_epoch >= inital_epoch, 9);
    }
}