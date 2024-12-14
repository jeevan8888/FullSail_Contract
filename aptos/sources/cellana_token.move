module fullsail::cellana_token {
    use std::string;
    use std::option::{Self};
    use aptos_framework::object::{Self, Object};
    use aptos_framework::fungible_asset::{Self, BurnRef, MintRef, TransferRef, FungibleAsset, FungibleStore};
    use aptos_framework::primary_fungible_store;
    use aptos_framework::signer;

    // --- friends modules ---
    friend fullsail::voting_escrow;
    friend fullsail::minter;
    friend fullsail::vote_manager;

    // --- structs ---
    struct CellanaToken has key {
        burn_ref: BurnRef,
        mint_ref: MintRef,
        transfer_ref: TransferRef,
    }
    
    // init
    public entry fun initialize() {
        if (is_initialized()) {
            return
        };

        let signer = fullsail::package_manager::get_signer();
        let token_object = object::create_named_object(&signer, b"CELLANA");
        let token_object_ref = &token_object;

        primary_fungible_store::create_primary_store_enabled_fungible_asset(
            token_object_ref, option::none<u128>(), 
            string::utf8(b"CELLANA"), string::utf8(b"CELL"), 
            8, 
            string::utf8(b"CELLANA"), 
            string::utf8(b"https://cellana.finance/")
        );

        let token_signer = object::generate_signer(token_object_ref);
        let token_signer_ref = &token_signer;
        let cellana_token = CellanaToken{
            burn_ref     : fungible_asset::generate_burn_ref(token_object_ref),
            mint_ref     : fungible_asset::generate_mint_ref(token_object_ref),
            transfer_ref : fungible_asset::generate_transfer_ref(token_object_ref),
        };
        move_to<CellanaToken>(token_signer_ref, cellana_token);
        fullsail::package_manager::add_address(string::utf8(b"CELLANA"), signer::address_of(token_signer_ref));
    }

    public fun is_initialized() : bool {
        fullsail::package_manager::address_exists(string::utf8(b"CELLANA"))
    }
    public(friend) fun burn(token: FungibleAsset) acquires CellanaToken {
        fungible_asset::burn(&borrow_global<CellanaToken>(token_address()).burn_ref, token);
    }

    public(friend) fun mint(amount: u64): FungibleAsset acquires CellanaToken {
        fungible_asset::mint(&borrow_global<CellanaToken>(token_address()).mint_ref, amount)
    }

    public fun balance(addr: address) : u64 {
        primary_fungible_store::balance<CellanaToken>(addr, token())
    }

    public(friend) fun deposit<T: key>(object: Object<T>, asset: FungibleAsset) acquires CellanaToken {
        fungible_asset::deposit_with_ref<T>(&borrow_global<CellanaToken>(token_address()).transfer_ref, object, asset);
    }

    public(friend) fun disable_transfer<T: key>(object: Object<T>) acquires CellanaToken {
        fungible_asset::set_frozen_flag<T>(&borrow_global<CellanaToken>(token_address()).transfer_ref, object, true);
    }

    public fun token() : Object<CellanaToken> {
        object::address_to_object<CellanaToken>(token_address())
    }

    public fun token_address() : address {
        fullsail::package_manager::get_address(string::utf8(b"CELLANA"))
    }

    public fun total_supply() : u128 {
        let supply = fungible_asset::supply<CellanaToken>(token());
        option::get_with_default<u128>(&supply, 0)
    }

    public(friend) fun transfer<T: key>(from: Object<T>, to: Object<FungibleStore>, amount: u64) acquires CellanaToken {
        fungible_asset::transfer_with_ref<FungibleStore>(
            &borrow_global<CellanaToken>(token_address()).transfer_ref, 
            object::convert<T, FungibleStore>(from), 
            to, 
            amount
        );
    }

    public(friend) fun withdraw<T: key>(object: Object<T>, amount: u64) : FungibleAsset acquires CellanaToken {
        fungible_asset::withdraw_with_ref<T>(
            &borrow_global<CellanaToken>(token_address()).transfer_ref,
            object, 
            amount
        )
    }

    #[test_only]
    public fun burn_test(token: FungibleAsset) acquires CellanaToken {
        burn(token);
    }

    #[test_only]
    public fun mint_test(amount: u64) : FungibleAsset acquires CellanaToken {
        let tokenAsset = mint(amount);
        tokenAsset
    }
    
    #[test_only]
    public fun initialize_test() {
        initialize();
    }

    #[test_only]
    public fun transfer_test<T: key>(from: Object<T>, to: Object<FungibleStore>, amount: u64) acquires CellanaToken {
        transfer(from, to, amount);
    }

    #[test_only]
    public fun balance_test(addr: address): u64 {
        balance(addr)
    }

    #[test_only]
    public fun deposit_test<T: key>(object: Object<T>, asset: FungibleAsset) acquires CellanaToken {
        deposit(object, asset)
    }
}

