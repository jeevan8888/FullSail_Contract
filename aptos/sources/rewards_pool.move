module fullsail::rewards_pool {
    use aptos_framework::object::{Self, Object};
    use aptos_framework::simple_map::{Self, SimpleMap};
    use aptos_framework::smart_table::{Self, SmartTable};
    use aptos_framework::vector;
    use aptos_framework::fungible_asset::{Self, FungibleStore, Metadata, FungibleAsset};
    use aptos_framework::dispatchable_fungible_asset;
    use aptos_framework::pool_u64_unbound::{Self, Pool};
    use fullsail::package_manager;
    use fullsail::liquidity_pool;
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
    struct EpochRewards has store {
        total_amounts: SimpleMap<Object<Metadata>, u64>,
        reward_tokens: vector<Object<Metadata>>,
        non_default_reward_tokens_count: u64,
        claimer_pool: Pool,
    }

    struct RewardStore has store {
        store: Object<FungibleStore>,
        store_extend_ref: object::ExtendRef,
    }

    struct RewardsPool has key {
        epoch_rewards: SmartTable<u64, EpochRewards>,
        reward_stores: SmartTable<Object<Metadata>, RewardStore>,
        default_reward_tokens: vector<Object<Metadata>>,
    }

    public(friend) fun create(reward_tokens_list: vector<Object<Metadata>>) : Object<RewardsPool> {
        let signer_address = package_manager::get_signer();
        let rewards_pool_object = object::create_object_from_account(&signer_address);
        let rewards_pool_ref = &rewards_pool_object;
        let signer_for_rewards_pool = object::generate_signer(rewards_pool_ref);
        let reward_store_table = smart_table::new<Object<Metadata>, RewardStore>();
        vector::reverse<Object<Metadata>>(&mut reward_tokens_list);
        let reward_tokens_length = vector::length<Object<Metadata>>(&reward_tokens_list);
        while (reward_tokens_length > 0) {
            let reward_token = vector::pop_back<Object<Metadata>>(&mut reward_tokens_list);
            let token_signer_address = package_manager::get_signer();
            let token_store_object = object::create_object_from_account(&token_signer_address);
            let token_store_ref = &token_store_object;
            let reward_store = RewardStore{
                store            : fungible_asset::create_store<Metadata>(token_store_ref, reward_token),
                store_extend_ref : object::generate_extend_ref(token_store_ref),
            };
            smart_table::add<Object<Metadata>, RewardStore>(&mut reward_store_table, reward_token, reward_store);
            reward_tokens_length = reward_tokens_length - 1;
        };
        vector::destroy_empty<Object<Metadata>>(reward_tokens_list);
        let rewards_pool = RewardsPool{
            epoch_rewards         : smart_table::new<u64, EpochRewards>(),
            reward_stores         : reward_store_table,
            default_reward_tokens : reward_tokens_list,
        };
        move_to<RewardsPool>(&signer_for_rewards_pool, rewards_pool);
        object::object_from_constructor_ref<RewardsPool>(rewards_pool_ref)
    }

    public(friend) fun add_rewards(rewards_pool_object: Object<RewardsPool>, fungible_assets: vector<FungibleAsset>, epoch_id: u64) acquires RewardsPool {
        let default_tokens = default_reward_tokens(rewards_pool_object);
        let default_tokens_ref = &default_tokens;
        let rewards_pool_ref = borrow_global_mut<RewardsPool>(object::object_address<RewardsPool>(&rewards_pool_object));
        let reward_store_table_ref = &mut rewards_pool_ref.reward_stores;
        vector::reverse<FungibleAsset>(&mut fungible_assets);
        let fungible_assets_length = vector::length<FungibleAsset>(&fungible_assets);
        while (fungible_assets_length > 0) {
            let fungible_asset = vector::pop_back<FungibleAsset>(&mut fungible_assets);
            let asset_amount = fungible_asset::amount(&fungible_asset);
            if (asset_amount == 0) {
                fungible_asset::destroy_zero(fungible_asset);
            } else {
                let asset_metadata = fungible_asset::metadata_from_asset(&fungible_asset);
                let epoch_rewards_table_ref = &mut rewards_pool_ref.epoch_rewards;
                if (!smart_table::contains<u64, EpochRewards>(epoch_rewards_table_ref, epoch_id)) {
                    let new_epoch_rewards = EpochRewards{
                        total_amounts                   : simple_map::new<Object<Metadata>, u64>(),
                        reward_tokens                   : vector::empty<Object<Metadata>>(),
                        non_default_reward_tokens_count : 0,
                        claimer_pool                    : pool_u64_unbound::create(),
                    };
                    smart_table::add<u64, EpochRewards>(epoch_rewards_table_ref, epoch_id, new_epoch_rewards);
                };
                let current_epoch_rewards = smart_table::borrow_mut<u64, EpochRewards>(epoch_rewards_table_ref, epoch_id);
                let total_amounts_ref = &mut current_epoch_rewards.total_amounts;
                if (!simple_map::contains_key<Object<Metadata>, u64>(total_amounts_ref, &asset_metadata)) {
                    let reward_tokens_ref = &mut current_epoch_rewards.reward_tokens;
                    if (!vector::contains<Object<Metadata>>(default_tokens_ref, &asset_metadata)) {
                        assert!(current_epoch_rewards.non_default_reward_tokens_count < 15, E_ZERO_AMOUNT);
                        current_epoch_rewards.non_default_reward_tokens_count = current_epoch_rewards.non_default_reward_tokens_count + 1;
                    };
                    simple_map::add<Object<Metadata>, u64>(total_amounts_ref, asset_metadata, 0);
                    vector::push_back<Object<Metadata>>(reward_tokens_ref, asset_metadata);
                };
                if (!smart_table::contains<Object<Metadata>, RewardStore>(reward_store_table_ref, asset_metadata)) {
                    let token_signer_address = package_manager::get_signer();
                    let token_store_object = object::create_object_from_account(&token_signer_address);
                    let token_store_ref = &token_store_object;
                    let reward_store = RewardStore{
                        store            : fungible_asset::create_store<Metadata>(token_store_ref, asset_metadata),
                        store_extend_ref : object::generate_extend_ref(token_store_ref),
                    };
                    smart_table::add<Object<Metadata>, RewardStore>(reward_store_table_ref, asset_metadata, reward_store);
                };
                liquidity_pool::dispatchable_exact_deposit<FungibleStore>(smart_table::borrow<Object<Metadata>, RewardStore>(reward_store_table_ref, asset_metadata).store, fungible_asset);
                let total_amount = simple_map::borrow_mut<Object<Metadata>, u64>(total_amounts_ref, &asset_metadata);
                *total_amount = *total_amount + asset_amount;
            };
            fungible_assets_length = fungible_assets_length - 1;
        };
        vector::destroy_empty<FungibleAsset>(fungible_assets);
    }

    public(friend) fun claim_rewards(user_address: address, rewards_pool_object: Object<RewardsPool>, epoch_id: u64) : vector<FungibleAsset> acquires RewardsPool {
        assert!(epoch_id < epoch::now(), E_INVALID_EPOCH);
        let reward_tokens_list = reward_tokens(rewards_pool_object, epoch_id);
        let claimed_assets = vector::empty<FungibleAsset>();
        let rewards_pool_ref = borrow_global_mut<RewardsPool>(object::object_address<RewardsPool>(&rewards_pool_object));
        vector::reverse<Object<Metadata>>(&mut reward_tokens_list);
        let reward_tokens_length = vector::length<Object<Metadata>>(&reward_tokens_list);
        while (reward_tokens_length > 0) {
            let reward_token = vector::pop_back<Object<Metadata>>(&mut reward_tokens_list);
            let rewards_amount = rewards(user_address, rewards_pool_ref, reward_token, epoch_id);
            let reward_store_ref = smart_table::borrow<Object<Metadata>, RewardStore>(&rewards_pool_ref.reward_stores, reward_token);
            if (rewards_amount == 0) {
                vector::push_back<FungibleAsset>(&mut claimed_assets, fungible_asset::zero<Metadata>(fungible_asset::store_metadata<FungibleStore>(reward_store_ref.store)));
            } else {
                let asset_signer = object::generate_signer_for_extending(&reward_store_ref.store_extend_ref);
                vector::push_back<FungibleAsset>(&mut claimed_assets, dispatchable_fungible_asset::withdraw<FungibleStore>(&asset_signer, reward_store_ref.store, rewards_amount));
                let total_amount_ref = simple_map::borrow_mut<Object<Metadata>, u64>(&mut smart_table::borrow_mut<u64, EpochRewards>(&mut rewards_pool_ref.epoch_rewards, epoch_id).total_amounts, &reward_token);
                *total_amount_ref = *total_amount_ref - rewards_amount;
            };
            reward_tokens_length = reward_tokens_length - 1;
        };
        vector::destroy_empty<Object<Metadata>>(reward_tokens_list);
        if (smart_table::contains<u64, EpochRewards>(&rewards_pool_ref.epoch_rewards, epoch_id)) {
            let current_epoch_rewards = smart_table::borrow_mut<u64, EpochRewards>(&mut rewards_pool_ref.epoch_rewards, epoch_id);
            let user_shares = pool_u64_unbound::shares(&current_epoch_rewards.claimer_pool, user_address);
            if (user_shares > 0) {
                pool_u64_unbound::redeem_shares(&mut current_epoch_rewards.claimer_pool, user_address, user_shares);
            };
        };
        claimed_assets
    }

    public fun default_reward_tokens(rewards_pool: Object<RewardsPool>) : vector<Object<fungible_asset::Metadata>> acquires RewardsPool {
        borrow_global<RewardsPool>(object::object_address<RewardsPool>(&rewards_pool)).default_reward_tokens
    }

    public fun reward_tokens(rewards_pool: Object<RewardsPool>, amount: u64) : vector<Object<fungible_asset::Metadata>> acquires RewardsPool {
        let rewards_pool = borrow_global<RewardsPool>(object::object_address<RewardsPool>(&rewards_pool));
        if (!smart_table::contains<u64, EpochRewards>(&rewards_pool.epoch_rewards, amount)) {
            return vector::empty<Object<fungible_asset::Metadata>>()
        };
        smart_table::borrow<u64, EpochRewards>(&rewards_pool.epoch_rewards, amount).reward_tokens
    }

    fun rewards(user_address: address, rewards_pool_ref: &RewardsPool, reward_token: Object<fungible_asset::Metadata>, epoch_id: u64) : u64 {
        if (!smart_table::contains<u64, EpochRewards>(&rewards_pool_ref.epoch_rewards, epoch_id)) {
            return 0
        };
        let epoch_rewards = smart_table::borrow<u64, EpochRewards>(&rewards_pool_ref.epoch_rewards, epoch_id);
        let reward_amount = if (simple_map::contains_key<Object<fungible_asset::Metadata>, u64>(&epoch_rewards.total_amounts, &reward_token)) {
            *simple_map::borrow<Object<fungible_asset::Metadata>, u64>(&epoch_rewards.total_amounts, &reward_token)
        } else {
            0
        };
        pool_u64_unbound::shares_to_amount_with_total_coins(&epoch_rewards.claimer_pool, pool_u64_unbound::shares(&epoch_rewards.claimer_pool, user_address), reward_amount)
    }

    public fun claimable_rewards(user_address: address, rewards_pool: Object<RewardsPool>, epoch_id: u64) : SimpleMap<Object<fungible_asset::Metadata>, u64> acquires RewardsPool {
        assert!(epoch_id < fullsail::epoch::now(), E_INVALID_EPOCH);
        let reward_tokens_list = reward_tokens(rewards_pool, epoch_id);
        let rewards_pool_ref = borrow_global<RewardsPool>(object::object_address<RewardsPool>(&rewards_pool));
        let tokens_vector = &reward_tokens_list;
        let claimable_amounts = vector[];
        let index = 0;

        while (index < vector::length<Object<fungible_asset::Metadata>>(tokens_vector)) {
            vector::push_back<u64>(&mut claimable_amounts, rewards(user_address, rewards_pool_ref, *vector::borrow<Object<fungible_asset::Metadata>>(tokens_vector, index), epoch_id));
            index = index + 1;
        };

        simple_map::new_from<Object<fungible_asset::Metadata>, u64>(reward_tokens_list, claimable_amounts)
    }

    public fun claimer_shares(user_address: address, rewards_pool: Object<RewardsPool>, epoch_id: u64) : (u64, u64) acquires RewardsPool {
        let epoch_rewards_ref = smart_table::borrow<u64, EpochRewards>(&borrow_global<RewardsPool>(object::object_address<RewardsPool>(&rewards_pool)).epoch_rewards, epoch_id);
        ((pool_u64_unbound::shares(&epoch_rewards_ref.claimer_pool, user_address) as u64), (pool_u64_unbound::total_shares(&epoch_rewards_ref.claimer_pool) as u64))
    }

    public(friend) fun decrease_allocation(user_address: address, rewards_pool: Object<RewardsPool>, amount: u64) acquires RewardsPool {
        let rewards_pool_mut_ref = &mut borrow_global_mut<RewardsPool>(object::object_address<RewardsPool>(&rewards_pool)).epoch_rewards;
        let current_epoch = fullsail::epoch::now();
        if (!smart_table::contains<u64, EpochRewards>(rewards_pool_mut_ref, current_epoch)) {
            let new_epoch_rewards = EpochRewards{
                total_amounts                   : simple_map::new<Object<fungible_asset::Metadata>, u64>(),
                reward_tokens                   : vector::empty<Object<fungible_asset::Metadata>>(),
                non_default_reward_tokens_count : 0,
                claimer_pool                    : pool_u64_unbound::create(),
            };
            smart_table::add<u64, EpochRewards>(rewards_pool_mut_ref, current_epoch, new_epoch_rewards);
        };
        pool_u64_unbound::redeem_shares(&mut smart_table::borrow_mut<u64, EpochRewards>(rewards_pool_mut_ref, current_epoch).claimer_pool, user_address, (amount as u128));
    }

    public(friend) fun increase_allocation(user_address: address, rewards_pool: Object<RewardsPool>, amount: u64) acquires RewardsPool {
        let rewards_pool_mut_ref = &mut borrow_global_mut<RewardsPool>(object::object_address<RewardsPool>(&rewards_pool)).epoch_rewards;
        let current_epoch = fullsail::epoch::now();
        if (!smart_table::contains<u64, EpochRewards>(rewards_pool_mut_ref, current_epoch)) {
            let new_epoch_rewards = EpochRewards{
                total_amounts                   : simple_map::new<Object<fungible_asset::Metadata>, u64>(),
                reward_tokens                   : vector::empty<Object<fungible_asset::Metadata>>(),
                non_default_reward_tokens_count : 0,
                claimer_pool                    : pool_u64_unbound::create(),
            };
            smart_table::add<u64, EpochRewards>(rewards_pool_mut_ref, current_epoch, new_epoch_rewards);
        };
        pool_u64_unbound::buy_in(&mut smart_table::borrow_mut<u64, EpochRewards>(rewards_pool_mut_ref, current_epoch).claimer_pool, user_address, amount);
    }

    public fun total_rewards(rewards_pool: Object<RewardsPool>, epoch_id: u64) : SimpleMap<Object<fungible_asset::Metadata>, u64> acquires RewardsPool {
        let rewards_pool_ref = borrow_global<RewardsPool>(object::object_address<RewardsPool>(&rewards_pool));
        if (!smart_table::contains<u64, EpochRewards>(&rewards_pool_ref.epoch_rewards, epoch_id)) {
            return simple_map::new<Object<fungible_asset::Metadata>, u64>()
        };
        smart_table::borrow<u64, EpochRewards>(&rewards_pool_ref.epoch_rewards, epoch_id).total_amounts
    }

    #[test_only]
    public fun create_test(reward_tokens_list: vector<Object<Metadata>>) : Object<RewardsPool> {
        create(reward_tokens_list)
    }

    #[test_only]
    public fun add_rewards_test(rewards_pool_object: Object<RewardsPool>, fungible_assets: vector<FungibleAsset>, epoch_id: u64) acquires RewardsPool {
        add_rewards(rewards_pool_object, fungible_assets, epoch_id);
    }

    #[test_only]
    public fun claim_rewards_test(user_address: address, rewards_pool_object: Object<RewardsPool>, epoch_id: u64) : vector<FungibleAsset> acquires RewardsPool {
        claim_rewards(user_address, rewards_pool_object, epoch_id)
    }

    #[test_only]
    public fun increase_allocation_test(user_address: address, rewards_pool: Object<RewardsPool>, amount: u64) acquires RewardsPool {
        increase_allocation(user_address, rewards_pool, amount);
    }

    #[test_only]
    public fun decrease_allocation_test(user_address: address, rewards_pool: Object<RewardsPool>, amount: u64) acquires RewardsPool {
        decrease_allocation(user_address, rewards_pool, amount);
    }
}