#[test_only]
module fullsail::liquidity_pool_tests {
    use aptos_framework::account;
    use aptos_framework::signer;
    use aptos_framework::resource_account;
    use aptos_framework::coin;
    use aptos_framework::fungible_asset::{Self, FungibleAsset};
    use std::string;
    use std::vector;

    use fullsail::coin_wrapper;
    use fullsail::liquidity_pool;
    use fullsail::package_manager;
    use fullsail::my_token::{MyToken, MyToken1};

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
        liquidity_pool::initialize();
    }

    #[test(source = @0xcafe, resource_acc = @0xc3bb8488ab1a5815a9d543d7e41b0e0df46a7396f89b22821f07a4362f75ddc5)]
    public fun liquidity_pool_initialized_test(source: &signer, resource_acc: &signer) {
        setup(source, resource_acc);
        assert!(liquidity_pool::is_initialized(), 1);
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

        let initial_amount2 = 1000;
        let my_token_coin2 = coin::mint<MyToken>(initial_amount2, &mint_cap);
        let fungible_asset2 = coin_wrapper::wrap_test<MyToken>(my_token_coin2);
        let output_fungible_asset = liquidity_pool::swap_test(_liquidity_pool, fungible_asset2);
        let (output_amount, _) = liquidity_pool::get_amount_out(_liquidity_pool, metadata, 1000);
        assert!(fungible_asset::amount(&output_fungible_asset) >= output_amount, 2);
        (mint_cap, mint_cap1, output_fungible_asset)
    }

    #[test(source = @0xcafe, resource_acc = @0xc3bb8488ab1a5815a9d543d7e41b0e0df46a7396f89b22821f07a4362f75ddc5)]
    public fun burn_test(source: &signer, resource_acc: &signer) : (coin::MintCapability<MyToken>, coin::MintCapability<MyToken1>, FungibleAsset, FungibleAsset) {
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

        let (fungible_asset2, fungible_asset3) = liquidity_pool::burn_test(resource_acc, metadata, metadata1, false, 1000);
        assert!(fungible_asset::amount(&fungible_asset2) == 1000 && fungible_asset::amount(&fungible_asset3) == 1000, 3);
        (mint_cap, mint_cap1, fungible_asset2, fungible_asset3)
    }

    #[test(source = @0xcafe, resource_acc = @0xc3bb8488ab1a5815a9d543d7e41b0e0df46a7396f89b22821f07a4362f75ddc5)]
    public fun claim_fees_test(source: &signer, resource_acc: &signer) : (coin::MintCapability<MyToken>, coin::MintCapability<MyToken1>, FungibleAsset, FungibleAsset) {
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
        
        let (fungible_asset2, fungible_asset3) = liquidity_pool::claim_fees_test(resource_acc, _liquidity_pool);
        assert!(fungible_asset::amount(&fungible_asset2) == 0 && fungible_asset::amount(&fungible_asset3) == 0, 3);
        (mint_cap, mint_cap1, fungible_asset2, fungible_asset3)
    }

    #[test(source = @0xcafe, resource_acc = @0xc3bb8488ab1a5815a9d543d7e41b0e0df46a7396f89b22821f07a4362f75ddc5)]
    public fun transfer_test(source: &signer, resource_acc: &signer) : (coin::MintCapability<MyToken>, coin::MintCapability<MyToken1>) {
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
        
        let recipient_addr = @0x0123;
        liquidity_pool::transfer(resource_acc, _liquidity_pool, recipient_addr, 1000);
        (mint_cap, mint_cap1)
    }
}