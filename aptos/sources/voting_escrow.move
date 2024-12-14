module fullsail::voting_escrow {
    use std::string;
    use std::vector;
    use std::option;
    use std::error;
    use aptos_std::math64;
    use aptos_std::string_utils;
    use aptos_std::smart_vector::{Self, SmartVector};
    use aptos_std::smart_table::{Self, SmartTable};
    use aptos_token_objects::collection;
    use aptos_token_objects::royalty;
    use aptos_token_objects::token::{Self, BurnRef};
    use aptos_framework::object::{Self, Object, DeleteRef, TransferRef};
    use aptos_framework::fungible_asset::{Self, FungibleAsset, FungibleStore};
    use aptos_framework::dispatchable_fungible_asset;
    use aptos_framework::primary_fungible_store;
    use aptos_framework::event;
    use aptos_framework::signer;
    use fullsail::cellana_token::{Self, CellanaToken};
    use fullsail::epoch;

    // --- friends modules ---
    friend fullsail::vote_manager;

    // --- errors ---
    const E_INSUFFICIENT_BALANCE: u64 = 1;
    const E_MIN_LOCK_TIME: u64 = 2;
    const E_MAX_LOCK_TIME: u64 = 3;
    const E_NOT_OWNER: u64 = 4;
    const E_LOCK_NOT_EXPIRED: u64 = 5;
    const E_INVALID_UPDATE: u64 = 6;
    const E_LOCK_EXTENSION_TOO_SHORT: u64 = 7;
    const E_ZERO_AMOUNT: u64 = 8;
    const E_NO_SNAPSHOT: u64 = 9;
    const E_LOCK_EXPIRED: u64 = 10;
    const E_INVALID_EPOCH: u64 = 11;
    const E_INVALID_SPLIT_AMOUNT: u64 = 12;
    const E_PENDING_REBASE: u64 = 13;
    const E_ZERO_TOTAL_POWER: u64 = 14;
    const E_EPOCH_NOT_ENDED: u64 = 15;
    const E_LOCK_DURATION_TOO_SHORT: u64 = 16;
    const E_LOCK_DURATION_TOO_LONG: u64 = 17;
    const E_INVALID_TOKEN: u64 = 18;
    const E_INVALID_EXTENSION: u64 = 19;
    const E_NO_SNAPSHOT_FOUND: u64 = 20;
    const E_INVALID_SPLIT_AMOUNTS: u64 = 21;
    const E_SMART_TABLE_ENTRY_NOT_FOUND: u64 = 22;
    const ERROR_INVALID_UPDATE: u64 = 23;

    // --- structs ---

    struct TokenSnapshot has drop, store {
        epoch: u64,
        locked_amount: u64,
        end_epoch: u64,
    }

    struct VeCellanaCollection has key {
        unscaled_total_voting_power_per_epoch: SmartTable<u64, u128>,
        rebases: SmartTable<u64, u64>,
    }

    struct VeCellanaDeleteRef has key {
        delete_ref: DeleteRef,
    }

    struct VeCellanaToken has key {
        locked_amount: u64,
        end_epoch: u64,
        snapshots: SmartVector<TokenSnapshot>,
        next_rebase_epoch: u64,
    }

    struct VeCellanaTokenRefs has key {
        burn_ref: BurnRef,
        transfer_ref: TransferRef,
    }

    // --- events ---
    #[event]
    struct CreateLockEvent has drop, store {
        owner: address,
        amount: u64,
        lockup_end_epoch: u64,
        ve_token: Object<VeCellanaToken>,
    }

    #[event]
    struct ExtendLockupEvent has drop, store {
        owner: address,
        old_lockup_end_epoch: u64,
        new_lockup_end_epoch: u64,
        ve_token: Object<VeCellanaToken>,
    }

    #[event]
    struct IncreaseAmountEvent has drop, store {
        owner: address,
        old_amount: u64,
        new_amount: u64,
        ve_token: Object<VeCellanaToken>,
    }

    #[event]
    struct WithdrawEvent has drop, store {
        owner: address,
        amount: u64,
        ve_token: Object<VeCellanaToken>,
    }

    // init
    public entry fun initialize() {
        if (is_initialized()) {
            return
        };

        fullsail::cellana_token::initialize();

        let collection = VeCellanaCollection{
            unscaled_total_voting_power_per_epoch : smart_table::new<u64, u128>(),
            rebases : smart_table::new<u64, u64>(),
        };

        let signer = fullsail::package_manager::get_signer();
        let collection_object = collection::create_unlimited_collection(
            &signer, 
            string::utf8(b"Cellana Voting Tokens"), 
            string::utf8(b"Cellana Voting Tokens"), 
            option::none<royalty::Royalty>(), 
            string::utf8(b"https://api.cellana.finance/api/v1/ve-nft/uri/")
        );

        fungible_asset::create_store<CellanaToken>(&collection_object, cellana_token::token());

        let collection_signer = object::generate_signer(&collection_object);
        move_to<VeCellanaCollection>(&collection_signer, collection);
        fullsail::package_manager::add_address(string::utf8(b"Cellana Voting Tokens"), signer::address_of(&collection_signer));
    }

    public fun is_initialized() : bool {
        fullsail::package_manager::address_exists(string::utf8(b"Cellana Voting Tokens"))
    }

    public fun withdraw(account: &signer, ve_token: Object<VeCellanaToken>) : FungibleAsset acquires VeCellanaCollection, VeCellanaDeleteRef, VeCellanaToken, VeCellanaTokenRefs {
        let claimable = claimable_rebase(ve_token);
        assert!(claimable == 0, E_PENDING_REBASE);

        let assets = fullsail::cellana_token::withdraw<VeCellanaToken>(ve_token, fungible_asset::balance<VeCellanaToken>(ve_token));
        assert!(object::is_owner<VeCellanaToken>(ve_token, signer::address_of(account)), E_NOT_OWNER);

        let token_addr = object::object_address<VeCellanaToken>(&ve_token);
        if (exists<VeCellanaDeleteRef>(token_addr)) {
            let VeCellanaDeleteRef { delete_ref } = move_from<VeCellanaDeleteRef>(token_addr);
            fungible_asset::remove_store(&delete_ref);
        };

        let VeCellanaTokenRefs {
            burn_ref,
            transfer_ref: _,
        } = move_from<VeCellanaTokenRefs>(token_addr);

        token::burn(burn_ref);

        let VeCellanaToken {
            locked_amount: _,
            end_epoch,
            snapshots,
            next_rebase_epoch: _,
        } = move_from<VeCellanaToken>(token_addr);

        destroy_snapshots(snapshots);
        
        event::emit<WithdrawEvent>(WithdrawEvent {
            owner: signer::address_of(account),
            amount: fungible_asset::amount(&assets),
            ve_token,
        });

        assert!(end_epoch <= epoch::now(), E_EPOCH_NOT_ENDED);
        assets
    }

    public(friend) fun add_rebase(assets: FungibleAsset, epoch_number: u64) acquires VeCellanaCollection {
        assert!(epoch_number < epoch::now(), E_INVALID_EPOCH);

        let amount = fungible_asset::amount(&assets);
        assert!(amount > 0, E_ZERO_AMOUNT);

        smart_table::add(
            &mut borrow_global_mut<VeCellanaCollection>(voting_escrow_collection()).rebases, 
            epoch_number, 
            amount
        );
        dispatchable_fungible_asset::deposit<FungibleStore>(object::address_to_object<FungibleStore>(voting_escrow_collection()), assets);
    }

    public entry fun claim_rebase(account: &signer, ve_token: Object<VeCellanaToken>) acquires VeCellanaCollection, VeCellanaToken {
        assert!(object::is_owner<VeCellanaToken>(ve_token, signer::address_of(account)), E_NOT_OWNER);

        let claimable = claimable_rebase_internal(ve_token);
        if (claimable > 0) {
            increase_amount_rebase(
                ve_token, 
                fullsail::cellana_token::withdraw<FungibleStore>(object::address_to_object<FungibleStore>(voting_escrow_collection()), claimable)
            );
            borrow_global_mut<VeCellanaToken>(object::object_address<VeCellanaToken>(&ve_token)).next_rebase_epoch = epoch::now();
        };
    }

    public fun claimable_rebase(ve_token: Object<VeCellanaToken>) : u64 acquires VeCellanaCollection, VeCellanaToken {
        claimable_rebase_internal(ve_token)
    }

    fun claimable_rebase_internal(ve_token: Object<VeCellanaToken>) : u64 acquires VeCellanaCollection, VeCellanaToken {
        let collection = borrow_global<VeCellanaCollection>(voting_escrow_collection());
        let next_rebase_epoch = borrow_global<VeCellanaToken>(object::object_address<VeCellanaToken>(&ve_token)).next_rebase_epoch;
        let total_claimable: u128 = 0;

        while (next_rebase_epoch < epoch::now()) {
            let default_rebase: u64 = 0;
            let epoch_rebase = (*smart_table::borrow_with_default<u64, u64>(&collection.rebases, next_rebase_epoch, &default_rebase) as u128);

            if (epoch_rebase > 0) {
                let user_voting_power = get_voting_power_at_epoch(ve_token, next_rebase_epoch);
                let total_voting_power_table = &collection.unscaled_total_voting_power_per_epoch;
                
                let total_voting_power = if (!smart_table::contains<u64, u128>(total_voting_power_table, next_rebase_epoch)) {
                    0
                } else {
                    *smart_table::borrow<u64, u128>(total_voting_power_table, next_rebase_epoch) / (104 as u128)
                };

                assert!(total_voting_power != 0, error::invalid_argument(E_ZERO_TOTAL_POWER));
                total_claimable = total_claimable + ((((user_voting_power as u128) as u256) * (epoch_rebase as u256) / (total_voting_power as u256)) as u128);
            };

            next_rebase_epoch = next_rebase_epoch + 1;
        };
        (total_claimable as u64)
    }

    public fun create_lock(account: &signer, amount: u64, lock_duration: u64) : Object<VeCellanaToken> acquires VeCellanaCollection {
        create_lock_with(primary_fungible_store::withdraw<CellanaToken>(
                account, 
                fullsail::cellana_token::token(),
                amount
            ), 
            lock_duration, 
            signer::address_of(account)
        )
    }

    public entry fun create_lock_entry(account: &signer, amount: u64, lock_duration: u64) acquires VeCellanaCollection {
        create_lock(account, amount, lock_duration);
    }

    public entry fun create_lock_for(account: &signer, amount: u64, lock_duration: u64, recipient: address) acquires VeCellanaCollection {
        create_lock_with(primary_fungible_store::withdraw<CellanaToken>(
                account, 
                fullsail::cellana_token::token(), 
                amount
            ), 
            lock_duration, 
            recipient
        );
    }

    public fun create_lock_with(tokens: FungibleAsset, lock_duration: u64, owner: address) : Object<VeCellanaToken> acquires VeCellanaCollection {
        let amount = fungible_asset::amount(&tokens);
        assert!(amount > 0, E_ZERO_AMOUNT);
        assert!(lock_duration >= 2, E_LOCK_DURATION_TOO_SHORT);
        assert!(lock_duration <= 104, E_LOCK_DURATION_TOO_LONG);

        let token_obj = fullsail::cellana_token::token();
        assert!(fungible_asset::asset_metadata(&tokens) == object::convert<fullsail::cellana_token::CellanaToken, fungible_asset::Metadata>(token_obj), E_INVALID_TOKEN);
        
        let signer = fullsail::package_manager::get_signer();
        let constructor_ref = &token::create_from_account(
            &signer, 
            string::utf8(b"Cellana Voting Tokens"), 
            string::utf8(b"NFT representing voting power in Cellana corresponding to $CELL locked up"), 
            string::utf8(b"veCELL"), 
            option::none<royalty::Royalty>(), 
            string::utf8(b"https://api.cellana.finance/api/v1/ve-nft/uri/")
        );
        let token_signer = object::generate_signer(constructor_ref);
        let end_epoch = epoch::now() + lock_duration;
        let ve_token = VeCellanaToken{
            locked_amount: amount,
            end_epoch,
            snapshots: smart_vector::new<TokenSnapshot>(),
            next_rebase_epoch: epoch::now(),
        };
        update_snapshots(&mut ve_token, amount, end_epoch);
        move_to<VeCellanaToken>(&token_signer, ve_token);

        let token_refs = VeCellanaTokenRefs{
            burn_ref: token::generate_burn_ref(constructor_ref),
            transfer_ref: object::generate_transfer_ref(constructor_ref),
        };
        move_to<VeCellanaTokenRefs>(&token_signer, token_refs);

        let delete_ref = VeCellanaDeleteRef{delete_ref: object::generate_delete_ref(constructor_ref)};
        move_to<VeCellanaDeleteRef>(&token_signer, delete_ref);

        let store = fungible_asset::create_store<CellanaToken>(constructor_ref, token_obj);
        dispatchable_fungible_asset::deposit<FungibleStore>(store, tokens);
        fullsail::cellana_token::disable_transfer<FungibleStore>(store);
        object::transfer<FungibleStore>(&signer, store, owner);

        let mutator_ref = token::generate_mutator_ref(constructor_ref);
        let ve_token_obj = object::object_from_constructor_ref<VeCellanaToken>(constructor_ref);
        let uri = string::utf8(b"https://api.cellana.finance/api/v1/ve-nft/uri/");

        string::append(&mut uri, string_utils::to_string<address>(&object::object_address<VeCellanaToken>(&ve_token_obj)));
        token::set_uri(&mutator_ref, uri);

        event::emit<CreateLockEvent>(CreateLockEvent {
            owner,
            amount,
            lockup_end_epoch: end_epoch,
            ve_token: ve_token_obj,
        });

        update_manifested_total_supply(0, 0, amount, end_epoch);
        ve_token_obj
    }

    fun destroy_snapshots(snapshots: SmartVector<TokenSnapshot>) {
        let i = 0;
        while (i < smart_vector::length(&snapshots)) {
            smart_vector::pop_back(&mut snapshots);
            i = i + 1;
        };
        smart_vector::destroy_empty(snapshots);
    }

    public entry fun extend_lockup(account: &signer, ve_token: Object<VeCellanaToken>, extension_duration: u64) acquires VeCellanaCollection, VeCellanaToken {
        assert!(extension_duration >= 2, E_LOCK_DURATION_TOO_SHORT);
        assert!(extension_duration <= 104, E_LOCK_DURATION_TOO_SHORT);
        assert!(object::is_owner<VeCellanaToken>(ve_token, signer::address_of(account)), E_NOT_OWNER);
        
        let token_data = borrow_global_mut<VeCellanaToken>(object::object_address<VeCellanaToken>(&ve_token));
        let old_end_epoch = token_data.end_epoch;
        let new_end_epoch = epoch::now() + extension_duration;
        
        assert!(new_end_epoch > old_end_epoch, E_INVALID_EXTENSION);

        token_data.end_epoch = new_end_epoch;
        let locked_amount = token_data.locked_amount;

        event::emit<ExtendLockupEvent>(ExtendLockupEvent {
            owner: signer::address_of(account),
            old_lockup_end_epoch: old_end_epoch,
            new_lockup_end_epoch: new_end_epoch,
            ve_token,
        });

        update_snapshots(token_data, locked_amount, new_end_epoch);
        update_manifested_total_supply(locked_amount, old_end_epoch, locked_amount, new_end_epoch);
    }

    public(friend) fun freeze_token(ve_token: Object<VeCellanaToken>) acquires VeCellanaTokenRefs {
        let token_refs = borrow_global<VeCellanaTokenRefs>(object::object_address(&ve_token));
        object::disable_ungated_transfer(&token_refs.transfer_ref);
    }

    public fun get_lockup_expiration_epoch(ve_token: Object<VeCellanaToken>) : u64 acquires VeCellanaToken {
        borrow_global<VeCellanaToken>(object::object_address<VeCellanaToken>(&ve_token)).end_epoch
    }

    public fun get_lockup_expiration_time(ve_token: Object<VeCellanaToken>) : u64 acquires VeCellanaToken {
        let expiration_epoch = get_lockup_expiration_epoch(ve_token);
        expiration_epoch * 604800
    }

    public fun get_voting_power(ve_token: Object<VeCellanaToken>) : u64 acquires VeCellanaToken {
        get_voting_power_at_epoch(ve_token, epoch::now())
    }

    public fun get_voting_power_at_epoch(ve_token: Object<VeCellanaToken>, target_epoch: u64) : u64 acquires VeCellanaToken {
        let token_data = borrow_global<VeCellanaToken>(object::object_address(&ve_token));
        let (locked_amount, end_epoch) = if (target_epoch == epoch::now()) {
            (token_data.locked_amount, token_data.end_epoch)
        } else {
            let snapshots = &token_data.snapshots;
            let snapshot_index = smart_vector::length(snapshots);
            while (snapshot_index > 0 && smart_vector::borrow(snapshots, snapshot_index - 1).epoch > target_epoch) {
                snapshot_index = snapshot_index - 1;
            };
            assert!(snapshot_index > 0, E_NO_SNAPSHOT_FOUND);
            let snapshot = smart_vector::borrow(snapshots, snapshot_index - 1);
            (snapshot.locked_amount, snapshot.end_epoch)
        };
        if (end_epoch <= target_epoch) {
            0
        } else {
            locked_amount * (end_epoch - target_epoch) / 104
        }
    }

    public fun increase_amount(account: &signer, ve_token: Object<VeCellanaToken>, additional_tokens: FungibleAsset) acquires VeCellanaCollection, VeCellanaToken {
        assert!(object::is_owner(ve_token, signer::address_of(account)), E_NOT_OWNER);
        increase_amount_internal(ve_token, additional_tokens);
    }

    public entry fun increase_amount_entry(account: &signer, ve_token: Object<VeCellanaToken>, amount: u64) acquires VeCellanaCollection, VeCellanaToken {
        increase_amount(account, ve_token, primary_fungible_store::withdraw<CellanaToken>(account, fullsail::cellana_token::token(), amount));
    }

    fun increase_amount_internal(ve_token: Object<VeCellanaToken>, additional_tokens: FungibleAsset) acquires VeCellanaCollection, VeCellanaToken {
        let token_data = borrow_global_mut<VeCellanaToken>(object::object_address(&ve_token));
        assert!(token_data.end_epoch > epoch::now(), E_LOCK_EXPIRED);

        let additional_amount = fungible_asset::amount(&additional_tokens);
        assert!(additional_amount > 0, E_ZERO_AMOUNT);

        let old_amount = token_data.locked_amount;
        let new_amount = old_amount + additional_amount;

        token_data.locked_amount = new_amount;

        fullsail::cellana_token::deposit<VeCellanaToken>(ve_token, additional_tokens);

        let owner = object::owner<VeCellanaToken>(ve_token);

        event::emit<IncreaseAmountEvent>(IncreaseAmountEvent {
            owner,
            old_amount,
            new_amount,
            ve_token,
        });

        let end_epoch = token_data.end_epoch;
        update_snapshots(token_data, new_amount, end_epoch);
        update_manifested_total_supply(old_amount, end_epoch, new_amount, end_epoch);
    }

    fun increase_amount_rebase(ve_token: Object<VeCellanaToken>, rebase_tokens: FungibleAsset) acquires VeCellanaCollection, VeCellanaToken {
        let token_data = borrow_global_mut<VeCellanaToken>(object::object_address(&ve_token));
        
        let rebase_amount = fungible_asset::amount(&rebase_tokens);
        assert!(rebase_amount > 0, E_ZERO_AMOUNT);

        let old_amount = token_data.locked_amount;
        let new_amount = old_amount + rebase_amount;
        token_data.locked_amount = new_amount;

        fullsail::cellana_token::deposit<VeCellanaToken>(ve_token, rebase_tokens);
        
        let owner = object::owner<VeCellanaToken>(ve_token);

        event::emit<IncreaseAmountEvent>(IncreaseAmountEvent {
            owner,
            old_amount,
            new_amount,
            ve_token,
        });

        let end_epoch = token_data.end_epoch;
        update_snapshots(token_data, new_amount, end_epoch);
        update_manifested_total_supply(old_amount, end_epoch, new_amount, end_epoch);
    }

    public fun locked_amount(ve_token: Object<VeCellanaToken>) : u64 acquires VeCellanaToken {
        borrow_global<VeCellanaToken>(object::object_address(&ve_token)).locked_amount
    }

    public fun max_lockup_epochs() : u64 {
        104
    }

    public entry fun merge(_account: &signer, _ve_token1: Object<VeCellanaToken>, _ve_token2: Object<VeCellanaToken>) {
        abort 0
    }

    public(friend) fun merge_ve_nft(account: &signer, source_token: Object<VeCellanaToken>, target_token: Object<VeCellanaToken>) acquires VeCellanaCollection, VeCellanaDeleteRef, VeCellanaToken, VeCellanaTokenRefs {
        let source_rebase = claimable_rebase(source_token);
        let target_rebase = claimable_rebase(target_token);
        assert!(source_rebase == 0 && target_rebase == 0, E_PENDING_REBASE);

        let transfer_amount = fungible_asset::balance<VeCellanaToken>(source_token);
        fullsail::cellana_token::transfer<VeCellanaToken>(
            source_token, 
            object::convert<VeCellanaToken, FungibleStore>(target_token), 
            transfer_amount
        );
        
        assert!(object::is_owner(source_token, signer::address_of(account)), E_NOT_OWNER);
        let source_addr = object::object_address(&source_token);

        if (exists<VeCellanaDeleteRef>(source_addr)) {
            let VeCellanaDeleteRef { delete_ref } = move_from<VeCellanaDeleteRef>(source_addr);
            fungible_asset::remove_store(&delete_ref);
        };

        let VeCellanaTokenRefs {
            burn_ref,
            transfer_ref: _,
        } = move_from<VeCellanaTokenRefs>(source_addr);
        token::burn(burn_ref);

        let VeCellanaToken {
            locked_amount: _,
            end_epoch: source_end_epoch,
            snapshots: source_snapshots,
            next_rebase_epoch: _,
        } = move_from<VeCellanaToken>(source_addr);

        destroy_snapshots(source_snapshots);

        assert!(object::is_owner(target_token, signer::address_of(account)), E_NOT_OWNER);
        let target_data = borrow_global_mut<VeCellanaToken>(object::object_address(&target_token));
        
        let old_amount = target_data.locked_amount;
        let new_amount = transfer_amount + old_amount;
        target_data.locked_amount = new_amount;

        event::emit<IncreaseAmountEvent>(IncreaseAmountEvent {
            owner: signer::address_of(account),
            old_amount,
            new_amount,
            ve_token: target_token,
        });

        let target_end_epoch = target_data.end_epoch;
        if (source_end_epoch > target_end_epoch) {
            target_data.end_epoch = source_end_epoch;
            update_snapshots(target_data, new_amount, source_end_epoch);
            update_manifested_total_supply(old_amount, target_end_epoch, old_amount, source_end_epoch);
        } else {
            update_snapshots(target_data, new_amount, target_end_epoch);
            if (source_end_epoch != target_end_epoch) {
                update_manifested_total_supply(transfer_amount, source_end_epoch, transfer_amount, target_end_epoch);
            };
        };
    }

    public fun nft_exists(addr: address) : bool {
        exists<VeCellanaToken>(addr)
    }

    public fun remaining_lockup_epochs(ve_token: Object<VeCellanaToken>) : u64 acquires VeCellanaToken {
        let expiration_epoch = get_lockup_expiration_epoch(ve_token);
        let current_epoch = epoch::now();
        if (expiration_epoch <= current_epoch) {
            0
        } else {
            expiration_epoch - current_epoch
        }
    }

    public fun split(_account: &signer, _ve_token: Object<VeCellanaToken>, _split_amounts: vector<u64>) : vector<Object<VeCellanaToken>> {
        abort 0
    }

    public entry fun split_entry(_account: &signer, _ve_token: Object<VeCellanaToken>, _split_amounts: vector<u64>) {
        abort 0
    }

    public(friend) fun split_ve_nft(account: &signer, ve_token: Object<VeCellanaToken>, split_amounts: vector<u64>) : vector<Object<VeCellanaToken>> acquires VeCellanaCollection, VeCellanaDeleteRef, VeCellanaToken, VeCellanaTokenRefs {
        assert!(object::is_owner(ve_token, signer::address_of(account)), E_NOT_OWNER);
        
        let claimable = claimable_rebase(ve_token);
        assert!(claimable == 0, E_PENDING_REBASE);

        let total_split_amount = 0;
        vector::reverse(&mut split_amounts);
        let split_amounts_length = vector::length<u64>(&split_amounts);
        while (split_amounts_length > 0) {
            total_split_amount = total_split_amount + vector::pop_back(&mut split_amounts);
            split_amounts_length = split_amounts_length - 1;
        };
        vector::destroy_empty(split_amounts);
        assert!(total_split_amount == fungible_asset::balance<VeCellanaToken>(ve_token), E_INVALID_SPLIT_AMOUNTS);
        
        let tokens = fullsail::cellana_token::withdraw<VeCellanaToken>(ve_token, fungible_asset::balance<VeCellanaToken>(ve_token));
        assert!(object::is_owner<VeCellanaToken>(ve_token, signer::address_of(account)), E_NOT_OWNER);
        
        let token_address = object::object_address<VeCellanaToken>(&ve_token);
        if (exists<VeCellanaDeleteRef>(token_address)) {
            let VeCellanaDeleteRef { delete_ref } = move_from<VeCellanaDeleteRef>(token_address);
            fungible_asset::remove_store(&delete_ref);
        };

        let VeCellanaTokenRefs {
            burn_ref,
            transfer_ref: _,
        } = move_from<VeCellanaTokenRefs>(token_address);
        token::burn(burn_ref);

        let VeCellanaToken {
            locked_amount,
            end_epoch,
            snapshots,
            next_rebase_epoch : _,
        } = move_from<VeCellanaToken>(token_address);

        let current_epoch = epoch::now();
        while (current_epoch < end_epoch) {
            let manifested_supply = &mut borrow_global_mut<VeCellanaCollection>(voting_escrow_collection()).unscaled_total_voting_power_per_epoch;
            assert!(smart_table::contains(manifested_supply, current_epoch), E_SMART_TABLE_ENTRY_NOT_FOUND);
            let supply = smart_table::borrow_mut(manifested_supply, current_epoch);
            *supply = *supply - ((locked_amount * (end_epoch - math64::min(current_epoch, end_epoch))) as u128);
            current_epoch = current_epoch + 1;
        };

        destroy_snapshots(snapshots);

        let remaining_lockup = end_epoch - epoch::now();
        let new_ve_tokens = vector::empty<Object<VeCellanaToken>>();
        vector::reverse(&mut split_amounts);

        let split_amounts_length = vector::length(&split_amounts);
        while (split_amounts_length > 0) {
            let split_amount = vector::pop_back(&mut split_amounts);
            if (fungible_asset::amount(&tokens) > split_amount) {
                let new_ve_token = create_lock_with(fungible_asset::extract(&mut tokens, split_amount), remaining_lockup, signer::address_of(account));
                let new_token_data = borrow_global_mut<VeCellanaToken>(object::object_address<VeCellanaToken>(&new_ve_token));
                update_snapshots(new_token_data, split_amount, end_epoch);
                vector::push_back(&mut new_ve_tokens, new_ve_token);
            };
            split_amounts_length = split_amounts_length - 1;
        };

        vector::destroy_empty(split_amounts);

        let final_ve_token = create_lock_with(tokens, remaining_lockup, signer::address_of(account));
        vector::push_back(&mut new_ve_tokens, final_ve_token);
        new_ve_tokens
    }

    public fun total_voting_power() : u128 acquires VeCellanaCollection {
        total_voting_power_at(epoch::now())
    }

    public fun total_voting_power_at(target_epoch: u64) : u128 acquires VeCellanaCollection {
        let voting_power_table = &borrow_global<VeCellanaCollection>(voting_escrow_collection()).unscaled_total_voting_power_per_epoch;
        if (!smart_table::contains(voting_power_table, target_epoch)) {
            0
        } else {
            *smart_table::borrow(voting_power_table, target_epoch) / (104 as u128)
        }
    }

    public(friend) fun unfreeze_token(ve_token: Object<VeCellanaToken>) acquires VeCellanaTokenRefs {
        let token_refs = borrow_global<VeCellanaTokenRefs>(object::object_address(&ve_token));
        object::enable_ungated_transfer(&token_refs.transfer_ref);
    }

    fun update_manifested_total_supply(old_amount: u64, old_end_epoch: u64, new_amount: u64, new_end_epoch: u64) acquires VeCellanaCollection {
        assert!(new_amount > old_amount || new_end_epoch > old_end_epoch, E_INVALID_UPDATE);
        
        let current_epoch = epoch::now();
        let manifested_supply = &mut borrow_global_mut<VeCellanaCollection>(voting_escrow_collection()).unscaled_total_voting_power_per_epoch;
        
        while (current_epoch < new_end_epoch) {
            let old_value = if (old_amount == 0 || old_end_epoch <= current_epoch) {
                0
            } else {
                old_amount * (old_end_epoch - current_epoch)
            };
            if (smart_table::contains(manifested_supply, current_epoch)) {
                let supply = smart_table::borrow_mut<u64, u128>(manifested_supply, current_epoch);
                *supply = *supply + ((new_amount * (new_end_epoch - current_epoch) - old_value) as u128);
            } else {
                smart_table::add(manifested_supply, current_epoch, ((new_amount * (new_end_epoch - current_epoch) - old_value) as u128));
            };
            current_epoch = current_epoch + 1;
        };
    }

    fun update_snapshots(token: &mut VeCellanaToken, locked_amount: u64, end_epoch: u64) {
        let snapshots = &mut token.snapshots;
        let current_epoch = epoch::now();
        let snapshot_count = smart_vector::length(snapshots);

        if (snapshot_count == 0 || smart_vector::borrow(snapshots, snapshot_count - 1).epoch < current_epoch) {
            let new_snapshot = TokenSnapshot{
                epoch: current_epoch,
                locked_amount : locked_amount,
                end_epoch : end_epoch,
            };
            smart_vector::push_back(snapshots, new_snapshot);
        } else {
            let last_snapshot = smart_vector::borrow_mut(snapshots, snapshot_count - 1);
            last_snapshot.locked_amount = locked_amount;
            last_snapshot.end_epoch = end_epoch;
        };
    }

    public fun voting_escrow_collection() : address {
        fullsail::package_manager::get_address(string::utf8(b"Cellana Voting Tokens"))
    }

    public entry fun withdraw_entry(account: &signer, ve_token: Object<VeCellanaToken>) acquires VeCellanaCollection, VeCellanaDeleteRef, VeCellanaToken, VeCellanaTokenRefs {
        let withdrawn_tokens = withdraw(account, ve_token);
        primary_fungible_store::deposit(signer::address_of(account), withdrawn_tokens);
    }

    #[test_only]
    public fun merge_ve_nft_test(account: &signer, source_token: Object<VeCellanaToken>, target_token: Object<VeCellanaToken>) acquires VeCellanaCollection, VeCellanaDeleteRef, VeCellanaToken, VeCellanaTokenRefs {
        merge_ve_nft(account, source_token, target_token);
    }

    #[test_only]
    public fun split_ve_nft_test(account: &signer, ve_token: Object<VeCellanaToken>, split_amounts: vector<u64>) : vector<Object<VeCellanaToken>> acquires VeCellanaCollection, VeCellanaDeleteRef, VeCellanaToken, VeCellanaTokenRefs {
        split_ve_nft(account, ve_token, split_amounts)
    }
    #[test_only]
    public fun update_manifested_total_supply_test(old_amount: u64, old_end_epoch: u64, new_amount: u64, new_end_epoch: u64) acquires VeCellanaCollection {
        update_manifested_total_supply(old_amount, old_end_epoch, new_amount, new_end_epoch);
    }

    #[test_only]
    public fun increase_amount_rebase_test(ve_token: Object<VeCellanaToken>, rebase_tokens: FungibleAsset) acquires VeCellanaCollection, VeCellanaToken {
        increase_amount_rebase(ve_token, rebase_tokens);
    }

    #[test_only]
    public fun getAmount(ve_token: Object<VeCellanaToken>): u64 {
        fungible_asset::balance<VeCellanaToken>(ve_token)
    }
}