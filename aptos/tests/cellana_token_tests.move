#[test_only]
module fullsail::cellana_token_tests {
    use std::vector;
    use aptos_framework::signer;
    use aptos_framework::account;
    use aptos_framework::resource_account;
    use fullsail::package_manager;
    use fullsail::cellana_token;

    #[test_only]
    fun setup(source: &signer, resource_acc: &signer) {
        account::create_account_for_test(signer::address_of(source));
        resource_account::create_resource_account(source, vector::empty(), vector::empty());
        package_manager::init_module_test(resource_acc);
        cellana_token::initialize_test();
    }

    #[test(source = @0xcafe, resource_acc = @0xc3bb8488ab1a5815a9d543d7e41b0e0df46a7396f89b22821f07a4362f75ddc5)]
    public fun token_initialized_test(source: &signer, resource_acc: &signer) {
        setup(source, resource_acc);
        assert!(cellana_token::is_initialized(), 1);
    }

    #[test(source = @0xcafe, resource_acc = @0xc3bb8488ab1a5815a9d543d7e41b0e0df46a7396f89b22821f07a4362f75ddc5)]
    public fun token_mint_test(source: &signer, resource_acc: &signer) {
        setup(source, resource_acc);
        let token = cellana_token::mint_test(100);
        cellana_token::burn_test(token); 
        assert!(cellana_token::total_supply() == 0, 2);
    }

    #[test(source = @0xcafe, resource_acc = @0xc3bb8488ab1a5815a9d543d7e41b0e0df46a7396f89b22821f07a4362f75ddc5)]
    public fun token_burn_test(source: &signer, resource_acc: &signer) {
        setup(source, resource_acc);
        let token = cellana_token::mint_test(100);
        cellana_token::burn_test(token); 
        assert!(cellana_token::total_supply() == 0, 3);
    }
}
