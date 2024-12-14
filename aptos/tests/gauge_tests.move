#[test_only]
module fullsail::gauge_tests {
    use aptos_framework::account;
    use aptos_framework::signer;
    use aptos_framework::resource_account;
    use aptos_framework::timestamp;
    use aptos_framework::coin;
    use std::string;
    use std::vector;
    use fullsail::my_token::{MyToken, MyToken1};
    use fullsail::coin_wrapper;
    use fullsail::liquidity_pool;
    use fullsail::package_manager;
    use fullsail::gauge;
    use fullsail::cellana_token;

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
        timestamp::set_time_has_started_for_testing(&account::create_signer_for_test(@0x1));
    }

    #[test(source = @0xcafe, resource_acc = @0xc3bb8488ab1a5815a9d543d7e41b0e0df46a7396f89b22821f07a4362f75ddc5)]
    public fun create_test(source: &signer, resource_acc: &signer) {
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
        let _gauge = gauge::create_test(_liquidity_pool);
        assert!(gauge::claimable_rewards(signer::address_of(resource_acc), _gauge) == 0, 1);
    }

    #[test(source = @0xcafe, resource_acc = @0xc3bb8488ab1a5815a9d543d7e41b0e0df46a7396f89b22821f07a4362f75ddc5)]
    public fun staking_into_gauge_test(source: &signer, resource_acc: &signer) : (coin::MintCapability<MyToken>, coin::MintCapability<MyToken1>) {
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

        let initial_amount = 2000;
        let my_token_coin = coin::mint<MyToken>(initial_amount, &mint_cap);
        let my_token_coin1 = coin::mint<MyToken1>(initial_amount, &mint_cap1);
        let _fungible_asset = coin_wrapper::wrap_test<MyToken>(my_token_coin);
        let _fungible_asset1 = coin_wrapper::wrap_test<MyToken1>(my_token_coin1);
        let _mint_lp_amount = liquidity_pool::mint_lp_test(resource_acc, _fungible_asset, _fungible_asset1, false);

        let _gauge = gauge::create_test(_liquidity_pool);
        gauge::stake(resource_acc, _gauge, 100);
        let _stake_balance = gauge::stake_balance(signer::address_of(resource_acc), _gauge);
        assert!(_stake_balance == 100, 2);
        let _total_stake = gauge::total_stake(_gauge);
        assert!(_total_stake == 100, 3);
        (mint_cap, mint_cap1)
    }

    #[test(source = @0xcafe, resource_acc = @0xc3bb8488ab1a5815a9d543d7e41b0e0df46a7396f89b22821f07a4362f75ddc5)]
    public fun unstaking_into_gauge_test(source: &signer, resource_acc: &signer) : (coin::MintCapability<MyToken>, coin::MintCapability<MyToken1>) {
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

        let initial_amount = 2000;
        let my_token_coin = coin::mint<MyToken>(initial_amount, &mint_cap);
        let my_token_coin1 = coin::mint<MyToken1>(initial_amount, &mint_cap1);
        let _fungible_asset = coin_wrapper::wrap_test<MyToken>(my_token_coin);
        let _fungible_asset1 = coin_wrapper::wrap_test<MyToken1>(my_token_coin1);
        let _mint_lp_amount = liquidity_pool::mint_lp_test(resource_acc, _fungible_asset, _fungible_asset1, false);

        let _gauge = gauge::create_test(_liquidity_pool);
        gauge::stake(resource_acc, _gauge, 100);
        gauge::unstake_lp_test(resource_acc, _gauge, 50);
        let _stake_balance = gauge::stake_balance(signer::address_of(resource_acc), _gauge);
        assert!(_stake_balance == 50, 4);
        let _total_stake = gauge::total_stake(_gauge);
        assert!(_total_stake == 50, 5);
        (mint_cap, mint_cap1)
    }

    #[test(source = @0xcafe, resource_acc = @0xc3bb8488ab1a5815a9d543d7e41b0e0df46a7396f89b22821f07a4362f75ddc5)]
    public fun claiming_rewards_test(source: &signer, resource_acc: &signer) : (coin::MintCapability<MyToken>, coin::MintCapability<MyToken1>) {
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

        let initial_amount = 2000;
        let my_token_coin = coin::mint<MyToken>(initial_amount, &mint_cap);
        let my_token_coin1 = coin::mint<MyToken1>(initial_amount, &mint_cap1);
        let _fungible_asset = coin_wrapper::wrap_test<MyToken>(my_token_coin);
        let _fungible_asset1 = coin_wrapper::wrap_test<MyToken1>(my_token_coin1);
        let _mint_lp_amount = liquidity_pool::mint_lp_test(resource_acc, _fungible_asset, _fungible_asset1, false);

        let _gauge = gauge::create_test(_liquidity_pool);
        timestamp::update_global_time_for_test_secs(3600*24*7*3);
        let _claimable_rewards = gauge::claimable_rewards(signer::address_of(resource_acc), _gauge);
        assert!(_claimable_rewards == 0, 6);
        (mint_cap, mint_cap1)
    }
}