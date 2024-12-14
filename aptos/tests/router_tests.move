#[test_only]
module fullsail::router_tests {
    use aptos_framework::account;
    use aptos_framework::signer;
    use aptos_framework::resource_account;
    use aptos_framework::timestamp;
    use aptos_framework::coin;
    use aptos_framework::fungible_asset::{Self, FungibleAsset};
    use aptos_framework::object;
    use std::string;
    use std::vector;

    use fullsail::coin_wrapper;
    use fullsail::liquidity_pool;
    use fullsail::package_manager;
    use fullsail::my_token::{MyToken, MyToken1};
    use fullsail::vote_manager;
    use fullsail::router;
    use fullsail::gauge;

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
        timestamp::set_time_has_started_for_testing(&account::create_signer_for_test(@0x1));
        vote_manager::initialize();
    }

    #[test(source = @0xcafe, resource_acc = @0xc3bb8488ab1a5815a9d543d7e41b0e0df46a7396f89b22821f07a4362f75ddc5)]
    public fun swap_test(source: &signer, resource_acc: &signer) : (coin::MintCapability<MyToken>, coin::MintCapability<MyToken1>, FungibleAsset) {
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

        let initial_amount = 10000;
        let my_token_coin = coin::mint<MyToken>(initial_amount, &mint_cap);
        let fungible_asset = coin_wrapper::wrap_test<MyToken>(my_token_coin);

        let initial_amount1 = 10000;
        let my_token_coin1 = coin::mint<MyToken1>(initial_amount1, &mint_cap1);
        let fungible_asset1 = coin_wrapper::wrap_test<MyToken1>(my_token_coin1);

        let metadata = coin_wrapper::create_fungible_asset_test<MyToken>();
        let metadata1 = coin_wrapper::create_fungible_asset_test<MyToken1>();
        
        let _liquidity_pool = liquidity_pool::create_test(metadata, metadata1, false);
        liquidity_pool::mint_lp_test(resource_acc, fungible_asset, fungible_asset1, false);

        let initial_amount2 = 500;
        let my_token_coin2 = coin::mint<MyToken>(initial_amount2, &mint_cap);
        let fungible_asset2 = coin_wrapper::wrap_test<MyToken>(my_token_coin2);
        let output_fungible_asset = router::swap(fungible_asset2, 400, metadata1, false);
        (mint_cap, mint_cap1, output_fungible_asset)
    }

    #[test(source = @0xcafe, resource_acc = @0xc3bb8488ab1a5815a9d543d7e41b0e0df46a7396f89b22821f07a4362f75ddc5)]
    public fun get_amount_out_test(source: &signer, resource_acc: &signer) : (coin::MintCapability<MyToken>, coin::MintCapability<MyToken1>) {
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

        let initial_amount = 10000;
        let my_token_coin = coin::mint<MyToken>(initial_amount, &mint_cap);
        let fungible_asset = coin_wrapper::wrap_test<MyToken>(my_token_coin);

        let initial_amount1 = 10000;
        let my_token_coin1 = coin::mint<MyToken1>(initial_amount1, &mint_cap1);
        let fungible_asset1 = coin_wrapper::wrap_test<MyToken1>(my_token_coin1);

        let metadata = coin_wrapper::create_fungible_asset_test<MyToken>();
        let metadata1 = coin_wrapper::create_fungible_asset_test<MyToken1>();
        
        let _liquidity_pool = liquidity_pool::create_test(metadata, metadata1, false);
        liquidity_pool::mint_lp_test(resource_acc, fungible_asset, fungible_asset1, false);

        let (output_amount, _) = router::get_amount_out(500, metadata, metadata1, false);
        assert!(output_amount > 0, 2);
        (mint_cap, mint_cap1)
    }

    #[test(source = @0xcafe, resource_acc = @0xc3bb8488ab1a5815a9d543d7e41b0e0df46a7396f89b22821f07a4362f75ddc5)]
    public fun get_trade_diff_test(source: &signer, resource_acc: &signer) : (coin::MintCapability<MyToken>, coin::MintCapability<MyToken1>) {
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

        let initial_amount = 10000;
        let my_token_coin = coin::mint<MyToken>(initial_amount, &mint_cap);
        let fungible_asset = coin_wrapper::wrap_test<MyToken>(my_token_coin);

        let initial_amount1 = 10000;
        let my_token_coin1 = coin::mint<MyToken1>(initial_amount1, &mint_cap1);
        let fungible_asset1 = coin_wrapper::wrap_test<MyToken1>(my_token_coin1);

        let metadata = coin_wrapper::create_fungible_asset_test<MyToken>();
        let metadata1 = coin_wrapper::create_fungible_asset_test<MyToken1>();
        
        let _liquidity_pool = liquidity_pool::create_test(metadata, metadata1, false);
        liquidity_pool::mint_lp_test(resource_acc, fungible_asset, fungible_asset1, false);

        let (output_amount_calculated, output_amount_input) = router::get_trade_diff(500, metadata, metadata1, false);
        assert!(output_amount_calculated <= output_amount_input, 3);
        (mint_cap, mint_cap1)
    }

    #[test(source = @0xcafe, resource_acc = @0xc3bb8488ab1a5815a9d543d7e41b0e0df46a7396f89b22821f07a4362f75ddc5)]
    public fun add_liquidity_and_stake_both_coins_test(source: &signer, resource_acc: &signer) : (coin::MintCapability<MyToken>, coin::MintCapability<MyToken1>) {
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
        let my_token_coin2 = coin::mint<MyToken>(initial_amount, &mint_cap);
        let my_token_coin3 = coin::mint<MyToken1>(initial_amount, &mint_cap1);
        coin::register<MyToken>(resource_acc);
        coin::register<MyToken1>(resource_acc);
        coin::deposit<MyToken>(signer::address_of(resource_acc), my_token_coin2);
        coin::deposit<MyToken1>(signer::address_of(resource_acc), my_token_coin3);
        let _fungible_asset = coin_wrapper::wrap_test<MyToken>(my_token_coin);
        let _fungible_asset1 = coin_wrapper::wrap_test<MyToken1>(my_token_coin1);
        let _mint_lp_amount = liquidity_pool::mint_lp_test(resource_acc, _fungible_asset, _fungible_asset1, false);

        let _gauge = vote_manager::create_gauge(resource_acc, _liquidity_pool);
        
        router::add_liquidity_and_stake_both_coins_entry<MyToken, MyToken1>(resource_acc, false, 100, 100);

        let _stake_balance = gauge::stake_balance(signer::address_of(resource_acc), _gauge);
        assert!(_stake_balance == 100, 2);
        let _total_stake = gauge::total_stake(_gauge);
        assert!(_total_stake == 100, 3);
        (mint_cap, mint_cap1)
    }

    #[test(source = @0xcafe, resource_acc = @0xc3bb8488ab1a5815a9d543d7e41b0e0df46a7396f89b22821f07a4362f75ddc5)]
    public fun get_amounts_out_test(source: &signer, resource_acc: &signer) : (coin::MintCapability<MyToken>, coin::MintCapability<MyToken1>) {
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

        let initial_amount = 10000;
        let my_token_coin = coin::mint<MyToken>(initial_amount, &mint_cap);
        let fungible_asset = coin_wrapper::wrap_test<MyToken>(my_token_coin);

        let initial_amount1 = 10000;
        let my_token_coin1 = coin::mint<MyToken1>(initial_amount1, &mint_cap1);
        let fungible_asset1 = coin_wrapper::wrap_test<MyToken1>(my_token_coin1);

        let metadata = coin_wrapper::create_fungible_asset_test<MyToken>();
        let metadata1 = coin_wrapper::create_fungible_asset_test<MyToken1>();
        
        let _liquidity_pool = liquidity_pool::create_test(metadata, metadata1, false);
        liquidity_pool::mint_lp_test(resource_acc, fungible_asset, fungible_asset1, false);

        let my_token_address = object::object_address(&metadata1);

        let _intermediary_tokens = vector::empty<address>();
        let _is_stables = vector::empty<bool>();
        vector::push_back(&mut _intermediary_tokens, my_token_address);
        vector::push_back(&mut _is_stables, false);

        let output_amount = router::get_amounts_out(500, metadata, _intermediary_tokens, _is_stables);
        assert!(output_amount > 0, 2);
        (mint_cap, mint_cap1)
    }

    #[test(source = @0xcafe, resource_acc = @0xc3bb8488ab1a5815a9d543d7e41b0e0df46a7396f89b22821f07a4362f75ddc5)]
    public fun swap_router_test(source: &signer, resource_acc: &signer) : (coin::MintCapability<MyToken>, coin::MintCapability<MyToken1>, FungibleAsset) {
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

        let initial_amount = 10000;
        let my_token_coin = coin::mint<MyToken>(initial_amount, &mint_cap);
        let fungible_asset = coin_wrapper::wrap_test<MyToken>(my_token_coin);

        let initial_amount1 = 10000;
        let my_token_coin1 = coin::mint<MyToken1>(initial_amount1, &mint_cap1);
        let fungible_asset1 = coin_wrapper::wrap_test<MyToken1>(my_token_coin1);

        let metadata = coin_wrapper::create_fungible_asset_test<MyToken>();
        let metadata1 = coin_wrapper::create_fungible_asset_test<MyToken1>();
        
        let _liquidity_pool = liquidity_pool::create_test(metadata, metadata1, false);
        liquidity_pool::mint_lp_test(resource_acc, fungible_asset, fungible_asset1, false);

        let _intermediary_tokens = vector::empty();
        let _is_stables = vector::empty<bool>();
        vector::push_back(&mut _intermediary_tokens, metadata1);
        vector::push_back(&mut _is_stables, false);

        let initial_amount2 = 500;
        let my_token_coin2 = coin::mint<MyToken>(initial_amount2, &mint_cap);
        let fungible_asset2 = coin_wrapper::wrap_test<MyToken>(my_token_coin2);

        let output_fungible_asset = router::swap_router(fungible_asset2, 400, _intermediary_tokens, _is_stables);
        assert!(fungible_asset::amount(&output_fungible_asset) > 0, 2);
        (mint_cap, mint_cap1, output_fungible_asset)
    }

    #[test(source = @0xcafe, resource_acc = @0xc3bb8488ab1a5815a9d543d7e41b0e0df46a7396f89b22821f07a4362f75ddc5)]
    public fun unstake_and_remove_liquidity_both_coins_test(source: &signer, resource_acc: &signer) : (coin::MintCapability<MyToken>, coin::MintCapability<MyToken1>) {
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

        let _gauge = vote_manager::create_gauge(resource_acc, _liquidity_pool);
        gauge::stake(resource_acc, _gauge, 100);

        router::unstake_and_remove_liquidity_both_coins_entry<MyToken, MyToken1>(resource_acc, false, 50, 50, 50, signer::address_of(resource_acc));
        let _stake_balance = gauge::stake_balance(signer::address_of(resource_acc), _gauge);
        assert!(_stake_balance == 50, 2);
        (mint_cap, mint_cap1)
    }
}