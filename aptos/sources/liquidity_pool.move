module fullsail::liquidity_pool {
    use std::string;
    use std::vector;
    use std::option;
    use std::error;
    use aptos_std::math64;
    use aptos_std::math128;
    use aptos_framework::object::{Self, Object};
    use aptos_framework::smart_table::{Self, SmartTable};
    use aptos_framework::fungible_asset::{Self, BurnRef, MintRef, TransferRef, FungibleStore, FungibleAsset};
    use aptos_framework::smart_vector;
    use aptos_framework::event;
    use aptos_framework::signer;
    use aptos_framework::dispatchable_fungible_asset;
    use aptos_framework::bcs;
    use aptos_framework::primary_fungible_store;
    use aptos_framework::comparator;

    // --- friends modules ---
    friend fullsail::gauge;
    friend fullsail::rewards_pool;

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

    // --- friends module ---
    friend fullsail::router;
    
    // --- structs ---
    struct FeesAccounting has key {
        total_fees_1: u128,
        total_fees_2: u128,
        total_fees_at_last_claim_1: SmartTable<address, u128>,
        total_fees_at_last_claim_2: SmartTable<address, u128>,
        claimable_1: SmartTable<address, u128>,
        claimable_2: SmartTable<address, u128>,
    }

    struct LPTokenRefs has store {
        burn_ref: BurnRef,
        mint_ref: MintRef,
        transfer_ref: TransferRef,
    }

    struct LiquidityPool has key {
        token_store_1: Object<FungibleStore>,
        token_store_2: Object<FungibleStore>,
        fees_store_1: Object<FungibleStore>,
        fees_store_2: Object<FungibleStore>,
        lp_token_refs: LPTokenRefs,
        swap_fee_bps: u64,
        is_stable: bool,
    }

    struct LiquidityPoolConfigs has key {
        all_pools: smart_vector::SmartVector<Object<LiquidityPool>>,
        is_paused: bool,
        fee_manager: address,
        pauser: address,
        pending_fee_manager: address,
        pending_pauser: address,
        stable_fee_bps: u64,
        volatile_fee_bps: u64,
    }

    // --- events ---
    #[event]
    struct AddLiquidityEvent has drop, store {
        lp: address,
        pool: address,
        amount_1: u64,
        amount_2: u64,
    }

    #[event]
    struct ClaimFeesEvent has drop, store {
        pool: address,
        amount_1: u64,
        amount_2: u64,
    }

    #[event]
    struct CreatePoolEvent has drop, store {
        pool: Object<LiquidityPool>,
        token_1: string::String,
        token_2: string::String,
        is_stable: bool,
    }

    #[event]
    struct RemoveLiquidityEvent has drop, store {
        lp: address,
        pool: address,
        amount_lp: u64,
        amount_1: u64,
        amount_2: u64,
    }

    #[event]
    struct SwapEvent has drop, store {
        pool: address,
        from_token: string::String,
        to_token: string::String,
        amount_in: u64,
        amount_out: u64,
    }

    #[event]
    struct SyncEvent has drop, store {
        pool: address,
        reserves_1: u128,
        reserves_2: u128,
    }

    #[event]
    struct TransferEvent has drop, store {
        pool: address,
        amount: u64,
        from: address,
        to: address,
    }

    public fun mint(_signer_ref: &signer, _primary_asset: FungibleAsset, _secondary_asset: FungibleAsset, _is_minting: bool) {
        abort 0
    }

    public(friend) fun swap(liquidity_pool: Object<LiquidityPool>, input_asset: FungibleAsset) : FungibleAsset acquires FeesAccounting, LiquidityPool, LiquidityPoolConfigs {
        assert!(!borrow_global<LiquidityPoolConfigs>(@fullsail).is_paused, E_LOCK_NOT_EXPIRED);
        
        let input_metadata = fungible_asset::metadata_from_asset(&input_asset);
        let input_amount = fungible_asset::amount(&input_asset);
        let (output_amount, fee_amount) = get_amount_out(liquidity_pool, input_metadata, input_amount);
        
        let extracted_fee = fungible_asset::extract(&mut input_asset, fee_amount);
        let pool_info = borrow_global<LiquidityPool>(object::object_address<LiquidityPool>(&liquidity_pool));
        
        let first_token_store = pool_info.token_store_1;
        let second_token_store = pool_info.token_store_2;
        
        let first_token_decimals = fungible_asset::decimals<fungible_asset::Metadata>(fungible_asset::store_metadata<FungibleStore>(first_token_store));
        let second_token_decimals = fungible_asset::decimals<fungible_asset::Metadata>(fungible_asset::store_metadata<FungibleStore>(second_token_store));
        
        let (standardized_reserve_first, standardized_reserve_second) = if (pool_info.is_stable) {
            standardize_reserve(
                (fungible_asset::balance<FungibleStore>(first_token_store) as u256), 
                (fungible_asset::balance<FungibleStore>(second_token_store) as u256), 
                first_token_decimals, 
                second_token_decimals
            )
        } else {
            ((fungible_asset::balance<FungibleStore>(first_token_store) as u256), (fungible_asset::balance<FungibleStore>(second_token_store) as u256))
        };
        
        let fees_accounting = borrow_global_mut<FeesAccounting>(object::object_address<LiquidityPool>(&liquidity_pool));
        let current_signer = fullsail::package_manager::get_signer();
        
        let output_asset = if (input_metadata == fungible_asset::store_metadata<FungibleStore>(pool_info.token_store_1)) {
            dispatchable_exact_deposit<FungibleStore>(first_token_store, input_asset);
            dispatchable_exact_deposit<FungibleStore>(pool_info.fees_store_1, extracted_fee);
            fees_accounting.total_fees_1 = fees_accounting.total_fees_1 + (output_amount as u128);
            dispatchable_exact_withdraw<FungibleStore>(&current_signer, second_token_store, output_amount)
        } else {
            dispatchable_exact_deposit<FungibleStore>(second_token_store, input_asset);
            dispatchable_exact_deposit<FungibleStore>(pool_info.fees_store_2, extracted_fee);
            fees_accounting.total_fees_2 = fees_accounting.total_fees_2 + (output_amount as u128);
            dispatchable_exact_withdraw<FungibleStore>(&current_signer, first_token_store, output_amount)
        };

        let (updated_reserve_first, updated_reserve_second) = if (pool_info.is_stable) {
            standardize_reserve(
                (fungible_asset::balance<FungibleStore>(first_token_store) as u256), 
                (fungible_asset::balance<FungibleStore>(second_token_store) as u256), 
                first_token_decimals, 
                second_token_decimals
            )
        } else {
            ((fungible_asset::balance<FungibleStore>(first_token_store) as u256), (fungible_asset::balance<FungibleStore>(second_token_store) as u256))
        };

        assert!(calculate_k(standardized_reserve_first, standardized_reserve_second, pool_info.is_stable) <= calculate_k(updated_reserve_first, updated_reserve_second, pool_info.is_stable), E_INVALID_UPDATE);
        
        let swap_event = SwapEvent{
            pool: object::object_address<LiquidityPool>(&liquidity_pool),
            from_token: fullsail::coin_wrapper::get_original(input_metadata),
            to_token: fullsail::coin_wrapper::get_original(fungible_asset::metadata_from_asset(&output_asset)),
            amount_in: input_amount,
            amount_out: output_amount,
        };
        
        event::emit<SwapEvent>(swap_event);
        
        let sync_event = SyncEvent{
            pool: object::object_address<LiquidityPool>(&liquidity_pool),
            reserves_1: (fungible_asset::balance<FungibleStore>(pool_info.token_store_1) as u128),
            reserves_2: (fungible_asset::balance<FungibleStore>(pool_info.token_store_2) as u128),
        };
        
        event::emit<SyncEvent>(sync_event);
        output_asset
    }

    public entry fun initialize() {
        if (is_initialized()) {
            return
        };
        
        fullsail::coin_wrapper::initialize();
        let signer = fullsail::package_manager::get_signer();
        
        let liquidity_pool_configs = LiquidityPoolConfigs{
            all_pools: smart_vector::new<Object<LiquidityPool>>(),
            is_paused: false,
            fee_manager: @0xc3bb8488ab1a5815a9d543d7e41b0e0df46a7396f89b22821f07a4362f75ddc5,
            pauser: @0xc3bb8488ab1a5815a9d543d7e41b0e0df46a7396f89b22821f07a4362f75ddc5,
            pending_fee_manager: @0x0,
            pending_pauser: @0x0,
            stable_fee_bps: 4,
            volatile_fee_bps: 10,
        };
        
        move_to<LiquidityPoolConfigs>(&signer, liquidity_pool_configs);
    }

    public fun liquidity_pool(first_metadata: Object<fungible_asset::Metadata>, second_metadata: Object<fungible_asset::Metadata>, is_stable: bool) : Object<LiquidityPool> {
        object::address_to_object<LiquidityPool>(liquidity_pool_address(first_metadata, second_metadata, is_stable))
    }

    public entry fun accept_fee_manager(signer_ref: &signer) acquires LiquidityPoolConfigs {
        let liquidity_pool_configs = borrow_global_mut<LiquidityPoolConfigs>(@fullsail);
        assert!(signer::address_of(signer_ref) == liquidity_pool_configs.pending_fee_manager, E_NOT_OWNER);
        liquidity_pool_configs.fee_manager = liquidity_pool_configs.pending_fee_manager;
        liquidity_pool_configs.pending_fee_manager = @0x0;
    }

    public entry fun accept_pauser(signer_ref: &signer) acquires LiquidityPoolConfigs {
        let liquidity_pool_configs = borrow_global_mut<LiquidityPoolConfigs>(@fullsail);
        assert!(signer::address_of(signer_ref) == liquidity_pool_configs.pending_pauser, E_NOT_OWNER);
        liquidity_pool_configs.pauser = liquidity_pool_configs.pending_pauser;
        liquidity_pool_configs.pending_pauser = @0x0;
    }

    public fun all_pool_addresses() : vector<Object<LiquidityPool>> acquires LiquidityPoolConfigs {
        smart_vector::to_vector<Object<LiquidityPool>>(&borrow_global<LiquidityPoolConfigs>(@fullsail).all_pools)
    }

    public(friend) fun burn(signer_ref: &signer, first_metadata: Object<fungible_asset::Metadata>, second_metadata: Object<fungible_asset::Metadata>, is_stable: bool, lp_amount: u64) : (FungibleAsset, FungibleAsset) acquires LiquidityPool {
        assert!(lp_amount > 0, E_INSUFFICIENT_BALANCE);
        let signer_address = signer::address_of(signer_ref);
        let liquidity_pool_object = liquidity_pool(first_metadata, second_metadata, is_stable);
        let lp_token_store = ensure_lp_token_store<LiquidityPool>(signer_address, liquidity_pool_object);
        let (withdraw_amount_1, withdraw_amount_2) = liquidity_amounts(liquidity_pool_object, lp_amount);
        assert!(withdraw_amount_1 > 0 && withdraw_amount_2 > 0, E_MAX_LOCK_TIME);
        
        let liquidity_pool_data = borrow_global<LiquidityPool>(object::object_address<LiquidityPool>(&liquidity_pool_object));
        fungible_asset::burn_from<FungibleStore>(&liquidity_pool_data.lp_token_refs.burn_ref, lp_token_store, lp_amount);
        
        let current_signer = fullsail::package_manager::get_signer();
        let current_signer_ref = &current_signer;
        let withdrawn_asset_1 = dispatchable_fungible_asset::withdraw<FungibleStore>(current_signer_ref, liquidity_pool_data.token_store_1, withdraw_amount_1);
        let withdrawn_asset_2 = dispatchable_fungible_asset::withdraw<FungibleStore>(current_signer_ref, liquidity_pool_data.token_store_2, withdraw_amount_2);
        
        let ordered_withdrawn_asset_1;
        let ordered_withdrawn_asset_2;

        if (!is_sorted(first_metadata, second_metadata)) {
            ordered_withdrawn_asset_1 = withdrawn_asset_2;
            ordered_withdrawn_asset_2 = withdrawn_asset_1;
        } else {
            ordered_withdrawn_asset_1 = withdrawn_asset_1;
            ordered_withdrawn_asset_2 = withdrawn_asset_2;
        };
        
        let remove_liquidity_event = RemoveLiquidityEvent {
            lp: signer_address,
            pool: object::object_address<LiquidityPool>(&liquidity_pool_object),
            amount_lp: lp_amount,
            amount_1: withdraw_amount_1,
            amount_2: withdraw_amount_2,
        };
        event::emit<RemoveLiquidityEvent>(remove_liquidity_event);
        
        let sync_event = SyncEvent {
            pool: object::object_address<LiquidityPool>(&liquidity_pool_object),
            reserves_1: fungible_asset::balance<FungibleStore>(liquidity_pool_data.token_store_1) as u128,
            reserves_2: fungible_asset::balance<FungibleStore>(liquidity_pool_data.token_store_2) as u128,
        };
        event::emit<SyncEvent>(sync_event);
        
        (ordered_withdrawn_asset_1, ordered_withdrawn_asset_2)
    }

    fun calculate_constant_k(liquidity_pool: &LiquidityPool) : u256 {
        let reserve_amount_1 = (fungible_asset::balance<FungibleStore>(liquidity_pool.token_store_1) as u256);
        let reserve_amount_2 = (fungible_asset::balance<FungibleStore>(liquidity_pool.token_store_2) as u256);
        if (liquidity_pool.is_stable) {
            reserve_amount_1 * reserve_amount_1 * reserve_amount_1 * reserve_amount_2 + reserve_amount_2 * reserve_amount_2 * reserve_amount_2 * reserve_amount_1
        } else {
            reserve_amount_1 * reserve_amount_2
        }
    }

    fun calculate_k(amount_1: u256, amount_2: u256, is_stable: bool) : u256 {
        if (is_stable) {
            amount_1 * amount_1 * amount_1 * amount_2 + amount_2 * amount_2 * amount_2 * amount_1
        } else {
            amount_1 * amount_2
        }
    }

    public(friend) fun claim_fees(_signer_ref: &signer, liquidity_pool_object: Object<LiquidityPool>) : (FungibleAsset, FungibleAsset) acquires LiquidityPool {
        let (claimable_amount_1, claimable_amount_2) = gauge_claimable_fees(liquidity_pool_object);
        let liquidity_pool_data = borrow_global<LiquidityPool>(object::object_address<LiquidityPool>(&liquidity_pool_object));
        let current_signer = fullsail::package_manager::get_signer();
        let current_signer_ref = &current_signer;

        let withdrawn_asset_1 = if (claimable_amount_1 > 0) {
            dispatchable_fungible_asset::withdraw<FungibleStore>(current_signer_ref, liquidity_pool_data.fees_store_1, claimable_amount_1)
        } else {
            fungible_asset::zero<fungible_asset::Metadata>(fungible_asset::store_metadata<FungibleStore>(liquidity_pool_data.fees_store_1))
        };

        let withdrawn_asset_2 = if (claimable_amount_2 > 0) {
            dispatchable_fungible_asset::withdraw<FungibleStore>(current_signer_ref, liquidity_pool_data.fees_store_2, claimable_amount_2)
        } else {
            fungible_asset::zero<fungible_asset::Metadata>(fungible_asset::store_metadata<FungibleStore>(liquidity_pool_data.fees_store_2))
        };

        let claim_fees_event = ClaimFeesEvent {
            pool: object::object_address<LiquidityPool>(&liquidity_pool_object),
            amount_1: (claimable_amount_1 as u64),
            amount_2: (claimable_amount_2 as u64),
        };
        event::emit<ClaimFeesEvent>(claim_fees_event);
        (withdrawn_asset_1, withdrawn_asset_2)
    }

    public fun claimable_fees(_user_address: address, _liquidity_pool_object: Object<LiquidityPool>) : (u128, u128) {
        abort 0
    }

    public(friend) fun create(first_metadata: Object<fungible_asset::Metadata>, second_metadata: Object<fungible_asset::Metadata>, is_stable: bool) : Object<LiquidityPool> acquires LiquidityPoolConfigs {
        if (!is_sorted(first_metadata, second_metadata)) {
            return create(second_metadata, first_metadata, is_stable)
        };
        let liquidity_pool_configs = borrow_global_mut<LiquidityPoolConfigs>(@fullsail);
        let name_bytes = b"";
        let first_metadata_address = object::object_address<fungible_asset::Metadata>(&first_metadata);
        vector::append<u8>(&mut name_bytes, bcs::to_bytes<address>(&first_metadata_address));
        let second_metadata_address = object::object_address<fungible_asset::Metadata>(&second_metadata);
        vector::append<u8>(&mut name_bytes, bcs::to_bytes<address>(&second_metadata_address));
        vector::append<u8>(&mut name_bytes, bcs::to_bytes<bool>(&is_stable));
        
        let current_signer = fullsail::package_manager::get_signer();
        let liquidity_pool_instance = object::create_named_object(&current_signer, name_bytes);
        let liquidity_pool_instance_ref = &liquidity_pool_instance;

        primary_fungible_store::create_primary_store_enabled_fungible_asset(
            liquidity_pool_instance_ref,
            option::none<u128>(),
            lp_token_name(first_metadata, second_metadata),
            string::utf8(b"LP"),
            8,
            string::utf8(b""),
            string::utf8(b"")
        );

        let liquidity_pool_signer = object::generate_signer(liquidity_pool_instance_ref);
        let liquidity_pool_signer_ref = &liquidity_pool_signer;
        let metadata_instance = object::object_from_constructor_ref<fungible_asset::Metadata>(liquidity_pool_instance_ref);
        fungible_asset::create_store<fungible_asset::Metadata>(liquidity_pool_instance_ref, metadata_instance);
        
        let lp_token_references = LPTokenRefs {
            burn_ref: fungible_asset::generate_burn_ref(liquidity_pool_instance_ref),
            mint_ref: fungible_asset::generate_mint_ref(liquidity_pool_instance_ref),
            transfer_ref: fungible_asset::generate_transfer_ref(liquidity_pool_instance_ref),
        };
        
        let fee_bps = if (is_stable) {
            liquidity_pool_configs.stable_fee_bps
        } else {
            liquidity_pool_configs.volatile_fee_bps
        };

        let new_liquidity_pool = LiquidityPool {
            token_store_1: create_token_store(liquidity_pool_signer_ref, first_metadata),
            token_store_2: create_token_store(liquidity_pool_signer_ref, second_metadata),
            fees_store_1: create_token_store(liquidity_pool_signer_ref, first_metadata),
            fees_store_2: create_token_store(liquidity_pool_signer_ref, second_metadata),
            lp_token_refs: lp_token_references,
            swap_fee_bps: fee_bps,
            is_stable: is_stable,
        };
        
        move_to<LiquidityPool>(liquidity_pool_signer_ref, new_liquidity_pool);

        let fees_accounting = FeesAccounting {
            total_fees_1: 0,
            total_fees_2: 0,
            total_fees_at_last_claim_1: smart_table::new<address, u128>(),
            total_fees_at_last_claim_2: smart_table::new<address, u128>(),
            claimable_1: smart_table::new<address, u128>(),
            claimable_2: smart_table::new<address, u128>(),
        };
        move_to<FeesAccounting>(liquidity_pool_signer_ref, fees_accounting);

        let liquidity_pool_metadata = object::convert<fungible_asset::Metadata, LiquidityPool>(metadata_instance);
        smart_vector::push_back<Object<LiquidityPool>>(&mut liquidity_pool_configs.all_pools, liquidity_pool_metadata);
        
        let create_pool_event = CreatePoolEvent {
            pool: liquidity_pool_metadata,
            token_1: fullsail::coin_wrapper::get_original(first_metadata),
            token_2: fullsail::coin_wrapper::get_original(second_metadata),
            is_stable: is_stable,
        };
        event::emit<CreatePoolEvent>(create_pool_event);
        liquidity_pool_metadata
    }

    fun create_token_store(signer_ref: &signer, metadata: Object<fungible_asset::Metadata>) : Object<FungibleStore> {
        let store_instance = object::create_object_from_object(signer_ref);
        fungible_asset::create_store<fungible_asset::Metadata>(&store_instance, metadata)
    }

    public(friend) fun deposit_fungible_asset<T: key>(store: Object<T>, asset: FungibleAsset) : u64 {
        let old = fungible_asset::balance<T>(store);
        dispatchable_fungible_asset::deposit<T>(store, asset);
        let new = fungible_asset::balance<T>(store);
        new - old
    }

    public(friend) fun dispatchable_exact_deposit<T: key>(store: Object<T>, asset: FungibleAsset) {
        let asset_amount = fungible_asset::amount(&asset);
        assert!(asset_amount == deposit_fungible_asset<T>(store, asset), E_INVALID_SPLIT_AMOUNT);
    }

    public(friend) fun dispatchable_exact_withdraw<T: key>(signer_ref: &signer, store: Object<T>, amount: u64) : FungibleAsset {
        let withdrawn_asset = dispatchable_fungible_asset::withdraw<T>(signer_ref, store, amount);
        assert!(fungible_asset::amount(&withdrawn_asset) == amount, E_INVALID_SPLIT_AMOUNT);
        withdrawn_asset
    }

    fun ensure_lp_token_store<T: key>(user_address: address, store: Object<T>) : Object<FungibleStore> acquires LiquidityPool {
        primary_fungible_store::ensure_primary_store_exists<T>(user_address, store);
        let primary_store = primary_fungible_store::primary_store<T>(user_address, store);
        
        if (!fungible_asset::is_frozen<FungibleStore>(primary_store)) {
            fungible_asset::set_frozen_flag<FungibleStore>(&borrow_global<LiquidityPool>(object::object_address<T>(&store)).lp_token_refs.transfer_ref, primary_store, true);
        };
        
        primary_store
    }

    public fun gauge_claimable_fees(pool: Object<LiquidityPool>) : (u64, u64) acquires LiquidityPool {
        let liquidity_pool = borrow_global<LiquidityPool>(object::object_address<LiquidityPool>(&pool));
        (
            fungible_asset::balance<FungibleStore>(liquidity_pool.fees_store_1), 
            fungible_asset::balance<FungibleStore>(liquidity_pool.fees_store_2)
        )
    }

    public fun get_amount_out(pool: Object<LiquidityPool>, asset_metadata: Object<fungible_asset::Metadata>, amount_in: u64) : (u64, u64) acquires LiquidityPool {
        let (token1_metadata, token2_metadata, reserve1, reserve2, scale1, scale2) = pool_metadata(pool);
        let liquidity_pool = borrow_global<LiquidityPool>(object::object_address<LiquidityPool>(&pool));
        
        assert!(asset_metadata == token1_metadata || asset_metadata == token2_metadata, E_LOCK_EXPIRED);
        
        let (reserve_a, reserve_b, scale_a, scale_b) = if (asset_metadata == token1_metadata) {
            ((reserve1 as u256), (reserve2 as u256), scale1, scale2)
        } else {
            ((reserve2 as u256), (reserve1 as u256), scale2, scale1)
        };
        
        let constant_factor = 10000;
        assert!(constant_factor != 0, error::invalid_argument(E_ZERO_TOTAL_POWER));
        
        let adjusted_amount_in = (((amount_in as u128) * ((10000 - liquidity_pool.swap_fee_bps) as u128) / (constant_factor as u128)) as u64);
        let amount_in_u256 = (adjusted_amount_in as u256);
        
        let output_amount = if (liquidity_pool.is_stable) {
            let (standard_reserve_a, standard_reserve_b) = standardize_reserve(reserve_a, reserve_b, scale_a, scale_b);
            let pow10_scale_b = math128::pow(10, (scale_b as u128));
            assert!(pow10_scale_b != 0, error::invalid_argument(E_ZERO_TOTAL_POWER));
            
            let constant_factor_large = (100000000 as u128);
            assert!(constant_factor_large != 0, error::invalid_argument(E_ZERO_TOTAL_POWER));
            
            ((((((standard_reserve_b - get_y((((((amount_in_u256 as u128) as u256) * ((constant_factor_large as u128) as u256) / (pow10_scale_b as u256)) as u128) as u256) + standard_reserve_a, calculate_k(standard_reserve_a, standard_reserve_b, liquidity_pool.is_stable), standard_reserve_b)) as u128) as u256) * (math128::pow(10, (scale_b as u128)) as u256) / (constant_factor_large as u256)) as u128) as u256)
        } else {
            amount_in_u256 * reserve_b / (reserve_a + amount_in_u256)
        };
        
        ((output_amount as u64), amount_in - adjusted_amount_in)
    }

    public fun get_trade_diff(pool: Object<LiquidityPool>, asset_metadata: Object<fungible_asset::Metadata>, amount_in: u64) : (u64, u64) acquires LiquidityPool {
        let (token1_metadata, _, reserve1, reserve2, scale1, scale2) = pool_metadata(pool);
        
        let selected_scale = if (asset_metadata == token1_metadata) {
            (scale1 as u64)
        } else {
            (scale2 as u64)
        };

        let calculated_amount_out = if (asset_metadata == token1_metadata) {
            assert!(reserve2 != 0, error::invalid_argument(E_ZERO_TOTAL_POWER));
            (((reserve1 as u128) * (math64::pow(10, (scale2 as u64)) as u128) / (reserve2 as u128)) as u64)
        } else {
            assert!(reserve1 != 0, error::invalid_argument(E_ZERO_TOTAL_POWER));
            (((reserve2 as u128) * (math64::pow(10, (scale1 as u64)) as u128) / (reserve1 as u128)) as u64)
        };

        let (amount_out_for_calculated, _) = get_amount_out(pool, asset_metadata, calculated_amount_out);
        assert!(calculated_amount_out != 0, error::invalid_argument(E_ZERO_TOTAL_POWER));
        
        let (amount_out_for_input, _) = get_amount_out(pool, asset_metadata, amount_in);
        assert!(amount_in != 0, error::invalid_argument(E_ZERO_TOTAL_POWER));
        
        (
            (((amount_out_for_calculated as u128) * (math64::pow(10, selected_scale) as u128) / (calculated_amount_out as u128)) as u64),
            (((amount_out_for_input as u128) * (math64::pow(10, selected_scale) as u128) / (amount_in as u128)) as u64)
        )
    }

    fun get_y(target_value: u256, multiplier: u256, current_guess: u256) : u256 {
        let iteration_count: u64 = 0;
        while (iteration_count < 255) {
            let calculated_output = multiplier * current_guess * current_guess * current_guess 
                + multiplier * multiplier * multiplier * current_guess;
            
            if (calculated_output < target_value) {
                let adjustment = (target_value - calculated_output) / 
                    (3 * multiplier * current_guess * current_guess + multiplier * multiplier * multiplier);
                current_guess = current_guess + adjustment;
            } else {
                let adjustment = (calculated_output - target_value) / 
                    (3 * multiplier * current_guess * current_guess + multiplier * multiplier * multiplier);
                current_guess = current_guess - adjustment;
            };
            
            if (current_guess > current_guess) {
                if (current_guess - current_guess <= 1) {
                    return current_guess
                };
            } else if (current_guess - current_guess <= 1) {
                return current_guess
            };
            
            iteration_count = iteration_count + 1;
        };
        current_guess
    }

    public fun is_initialized() : bool {
        exists<LiquidityPoolConfigs>(@fullsail)
    }

    public fun is_sorted(asset1: Object<fungible_asset::Metadata>, asset2: Object<fungible_asset::Metadata>) : bool {
        assert!(asset1 != asset2, E_NO_SNAPSHOT);
        let asset1_address = object::object_address<fungible_asset::Metadata>(&asset1);
        let asset2_address = object::object_address<fungible_asset::Metadata>(&asset2);
        let comparison_result = comparator::compare<address>(&asset1_address, &asset2_address);
        comparator::is_smaller_than(&comparison_result)
    }

    public fun is_stable(pool: Object<LiquidityPool>) : bool acquires LiquidityPool {
        borrow_global<LiquidityPool>(object::object_address<LiquidityPool>(&pool)).is_stable
    }

    public fun liquidity_amounts(pool: Object<LiquidityPool>, total_liquidity: u64) : (u64, u64) acquires LiquidityPool {
        let total_supply = option::destroy_some<u128>(fungible_asset::supply<LiquidityPool>(pool));
        let pool_data = borrow_global<LiquidityPool>(object::object_address<LiquidityPool>(&pool));
        assert!(total_supply != 0, error::invalid_argument(E_ZERO_TOTAL_POWER));
        assert!(total_supply != 0, error::invalid_argument(E_ZERO_TOTAL_POWER));
        (
            (((((total_liquidity as u128) * (fungible_asset::balance<FungibleStore>(pool_data.token_store_1) as u128)) / (total_supply as u128)) as u128) as u64),
            (((((total_liquidity as u128) * (fungible_asset::balance<FungibleStore>(pool_data.token_store_2) as u128)) / (total_supply as u128)) as u128) as u64)
        )
    }

    public fun liquidity_out(asset1: Object<fungible_asset::Metadata>, asset2: Object<fungible_asset::Metadata>, is_stable: bool, amount1: u64, amount2: u64) : u64 acquires LiquidityPool {
        if (!is_sorted(asset1, asset2)) {
            return liquidity_out(asset2, asset1, is_stable, amount2, amount1)
        };
        let pool_address = liquidity_pool(asset1, asset2, is_stable);
        let pool_data = borrow_global<LiquidityPool>(object::object_address<LiquidityPool>(&pool_address));
        let reserve1 = fungible_asset::balance<FungibleStore>(pool_data.token_store_1);
        let reserve2 = fungible_asset::balance<FungibleStore>(pool_data.token_store_2);
        let total_supply = option::destroy_some<u128>(fungible_asset::supply<LiquidityPool>(pool_address));
        
        if (total_supply == 0) {
            (math128::sqrt((amount1 as u128) * (amount2 as u128)) as u64) - 1000
        } else {
            assert!(reserve1 != 0, error::invalid_argument(E_ZERO_TOTAL_POWER));
            assert!(reserve2 != 0, error::invalid_argument(E_ZERO_TOTAL_POWER));
            math64::min(
                (((amount1 as u128) * (total_supply as u128) / (reserve1 as u128)) as u64), 
                (((amount2 as u128) * (total_supply as u128) / (reserve2 as u128)) as u64)
            )
        }
    }

    public fun liquidity_pool_address(asset1: Object<fungible_asset::Metadata>, asset2: Object<fungible_asset::Metadata>, is_stable: bool) : address {
        if (!is_sorted(asset1, asset2)) {
            return liquidity_pool_address(asset2, asset1, is_stable)
        };
        let base_address = @fullsail;
        let address_bytes = b"";
        let asset1_address = object::object_address<fungible_asset::Metadata>(&asset1);
        vector::append<u8>(&mut address_bytes, bcs::to_bytes<address>(&asset1_address));
        let asset2_address = object::object_address<fungible_asset::Metadata>(&asset2);
        vector::append<u8>(&mut address_bytes, bcs::to_bytes<address>(&asset2_address));
        vector::append<u8>(&mut address_bytes, bcs::to_bytes<bool>(&is_stable));
        object::create_object_address(&base_address, address_bytes)
    }

    fun lp_token_name(asset1: Object<fungible_asset::Metadata>, asset2: Object<fungible_asset::Metadata>) : string::String {
        let lp_name = string::utf8(b"LP-");
        string::append(&mut lp_name, fungible_asset::symbol<fungible_asset::Metadata>(asset1));
        string::append_utf8(&mut lp_name, b"-");
        string::append(&mut lp_name, fungible_asset::symbol<fungible_asset::Metadata>(asset2));
        lp_name
    }

    public fun lp_token_supply<T: key>(token: Object<T>) : u128 {
        option::destroy_some<u128>(fungible_asset::supply<T>(token))
    }

    public fun min_liquidity() : u64 {
        1000
    }

    public(friend) fun mint_lp(signer_ref: &signer, asset1: FungibleAsset, asset2: FungibleAsset, is_stable: bool) : u64 acquires FeesAccounting, LiquidityPool {
        let metadata1 = fungible_asset::metadata_from_asset(&asset1);
        let metadata2 = fungible_asset::metadata_from_asset(&asset2);
        
        if (!is_sorted(metadata1, metadata2)) {
            return mint_lp(signer_ref, asset2, asset1, is_stable)
        };
        
        let pool_address = liquidity_pool(metadata1, metadata2, is_stable);
        let signer_address = signer::address_of(signer_ref);
        let lp_store = ensure_lp_token_store<LiquidityPool>(signer_address, pool_address);
        let amount1 = fungible_asset::amount(&asset1);
        let amount2 = fungible_asset::amount(&asset2);
        assert!(amount1 > 0 && amount2 > 0, E_INSUFFICIENT_BALANCE);
        
        let pool_data = borrow_global<LiquidityPool>(object::object_address<LiquidityPool>(&pool_address));
        let token_store1 = pool_data.token_store_1;
        let token_store2 = pool_data.token_store_2;
        let total_supply = option::destroy_some<u128>(fungible_asset::supply<LiquidityPool>(pool_address));
        let mint_ref = &pool_data.lp_token_refs.mint_ref;
        
        let liquidity_out = if (total_supply == 0) {
            fungible_asset::mint_to<LiquidityPool>(mint_ref, pool_address, 1000);
            (math128::sqrt((amount1 as u128) * (amount2 as u128)) as u64) - 1000
        } else {
            assert!(fungible_asset::balance<FungibleStore>(token_store1) != 0, error::invalid_argument(E_ZERO_TOTAL_POWER));
            assert!(fungible_asset::balance<FungibleStore>(token_store2) != 0, error::invalid_argument(E_ZERO_TOTAL_POWER));
            math64::min(
                (((amount1 as u128) * (total_supply as u128) / (fungible_asset::balance<FungibleStore>(token_store1) as u128)) as u64),
                (((amount2 as u128) * (total_supply as u128) / (fungible_asset::balance<FungibleStore>(token_store2) as u128)) as u64)
            )
        };
        
        assert!(liquidity_out > 0, E_MIN_LOCK_TIME);
        dispatchable_exact_deposit<FungibleStore>(token_store1, asset1);
        dispatchable_exact_deposit<FungibleStore>(token_store2, asset2);
        
        let minted_token = fungible_asset::mint(mint_ref, liquidity_out);
        let minted_amount = fungible_asset::amount(&minted_token);
        
        fungible_asset::deposit_with_ref<FungibleStore>(&pool_data.lp_token_refs.transfer_ref, lp_store, minted_token);
        
        let add_liquidity_event = AddLiquidityEvent {
            lp: signer_address,
            pool: object::object_address<LiquidityPool>(&pool_address),
            amount_1: amount1,
            amount_2: amount2,
        };
        event::emit<AddLiquidityEvent>(add_liquidity_event);
        
        let sync_event = SyncEvent {
            pool: object::object_address<LiquidityPool>(&pool_address),
            reserves_1: (fungible_asset::balance<FungibleStore>(pool_data.token_store_1) as u128),
            reserves_2: (fungible_asset::balance<FungibleStore>(pool_data.token_store_2) as u128),
        };
        event::emit<SyncEvent>(sync_event);
        
        minted_amount
    }

    public fun pool_metadata(pool_object: Object<LiquidityPool>) : (Object<fungible_asset::Metadata>, Object<fungible_asset::Metadata>, u64, u64, u8, u8) acquires LiquidityPool {
        let liquidity_pool = borrow_global<LiquidityPool>(object::object_address<LiquidityPool>(&pool_object));
        let token_metadata_1 = fungible_asset::store_metadata<FungibleStore>(liquidity_pool.token_store_1);
        let token_metadata_2 = fungible_asset::store_metadata<FungibleStore>(liquidity_pool.token_store_2);
        (token_metadata_1, token_metadata_2, fungible_asset::balance<FungibleStore>(liquidity_pool.token_store_1), fungible_asset::balance<FungibleStore>(liquidity_pool.token_store_2), fungible_asset::decimals<fungible_asset::Metadata>(token_metadata_1), fungible_asset::decimals<fungible_asset::Metadata>(token_metadata_2))
    }

    public fun pool_reserve(pool_ref: &LiquidityPool) : (u64, u64, u8, u8) {
        (fungible_asset::balance<FungibleStore>(pool_ref.token_store_1), fungible_asset::balance<FungibleStore>(pool_ref.token_store_2), fungible_asset::decimals<fungible_asset::Metadata>(fungible_asset::store_metadata<FungibleStore>(pool_ref.token_store_1)), fungible_asset::decimals<fungible_asset::Metadata>(fungible_asset::store_metadata<FungibleStore>(pool_ref.token_store_2)))
    }

    public fun pool_reserves<T0: key>(pool_object: Object<T0>) : (u64, u64) acquires LiquidityPool {
        let liquidity_pool = borrow_global<LiquidityPool>(object::object_address<T0>(&pool_object));
        (fungible_asset::balance<FungibleStore>(liquidity_pool.token_store_1), fungible_asset::balance<FungibleStore>(liquidity_pool.token_store_2))
    }

    public entry fun set_fee_manager(signer_ref: &signer, new_fee_manager: address) acquires LiquidityPoolConfigs {
        let pool_configs = borrow_global_mut<LiquidityPoolConfigs>(@fullsail);
        assert!(signer::address_of(signer_ref) == pool_configs.fee_manager, E_NOT_OWNER);
        pool_configs.pending_fee_manager = new_fee_manager;
    }

    public entry fun set_pause(signer_ref: &signer, pause_status: bool) acquires LiquidityPoolConfigs {
        let pool_configs = borrow_global_mut<LiquidityPoolConfigs>(@fullsail);
        assert!(signer::address_of(signer_ref) == pool_configs.pauser, E_NOT_OWNER);
        pool_configs.is_paused = pause_status;
    }

    public entry fun set_pauser(signer_ref: &signer, new_pauser: address) acquires LiquidityPoolConfigs {
        let pool_configs = borrow_global_mut<LiquidityPoolConfigs>(@fullsail);
        assert!(signer::address_of(signer_ref) == pool_configs.pauser, E_NOT_OWNER);
        pool_configs.pending_pauser = new_pauser;
    }

    public entry fun set_pool_swap_fee(signer_ref: &signer, pool_object: Object<LiquidityPool>, new_swap_fee: u64) acquires LiquidityPool, LiquidityPoolConfigs {
        assert!(new_swap_fee <= 30, E_ZERO_AMOUNT);
        assert!(signer::address_of(signer_ref) == borrow_global_mut<LiquidityPoolConfigs>(@fullsail).fee_manager, E_NOT_OWNER);
        borrow_global_mut<LiquidityPool>(object::object_address<LiquidityPool>(&pool_object)).swap_fee_bps = new_swap_fee;
    }

    public entry fun set_stable_fee(signer_ref: &signer, new_stable_fee: u64) acquires LiquidityPoolConfigs {
        assert!(new_stable_fee <= 30, E_ZERO_AMOUNT);
        let pool_configs = borrow_global_mut<LiquidityPoolConfigs>(@fullsail);
        assert!(signer::address_of(signer_ref) == pool_configs.fee_manager, E_NOT_OWNER);
        pool_configs.stable_fee_bps = new_stable_fee;
    }

    public entry fun set_volatile_fee(signer_ref: &signer, new_volatile_fee: u64) acquires LiquidityPoolConfigs {
        assert!(new_volatile_fee <= 30, E_ZERO_AMOUNT);
        let pool_configs = borrow_global_mut<LiquidityPoolConfigs>(@fullsail);
        assert!(signer::address_of(signer_ref) == pool_configs.fee_manager, E_NOT_OWNER);
        pool_configs.volatile_fee_bps = new_volatile_fee;
    }

    fun standardize_reserve(amount_1: u256, amount_2: u256, decimals_1: u8, decimals_2: u8) : (u256, u256) {
        let factor_1 = math128::pow(10, (decimals_1 as u128));
        let factor_2 = math128::pow(10, (decimals_2 as u128));
        assert!(factor_1 != 0, error::invalid_argument(E_ZERO_TOTAL_POWER));
        assert!(factor_2 != 0, error::invalid_argument(E_ZERO_TOTAL_POWER));
        ((((((amount_1 as u128) as u256) * ((100000000 as u128) as u256) / (factor_1 as u256)) as u128) as u256), (((((amount_2 as u128) as u256) * ((100000000 as u128) as u256) / (factor_2 as u256)) as u128) as u256))
    }

    public fun supported_inner_assets(pool_object: Object<LiquidityPool>) : vector<Object<fungible_asset::Metadata>> acquires LiquidityPool {
        let liquidity_pool = borrow_global<LiquidityPool>(object::object_address<LiquidityPool>(&pool_object));
        let inner_assets = vector::empty<Object<fungible_asset::Metadata>>();
        let inner_assets_mut = &mut inner_assets;
        vector::push_back<Object<fungible_asset::Metadata>>(inner_assets_mut, fungible_asset::store_metadata<FungibleStore>(liquidity_pool.token_store_1));
        vector::push_back<Object<fungible_asset::Metadata>>(inner_assets_mut, fungible_asset::store_metadata<FungibleStore>(liquidity_pool.token_store_2));
        inner_assets
    }

    public fun supported_native_fungible_assets(pool_object: Object<LiquidityPool>) : vector<Object<fungible_asset::Metadata>> acquires LiquidityPool {
        let inner_assets = supported_inner_assets(pool_object);
        let native_assets = vector::empty<Object<fungible_asset::Metadata>>();
        vector::reverse<Object<fungible_asset::Metadata>>(&mut inner_assets);
        let inner_assets_length = vector::length<Object<fungible_asset::Metadata>>(&inner_assets);
        while (inner_assets_length > 0) {
            let asset = vector::pop_back<Object<fungible_asset::Metadata>>(&mut inner_assets);
            if (!fullsail::coin_wrapper::is_wrapper(asset)) {
                vector::push_back<Object<fungible_asset::Metadata>>(&mut native_assets, asset);
            };
            inner_assets_length = inner_assets_length - 1;
        };
        vector::destroy_empty<Object<fungible_asset::Metadata>>(inner_assets);
        native_assets
    }

    public fun supported_token_strings(pool_object: Object<LiquidityPool>) : vector<string::String> acquires LiquidityPool {
        let inner_assets = supported_inner_assets(pool_object);
        let token_strings = vector::empty<string::String>();
        vector::reverse<Object<fungible_asset::Metadata>>(&mut inner_assets);
        let inner_assets_length = vector::length<Object<fungible_asset::Metadata>>(&inner_assets);
        while (inner_assets_length > 0) {
            vector::push_back<string::String>(&mut token_strings, fullsail::coin_wrapper::get_original(vector::pop_back<Object<fungible_asset::Metadata>>(&mut inner_assets)));
            inner_assets_length = inner_assets_length - 1;
        };
        vector::destroy_empty<Object<fungible_asset::Metadata>>(inner_assets);
        token_strings
    }

    public fun swap_fee_bps(pool_object: Object<LiquidityPool>) : u64 acquires LiquidityPool {
        borrow_global<LiquidityPool>(object::object_address<LiquidityPool>(&pool_object)).swap_fee_bps
    }

    public entry fun transfer(signer_ref: &signer, pool_object: Object<LiquidityPool>, recipient: address, amount: u64) acquires LiquidityPool {
        assert!(amount > 0, E_INSUFFICIENT_BALANCE);
        let sender_address = signer::address_of(signer_ref);
        let sender_store = ensure_lp_token_store<LiquidityPool>(sender_address, pool_object);
        let recipient_store = ensure_lp_token_store<LiquidityPool>(recipient, pool_object);
        fungible_asset::transfer_with_ref<FungibleStore>(&borrow_global<LiquidityPool>(object::object_address<LiquidityPool>(&pool_object)).lp_token_refs.transfer_ref, sender_store, recipient_store, amount);
        let transfer_event = TransferEvent{
            pool   : object::object_address<LiquidityPool>(&pool_object),
            amount : amount,
            from   : sender_address,
            to     : recipient,
        };
        event::emit<TransferEvent>(transfer_event);
    }

    public entry fun update_claimable_fees(_account: address, _pool_object: Object<LiquidityPool>) {
        abort 0
    }

    #[test_only]
    public fun create_test(first_metadata: Object<fungible_asset::Metadata>, second_metadata: Object<fungible_asset::Metadata>, is_stable: bool) : Object<LiquidityPool> acquires LiquidityPoolConfigs {
        create(first_metadata, second_metadata, is_stable)
    }

    #[test_only]
    public fun mint_lp_test(signer_ref: &signer, asset1: FungibleAsset, asset2: FungibleAsset, is_stable: bool) : u64 acquires FeesAccounting, LiquidityPool {
        mint_lp(signer_ref, asset1, asset2, is_stable)
    }

    #[test_only]
    public fun swap_test(liquidity_pool: Object<LiquidityPool>, input_asset: FungibleAsset) : FungibleAsset acquires FeesAccounting, LiquidityPool, LiquidityPoolConfigs {
        swap(liquidity_pool, input_asset)
    }

    #[test_only]
    public fun burn_test(signer_ref: &signer, first_metadata: Object<fungible_asset::Metadata>, second_metadata: Object<fungible_asset::Metadata>, is_stable: bool, lp_amount: u64) : (FungibleAsset, FungibleAsset) acquires LiquidityPool {
        burn(signer_ref, first_metadata, second_metadata, is_stable, lp_amount)
    }

    #[test_only]
    public fun claim_fees_test(_signer_ref: &signer, liquidity_pool_object: Object<LiquidityPool>) : (FungibleAsset, FungibleAsset) acquires LiquidityPool {
        claim_fees(_signer_ref, liquidity_pool_object)
    }
}