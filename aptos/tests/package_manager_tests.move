#[test_only]
module fullsail::package_manager_tests {
    use std::string;
    use std::vector;
    use aptos_framework::signer;
    use aptos_framework::account;
    use aptos_framework::resource_account;
    use fullsail::package_manager;
    
    #[test_only]
    fun setup(source: &signer, resource_acc: &signer) {
        account::create_account_for_test(signer::address_of(source));
        resource_account::create_resource_account(source, vector::empty(), vector::empty());
        package_manager::init_module_test(resource_acc);
    }

    #[test(source = @0xcafe, resource_acc = @0xc3bb8488ab1a5815a9d543d7e41b0e0df46a7396f89b22821f07a4362f75ddc5)]
    public fun add_address_test(source: &signer, resource_acc: &signer) {
        setup(source, resource_acc);
        let test_identifier = string::utf8(b"test_address");
        let test_address = @0x123;
        package_manager::add_address_test(test_identifier, test_address);
        assert!(package_manager::address_exists(test_identifier), 1);
        let retrieved_address = package_manager::get_address(test_identifier);
        assert!(retrieved_address == test_address, 2);
    }

    #[test(source = @0xcafe, resource_acc = @0xc3bb8488ab1a5815a9d543d7e41b0e0df46a7396f89b22821f07a4362f75ddc5)]
    public fun test_address_exists(source: &signer, resource_acc: &signer) {
        setup(source, resource_acc);
        let test_identifier = string::utf8(b"test_address");
        let test_address = @0x123;
        package_manager::add_address_test(test_identifier, test_address);
        assert!(package_manager::address_exists(test_identifier), 3);
        assert!(!package_manager::address_exists(string::utf8(b"non_existent")), 4);
    }

    #[test(source = @0xcafe, resource_acc = @0xc3bb8488ab1a5815a9d543d7e41b0e0df46a7396f89b22821f07a4362f75ddc5)]
    public fun test_get_address(source: &signer, resource_acc: &signer) {
        setup(source, resource_acc);
        let test_identifier = string::utf8(b"test_address");
        let test_address = @0x123;
        package_manager::add_address_test(test_identifier, test_address);
        let retrieved_address = package_manager::get_address(test_identifier);
        assert!(retrieved_address == test_address, 5);
    }
    
    #[test(source = @0xcafe, resource_acc = @0xc3bb8488ab1a5815a9d543d7e41b0e0df46a7396f89b22821f07a4362f75ddc5)]
    public fun get_signer_test(source: &signer, resource_acc: &signer) {
        setup(source, resource_acc);
        let signer = package_manager::get_signer_test();
        let signer_address = signer::address_of(&signer);
        assert!(signer_address == @fullsail, 6);
    }
}