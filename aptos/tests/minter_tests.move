#[test_only]
module fullsail::minter_tests {
    use aptos_framework::account;
    use aptos_framework::signer;
    use aptos_framework::resource_account;
    use aptos_framework::fungible_asset::{Self, FungibleAsset};
    use aptos_framework::genesis;
    use aptos_framework::timestamp;
    use std::vector;

    use fullsail::minter;
    use fullsail::cellana_token;
    use fullsail::package_manager;
    use fullsail::voting_escrow;

    const INIT_GUID_CREATION_NUM: u64 = 0x4000000000000;

    #[test_only]
    fun setup(source: &signer, resource_acc: &signer) {
        account::create_account_for_test(signer::address_of(source));
        resource_account::create_resource_account(source, vector::empty(), vector::empty());
        package_manager::init_module_test(resource_acc);
        cellana_token::initialize_test();
        voting_escrow::initialize();
        genesis::setup();
        minter::initialize();
    }

    #[test(source = @0xcafe, resource_acc = @0xc3bb8488ab1a5815a9d543d7e41b0e0df46a7396f89b22821f07a4362f75ddc5)]
    public fun minter_initialized_test(source: &signer, resource_acc: &signer) {
        setup(source, resource_acc);
        assert!(minter::is_initialized(), 1);
    }

    #[test(source = @0xcafe, resource_acc = @0xc3bb8488ab1a5815a9d543d7e41b0e0df46a7396f89b22821f07a4362f75ddc5)]
    public fun mint_test(source: &signer, resource_acc: &signer) : (FungibleAsset, FungibleAsset) {
        setup(source, resource_acc);
        timestamp::update_global_time_for_test_secs(3600*24*7*1);
        let (minted_tokens, additional_minted_tokens) = minter::mint_test();
        assert!(fungible_asset::amount(&minted_tokens) != 0, 2);
        (minted_tokens, additional_minted_tokens)
    }

    #[test(source = @0xcafe, resource_acc = @0xc3bb8488ab1a5815a9d543d7e41b0e0df46a7396f89b22821f07a4362f75ddc5)]
    public fun confirm_new_team_test(source: &signer, resource_acc: &signer) {
        setup(source, resource_acc);
        let new_team = account::create_account_for_test(@0x0123);
        minter::update_team_account(resource_acc, signer::address_of(&new_team));
        minter::confirm_new_team_account(&new_team);
        assert!(minter::team() == signer::address_of(&new_team), 3);
    }

    #[test(source = @0xcafe, resource_acc = @0xc3bb8488ab1a5815a9d543d7e41b0e0df46a7396f89b22821f07a4362f75ddc5)]
    public fun set_team_rate_test(source: &signer, resource_acc: &signer) {
        setup(source, resource_acc);
        let new_emission_rate = 50;
        minter::set_team_rate(resource_acc, new_emission_rate);
        assert!(minter::team_emission_rate_bps() == new_emission_rate, 4);
    }

    #[test(source = @0xcafe, resource_acc = @0xc3bb8488ab1a5815a9d543d7e41b0e0df46a7396f89b22821f07a4362f75ddc5)]
    public fun current_rebase_test(source: &signer, resource_acc: &signer) : FungibleAsset {
        setup(source, resource_acc);
        let initial_rebase = minter::current_rebase();
        let _asset = cellana_token::mint_test(100000);
        let new_rebase = minter::current_rebase();
        assert!(new_rebase != initial_rebase, 5);
        _asset
    }
}