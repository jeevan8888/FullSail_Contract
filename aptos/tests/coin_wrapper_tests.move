#[test_only]
module fullsail::coin_wrapper_tests {
    use std::vector;
    use std::coin;
    use aptos_framework::resource_account;
    use aptos_framework::account;
    use aptos_framework::signer;
    use aptos_framework::fungible_asset;
    use aptos_framework::string;

    use fullsail::package_manager;
    use fullsail::coin_wrapper;
    use fullsail::my_token::{MyToken};

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
    }

    #[test(source = @0xcafe, resource_acc = @0xc3bb8488ab1a5815a9d543d7e41b0e0df46a7396f89b22821f07a4362f75ddc5)]
    public fun coin_wrapper_initialized_test(source: &signer, resource_acc: &signer) {
        setup(source, resource_acc);
        coin_wrapper::initialize();
        assert!(coin_wrapper::is_initialized(), 1);
    }

    #[test(source = @0xcafe, resource_acc = @0xc3bb8488ab1a5815a9d543d7e41b0e0df46a7396f89b22821f07a4362f75ddc5)]
    public fun create_fungible_asset_test(source: &signer, resource_acc: &signer) {
        setup(source, resource_acc);
        coin_wrapper::initialize();
        let (burn_cap, freeze_cap, mint_cap) = coin::initialize<MyToken>(resource_acc, string::utf8(b"MyToken"), string::utf8(b"MTK"), 8, true);
        move_to<TokenManager>(resource_acc, TokenManager{
            burn_cap,
            freeze_cap,
            mint_cap,
        });
        let metadata = coin_wrapper::create_fungible_asset_test<MyToken>();
        assert!(fungible_asset::name(metadata) == string::utf8(b"MyToken"), 2);
    }
    
    #[test(source = @0xcafe, resource_acc = @0xc3bb8488ab1a5815a9d543d7e41b0e0df46a7396f89b22821f07a4362f75ddc5)]
    public fun wrap_and_unwrap_test(source: &signer, resource_acc: &signer) : (coin::BurnCapability<MyToken>, coin::FreezeCapability<MyToken>, coin::MintCapability<MyToken>) {
        setup(source, resource_acc);
        coin_wrapper::initialize();

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
        let fungible_asset = coin_wrapper::wrap_test<MyToken>(my_token_coin);

        assert!(fungible_asset::amount(&fungible_asset) == initial_amount, 3);

        let unwrapped_coin = coin_wrapper::unwrap_test<MyToken>(fungible_asset);
        let value = coin::value<MyToken>(&unwrapped_coin);
        assert!(value == initial_amount, 4);
        coin::burn<MyToken>(unwrapped_coin, &burn_cap);
        (burn_cap, freeze_cap, mint_cap)
    }

    #[test(source = @0xcafe, resource_acc = @0xc3bb8488ab1a5815a9d543d7e41b0e0df46a7396f89b22821f07a4362f75ddc5)]
    public fun is_wrapper_Test(source: &signer, resource_acc: &signer) {
        setup(source, resource_acc);
        coin_wrapper::initialize();

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
        assert!(coin_wrapper::is_wrapper(metadata), 6);
    }

    #[test(source = @0xcafe, resource_acc = @0xc3bb8488ab1a5815a9d543d7e41b0e0df46a7396f89b22821f07a4362f75ddc5)]
    public fun is_supported_test(source: &signer, resource_acc: &signer) {
        setup(source, resource_acc);
        coin_wrapper::initialize();

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
        coin_wrapper::create_fungible_asset_test<MyToken>();
        assert!(coin_wrapper::is_supported<MyToken>(), 7);
    }
}