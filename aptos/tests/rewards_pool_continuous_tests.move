#[test_only]
module fullsail::rewards_pool_continuous_tests {
    use aptos_framework::account;
    use aptos_framework::signer;
    use aptos_framework::resource_account;
    use aptos_framework::object;
    use aptos_framework::fungible_asset;
    use aptos_framework::timestamp;
    use aptos_framework::coin;

    use std::string;
    use std::vector;
    use std::option;
    use fullsail::rewards_pool_continuous;
    use fullsail::package_manager;
    use fullsail::my_token::{MyToken};
    use fullsail::coin_wrapper;

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
        timestamp::set_time_has_started_for_testing(&account::create_signer_for_test(@0x1));
    }

    #[test(source = @0xcafe, resource_acc = @0xc3bb8488ab1a5815a9d543d7e41b0e0df46a7396f89b22821f07a4362f75ddc5)]
    public fun add_rewards_test(source: &signer, resource_acc: &signer) {
        setup(source, resource_acc);
        let account = object::create_named_object(source, b"test");
        let metadata = fungible_asset::add_fungibility(
            &account,
            option::some(100),
            string::utf8(b"test"),
            string::utf8(b"TOK"),
            8,
            string::utf8(b"https://example.com/icon.png"),
            string::utf8(b"https://example.com"),
        );
        let rewards_pool = rewards_pool_continuous::create_test(metadata, 10000);
        let mint_ref = &fungible_asset::generate_mint_ref(&account);
        let asset = fungible_asset::mint(mint_ref, 10);
        rewards_pool_continuous::add_rewards_test(rewards_pool, asset);
        assert!(rewards_pool_continuous::total_unclaimed_rewards(rewards_pool) == 10, 1);
    }

    #[test(source = @0xcafe, resource_acc = @0xc3bb8488ab1a5815a9d543d7e41b0e0df46a7396f89b22821f07a4362f75ddc5)]
    public fun stake_test(source: &signer, resource_acc: &signer) {
        setup(source, resource_acc);
        let account = object::create_named_object(source, b"test");
        let metadata = fungible_asset::add_fungibility(
            &account,
            option::some(100),
            string::utf8(b"test"),
            string::utf8(b"TOK"),
            8,
            string::utf8(b"https://example.com/icon.png"),
            string::utf8(b"https://example.com"),
        );
        let rewards_pool = rewards_pool_continuous::create_test(metadata, 10000);
        let test_addr = @0x123;
        rewards_pool_continuous::stake_test(test_addr, rewards_pool, 100);
        assert!(rewards_pool_continuous::total_stake(rewards_pool) == 100, 2);
    }
    
    #[test(source = @0xcafe, resource_acc = @0xc3bb8488ab1a5815a9d543d7e41b0e0df46a7396f89b22821f07a4362f75ddc5)]
    public fun unstake_test(source: &signer, resource_acc: &signer) {
        setup(source, resource_acc);
        let account = object::create_named_object(source, b"test");
        let metadata = fungible_asset::add_fungibility(
            &account,
            option::some(100),
            string::utf8(b"test"),
            string::utf8(b"TOK"),
            8,
            string::utf8(b"https://example.com/icon.png"),
            string::utf8(b"https://example.com"),
        );
        let rewards_pool = rewards_pool_continuous::create_test(metadata, 10000);
        let test_addr = @0x123;
        rewards_pool_continuous::stake_test(test_addr, rewards_pool, 200);
        rewards_pool_continuous::unstake_test(test_addr, rewards_pool, 100);
        assert!(rewards_pool_continuous::total_stake(rewards_pool) == 100, 3);
    }

    #[test(source = @0xcafe, resource_acc = @0xc3bb8488ab1a5815a9d543d7e41b0e0df46a7396f89b22821f07a4362f75ddc5)]
    #[expected_failure]
    public fun claim_rewards_test(source: &signer, resource_acc: &signer) : coin::MintCapability<MyToken> {
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
        
        let initial_amount = 10000;
        let my_token_coin = coin::mint<MyToken>(initial_amount, &mint_cap);
        let asset = coin_wrapper::wrap_test<MyToken>(my_token_coin);
        let metadata = coin_wrapper::create_fungible_asset_test<MyToken>();

        let rewards_pool = rewards_pool_continuous::create_test(metadata, 10000);
        rewards_pool_continuous::add_rewards_test(rewards_pool, asset);
        
        rewards_pool_continuous::stake_test(signer::address_of(resource_acc), rewards_pool, 100);
        let claim_asset = rewards_pool_continuous::claim_rewards_test(signer::address_of(resource_acc), rewards_pool);
        fungible_asset::destroy_zero(claim_asset);
        assert!(rewards_pool_continuous::total_unclaimed_rewards(rewards_pool) == 10000, 4);
        mint_cap
    }
}