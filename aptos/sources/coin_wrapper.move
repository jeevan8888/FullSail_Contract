module fullsail::coin_wrapper {
    use aptos_framework::account::{Self, SignerCapability};
    use std::option;
    use std::coin::{Self, Coin};
    use aptos_framework::signer;
    use aptos_framework::aptos_account;
    use aptos_framework::fungible_asset::{Self, Metadata, BurnRef, MintRef, TransferRef, FungibleAsset};
    use aptos_framework::object::{Self, Object};
    use aptos_framework::primary_fungible_store;
    use aptos_framework::smart_table::{Self, SmartTable};
    use aptos_framework::string::{Self, String};
    use aptos_framework::string_utils;
    use aptos_framework::type_info;
    use fullsail::package_manager;

    // --- friends modules ---
    friend fullsail::vote_manager;
    friend fullsail::router;

    // --- structs ---
    struct FungibleAssetData has store {
        metadata: Object<Metadata>,
        burn_ref: BurnRef,
        mint_ref: MintRef,
        transfer_ref: TransferRef,
    }

    struct WrapperAccount has key {
        signer_cap: SignerCapability,
        coin_to_fungible_asset: SmartTable<String, FungibleAssetData>,
        fungible_asset_to_coin: SmartTable<Object<Metadata>, String>,
    }

    public(friend) fun create_fungible_asset<T0>() : Object<Metadata> acquires WrapperAccount {
        let wrapper_acc = borrow_global_mut<WrapperAccount>(wrapper_address());
        let coin_name = format_coin<T0>();
        let table = &mut wrapper_acc.coin_to_fungible_asset;

        if (!smart_table::contains<String, FungibleAssetData>(table, coin_name)) {
            let signer = account::create_signer_with_capability(&wrapper_acc.signer_cap);
            let object = object::create_named_object(&signer, *string::bytes(&coin_name));
            primary_fungible_store::create_primary_store_enabled_fungible_asset(
                &object,
                option::none<u128>(),
                coin::name<T0>(),
                coin::symbol<T0>(),
                coin::decimals<T0>(),
                string::utf8(b""),
                string::utf8(b"")
            );
            let metadata = object::object_from_constructor_ref<Metadata>(&object);
            let data = FungibleAssetData {
                metadata,
                burn_ref: fungible_asset::generate_burn_ref(&object),
                mint_ref: fungible_asset::generate_mint_ref(&object),
                transfer_ref: fungible_asset::generate_transfer_ref(&object),
            };
            smart_table::add<String, FungibleAssetData>(table, coin_name, data);
            smart_table::add<Object<Metadata>, String>(&mut wrapper_acc.fungible_asset_to_coin, metadata, coin_name);
        };
        smart_table::borrow<String, FungibleAssetData>(table, coin_name).metadata
    }

    public fun format_coin<T0>() : String {
        type_info::type_name<T0>()
    }

    public fun format_fungible_asset(identifier: Object<Metadata>) : String {
        let addr_str = string_utils::to_string<address>(&object::object_address<Metadata>(&identifier));
        string::sub_string(&addr_str, 1, string::length(&addr_str))
    }

    public fun get_coin_type(identifier: Object<Metadata>) : String acquires WrapperAccount {
        *smart_table::borrow<Object<Metadata>, String>(&borrow_global<WrapperAccount>(wrapper_address()).fungible_asset_to_coin, identifier)
    }

    public fun get_original(identifier: Object<Metadata>) : String acquires WrapperAccount {
        if (is_wrapper(identifier)) {
            get_coin_type(identifier)
        } else {
            format_fungible_asset(identifier)
        }
    }

    public fun get_wrapper<T0>() : Object<Metadata> acquires WrapperAccount {
        smart_table::borrow<String, FungibleAssetData>(
            &borrow_global<WrapperAccount>(wrapper_address()).coin_to_fungible_asset,
            type_info::type_name<T0>()
        ).metadata
    }

    public entry fun initialize() {
        if (is_initialized()) {
            return
        };
        let signer = fullsail::package_manager::get_signer();
        let (resource_account, signer_cap) = account::create_resource_account(&signer, b"COIN_WRAPPER");
        package_manager::add_address(string::utf8(b"COIN_WRAPPER"), signer::address_of(&resource_account));
        
        let wrapper_account = WrapperAccount {
            signer_cap,
            coin_to_fungible_asset: smart_table::new<String, FungibleAssetData>(),
            fungible_asset_to_coin: smart_table::new<Object<Metadata>, String>(),
        };
        move_to<WrapperAccount>(&resource_account, wrapper_account);
    }

    public fun is_initialized() : bool {
        package_manager::address_exists(string::utf8(b"COIN_WRAPPER"))
    }

    public fun is_supported<T0>() : bool acquires WrapperAccount {
        smart_table::contains<String, FungibleAssetData>(
            &borrow_global<WrapperAccount>(wrapper_address()).coin_to_fungible_asset,
            type_info::type_name<T0>()
        )
    }

    public fun is_wrapper(identifier: Object<Metadata>) : bool acquires WrapperAccount {
        smart_table::contains<Object<Metadata>, String>(
            &borrow_global<WrapperAccount>(wrapper_address()).fungible_asset_to_coin,
            identifier
        )
    }

    public(friend) fun unwrap<T0>(asset: FungibleAsset) : Coin<T0> acquires WrapperAccount {
        let amount_to_burn = fungible_asset::amount(&asset);
        fungible_asset::burn(
            &smart_table::borrow<String, FungibleAssetData>(
                &borrow_global<WrapperAccount>(wrapper_address()).coin_to_fungible_asset,
                type_info::type_name<T0>()
            ).burn_ref,
            asset
        );
        let signer = account::create_signer_with_capability(&borrow_global<WrapperAccount>(wrapper_address()).signer_cap);
        coin::withdraw<T0>(&signer, amount_to_burn)
    }

    public(friend) fun wrap<T0>(coin: Coin<T0>) : FungibleAsset acquires WrapperAccount {
        create_fungible_asset<T0>();
        let value_of_coin = coin::value<T0>(&coin);
        aptos_account::deposit_coins<T0>(wrapper_address(), coin);
        fungible_asset::mint(
            &smart_table::borrow<String, FungibleAssetData>(
                &borrow_global<WrapperAccount>(wrapper_address()).coin_to_fungible_asset,
                type_info::type_name<T0>()
            ).mint_ref,
            value_of_coin
        )
    }

    public fun wrapper_address() : address {
        package_manager::get_address(string::utf8(b"COIN_WRAPPER"))
    }

    #[test_only]
    public fun create_fungible_asset_test<T0>() : Object<Metadata> acquires WrapperAccount {
        create_fungible_asset<T0>()
    }

    #[test_only]
    public fun wrap_test<T0>(coin: Coin<T0>) : FungibleAsset acquires WrapperAccount {
        wrap<T0>(coin)
    }

    #[test_only]
    public fun unwrap_test<T0>(asset: FungibleAsset) : Coin<T0> acquires WrapperAccount {
        unwrap<T0>(asset)
    }
}
