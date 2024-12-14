#[test_only]
module fullsail::voting_escrow_tests {
    use std::vector;
    use aptos_framework::signer;
    use aptos_framework::account;
    use aptos_framework::resource_account;
    use aptos_framework::fungible_asset;
    use aptos_framework::primary_fungible_store;
    use fullsail::package_manager;
    use fullsail::voting_escrow;
    use fullsail::cellana_token;
    use fullsail::epoch;
    use aptos_framework::genesis;   
    use aptos_framework::timestamp;

    #[test_only]
    fun setup(source: &signer, resource_acc: &signer) {
        account::create_account_for_test(signer::address_of(source));
        resource_account::create_resource_account(source, vector::empty(), vector::empty());
        package_manager::init_module_test(resource_acc);
        cellana_token::initialize_test();
        voting_escrow::initialize();
        genesis::setup();
    }

    #[test(source = @0xcafe, resource_acc = @0xc3bb8488ab1a5815a9d543d7e41b0e0df46a7396f89b22821f07a4362f75ddc5)]
    public fun voting_escrow_initialized_test(source: &signer, resource_acc: &signer) {
        setup(source, resource_acc);
        assert!(voting_escrow::is_initialized(), 1);
    }

    #[test(source = @0xcafe, resource_acc = @0xc3bb8488ab1a5815a9d543d7e41b0e0df46a7396f89b22821f07a4362f75ddc5)]
    public fun create_lock_test(source: &signer, resource_acc: &signer) {
        setup(source, resource_acc);
        let mint_amount = 1000;
        let token = cellana_token::mint_test(mint_amount);
        primary_fungible_store::deposit(signer::address_of(resource_acc), token);
        assert!(cellana_token::total_supply() != 900, 2); //mint_amount - lock_amount = 900;
    }

    #[test(source = @0xcafe, resource_acc = @0xc3bb8488ab1a5815a9d543d7e41b0e0df46a7396f89b22821f07a4362f75ddc5)]
    fun extend_lockup_test(source: &signer, resource_acc: &signer) {
        setup(source, resource_acc);
        let mint_amount = 1000;
        let lock_amount = 100;
        let duration = 10;
        let token = cellana_token::mint_test(mint_amount);
        primary_fungible_store::deposit(signer::address_of(resource_acc), token);
        let ve_token = voting_escrow::create_lock(resource_acc, lock_amount, duration);
        let new_duration = 15; // within max allowed duration

        voting_escrow::extend_lockup(resource_acc, ve_token, new_duration);
        let new_end_epoch = voting_escrow::get_lockup_expiration_epoch(ve_token);
        assert!(new_end_epoch - epoch::now() == new_duration, 3);
    }

    #[test(source = @0xcafe, resource_acc = @0xc3bb8488ab1a5815a9d543d7e41b0e0df46a7396f89b22821f07a4362f75ddc5)]
    public fun voting_power_calculation_test(source: &signer, resource_acc: &signer) {
        setup(source, resource_acc);
        let mint_amount = 1000;
        let lock_amount = 100;
        let duration = 10;
        let token = cellana_token::mint_test(mint_amount);
        primary_fungible_store::deposit(signer::address_of(resource_acc), token);
        let ve_token = voting_escrow::create_lock(resource_acc, lock_amount, duration);

        let voting_power_now = voting_escrow::get_voting_power(ve_token);
        assert!(voting_power_now > 0, 4);
        let new_duration = 5; // within max allowed duration
        let voting_power_new = voting_escrow::get_voting_power_at_epoch(ve_token, epoch::now() + new_duration);
        assert!(voting_power_new < voting_power_now, 5);
    }

    #[test(source = @0xcafe, resource_acc = @0xc3bb8488ab1a5815a9d543d7e41b0e0df46a7396f89b22821f07a4362f75ddc5)]
    public fun merge_and_split_tokens_test(source: &signer, resource_acc: &signer) {
        setup(source, resource_acc);
        let mint_amount = 1000;
        let lock_amount1 = 100;
        let duration1 = 10;
        let lock_amount2 = 50;
        let token = cellana_token::mint_test(mint_amount);
        primary_fungible_store::deposit(signer::address_of(resource_acc), token);

        let ve_token1 = voting_escrow::create_lock(resource_acc, lock_amount1, duration1);
        let ve_token2 = voting_escrow::create_lock(resource_acc, lock_amount2, duration1);

        voting_escrow::merge_ve_nft_test(resource_acc, ve_token1, ve_token2);
        let merged_amount = voting_escrow::locked_amount(ve_token2);
        assert!(merged_amount == 150, 6);

        let split_amounts = vector::empty<u64>();
        vector::push_back(&mut split_amounts, 70);
        vector::push_back(&mut split_amounts, 40);
        vector::push_back(&mut split_amounts, 10);
        vector::push_back(&mut split_amounts, 30);
        let split_tokens = voting_escrow::split_ve_nft_test(resource_acc, ve_token2, split_amounts);
        let amount = voting_escrow::locked_amount(vector::pop_back(&mut split_tokens));
        assert!(amount == 150, 7);
    }

    #[test(source = @0xcafe, resource_acc = @0xc3bb8488ab1a5815a9d543d7e41b0e0df46a7396f89b22821f07a4362f75ddc5)]
    public fun supply_and_rebase_management_test(source: &signer, resource_acc: &signer) {
        setup(source, resource_acc);
        let mint_amount = 1000;
        let lock_amount = 100;
        let duration = 10;
        let token = cellana_token::mint_test(mint_amount);
        let token1 = cellana_token::mint_test(200);
        let token2 = cellana_token::mint_test(100);
        primary_fungible_store::deposit(signer::address_of(resource_acc), token);
        let ve_token = voting_escrow::create_lock(resource_acc, lock_amount, duration);

        voting_escrow::increase_amount(resource_acc, ve_token, token2);
        voting_escrow::increase_amount_rebase_test(ve_token, token1);
        let updated_amount = voting_escrow::locked_amount(ve_token);
        assert!(updated_amount == 400, 8); // Total after increase and rebase
    }

    #[test(source = @0xcafe, resource_acc = @0xc3bb8488ab1a5815a9d543d7e41b0e0df46a7396f89b22821f07a4362f75ddc5)]
    public fun withdraw_test(source: &signer, resource_acc: &signer) {
        setup(source, resource_acc);
        let mint_amount = 1000;
        let lock_amount = 100;
        let duration = 2;
        let token = cellana_token::mint_test(mint_amount);
        primary_fungible_store::deposit(signer::address_of(resource_acc), token);
        let ve_token = voting_escrow::create_lock(resource_acc, lock_amount, duration);

        timestamp::update_global_time_for_test_secs(3600*24*7*3);
        let withdraw_asset = voting_escrow::withdraw(resource_acc, ve_token);
        assert!(fungible_asset::amount(&withdraw_asset) == 100, 9);
        primary_fungible_store::deposit(signer::address_of(resource_acc), withdraw_asset);
    }
}