#[test_only]
module fullsail::token_whitelist_tests {
    use std::string;
    use std::vector;
    use aptos_framework::account;
    use aptos_framework::resource_account;
    use aptos_framework::signer;
    use fullsail::package_manager;
    use fullsail::token_whitelist;

    // setup
    #[test_only]
    fun setup(source: &signer, resource_acc: &signer) {

        // resource account
        account::create_account_for_test(signer::address_of(source));
        resource_account::create_resource_account(source, vector::empty(), vector::empty());

        // initialize package manager
        package_manager::init_module_test(resource_acc);
    }

    #[test(fullsail = @fullsail, source = @0xcafe, resource_acc = @0xc3bb8488ab1a5815a9d543d7e41b0e0df46a7396f89b22821f07a4362f75ddc5)]
    public entry fun test_initialize(fullsail: &signer, source: &signer, resource_acc: &signer) {
        setup(source, resource_acc);
        account::create_account_for_test(@fullsail);
        let fullsail_addr = signer::address_of(fullsail);

        // test initial state
        assert!(!token_whitelist::is_initialized_test(fullsail_addr), 0);
        
        // init
        token_whitelist::initialize_for_test();
        
        // test after initialization
        assert!(token_whitelist::is_initialized_test(fullsail_addr), 1);
        
        // test idempotency
        token_whitelist::initialize();
        assert!(token_whitelist::is_initialized(), 2);
    }

    #[test(fullsail = @fullsail, source = @0xcafe, resource_acc = @0xc3bb8488ab1a5815a9d543d7e41b0e0df46a7396f89b22821f07a4362f75ddc5)]
    public entry fun test_are_whitelisted(source: &signer, resource_acc: &signer) {
        setup(source, resource_acc);
        account::create_account_for_test(@fullsail);
        token_whitelist::initialize();

        // add tokens to whitelist
        let tokens_to_add = vector[
            string::utf8(b"TokenA"),
            string::utf8(b"TokenB"),
            string::utf8(b"TokenC")
        ];
        token_whitelist::add_to_whitelist_test(tokens_to_add);

        // test whitelisted tokens
        let test_tokens = vector[
            string::utf8(b"TokenA"),
            string::utf8(b"TokenB")
        ];
        assert!(token_whitelist::are_whitelisted(test_tokens), 3);

        // test non-whitelisted token
        let non_whitelisted = vector[string::utf8(b"TokenD")];
        assert!(!token_whitelist::are_whitelisted(non_whitelisted), 4);

        // test mixed case
        let mixed_tokens = vector[
            string::utf8(b"TokenA"),
            string::utf8(b"TokenD")
        ];
        assert!(!token_whitelist::are_whitelisted(mixed_tokens), 5);
    }


}