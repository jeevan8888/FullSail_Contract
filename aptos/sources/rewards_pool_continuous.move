module fullsail::rewards_pool_continuous {
    use aptos_framework::object::{Self, Object};
    use aptos_framework::fungible_asset;
    use aptos_framework::smart_table::{Self, SmartTable};
    use aptos_framework::dispatchable_fungible_asset;
    use aptos_framework::timestamp;
    use aptos_framework::math64;
    use aptos_framework::error;

    // --- friends modules ---
    friend fullsail::gauge; 
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
    struct RewardsPool has key {
        extend_ref: object::ExtendRef,
        reward_per_token_stored: u128,
        user_reward_per_token_paid: SmartTable<address, u128>,
        last_update_time: u64,
        reward_rate: u128,
        reward_duration: u64,
        reward_period_finish: u64,
        rewards: SmartTable<address, u64>,
        total_stake: u128,
        stakes: SmartTable<address, u64>,
    }

    public(friend) fun add_rewards(pool: Object<RewardsPool>, asset: fungible_asset::FungibleAsset) acquires RewardsPool {
        update_reward(@0x0, pool);
        let asset_amount = fungible_asset::amount(&asset);
        dispatchable_fungible_asset::deposit<RewardsPool>(pool, asset);
        let current_time = timestamp::now_seconds();
        let pool_ref = borrow_global_mut<RewardsPool>(object::object_address<RewardsPool>(&pool));
        let pending_reward = if (pool_ref.reward_period_finish > current_time) {
            pool_ref.reward_rate * ((pool_ref.reward_period_finish - current_time) as u128)
        } else {
            0
        };
        pool_ref.reward_rate = (pending_reward + (asset_amount as u128) * 100000000) / (pool_ref.reward_duration as u128);
        pool_ref.reward_period_finish = current_time + pool_ref.reward_duration;
        pool_ref.last_update_time = current_time;
    }

    public(friend) fun claim_rewards(user_address: address, pool: Object<RewardsPool>) : fungible_asset::FungibleAsset acquires RewardsPool {
        update_reward(user_address, pool);
        let pool_ref = borrow_global_mut<RewardsPool>(object::object_address<RewardsPool>(&pool));
        let default_reward_value = 0;
        let user_reward_amount = *smart_table::borrow_with_default<address, u64>(&mut pool_ref.rewards, user_address, &default_reward_value);
        assert!(user_reward_amount > 0, E_MAX_LOCK_TIME);
        smart_table::upsert<address, u64>(&mut pool_ref.rewards, user_address, 0);
        let user_signer = fullsail::package_manager::get_signer();
        dispatchable_fungible_asset::withdraw<RewardsPool>(&user_signer, pool, user_reward_amount)
    }

    fun claimable_internal(user_address: address, pool_ref: &RewardsPool) : u64 {
        let default_stake_value = 0;
        let default_reward_value = 0;
        let scale_factor = 100000000;
        assert!(scale_factor != 0, error::invalid_argument(E_ZERO_TOTAL_POWER));
        let user_rewards = 0;
        (((((*smart_table::borrow_with_default<address, u64>(&pool_ref.stakes, user_address, &default_stake_value) as u128) as u256) * ((reward_per_token_internal(pool_ref) - *smart_table::borrow_with_default<address, u128>(&pool_ref.user_reward_per_token_paid, user_address, &default_reward_value)) as u256) / (scale_factor as u256)) as u128) as u64) + *smart_table::borrow_with_default<address, u64>(&pool_ref.rewards, user_address, &user_rewards)
    }

    public fun claimable_rewards(user_address: address, pool: Object<RewardsPool>) : u64 acquires RewardsPool {
        claimable_internal(user_address, borrow_global<RewardsPool>(object::object_address<RewardsPool>(&pool)))
    }

    public(friend) fun create(metadata: Object<fungible_asset::Metadata>, duration: u64) : Object<RewardsPool> {
        assert!(duration > 0, E_NOT_OWNER);
        let user_signer = fullsail::package_manager::get_signer();
        let rewards_pool_ref = object::create_object_from_account(&user_signer);
        let rewards_pool_address = &rewards_pool_ref;
        fungible_asset::create_store<fungible_asset::Metadata>(rewards_pool_address, metadata);
        let signer_address = object::generate_signer(rewards_pool_address);
        let new_rewards_pool = RewardsPool{
            extend_ref                 : object::generate_extend_ref(rewards_pool_address),
            reward_per_token_stored    : 0,
            user_reward_per_token_paid : smart_table::new<address, u128>(),
            last_update_time           : 0,
            reward_rate                : 0,
            reward_duration            : duration,
            reward_period_finish       : 0,
            rewards                    : smart_table::new<address, u64>(),
            total_stake                : 0,
            stakes                     : smart_table::new<address, u64>(),
        };
        move_to<RewardsPool>(&signer_address, new_rewards_pool);
        object::object_from_constructor_ref<RewardsPool>(rewards_pool_address)
    }

    public fun current_reward_period_finish(pool: Object<RewardsPool>) : u64 acquires RewardsPool {
        borrow_global<RewardsPool>(object::object_address<RewardsPool>(&pool)).reward_period_finish
    }

    public fun reward_per_token(pool: Object<RewardsPool>) : u128 acquires RewardsPool {
        reward_per_token_internal(borrow_global<RewardsPool>(object::object_address<RewardsPool>(&pool)))
    }

    fun reward_per_token_internal(pool_ref: &RewardsPool) : u128 {
        let stored_reward = pool_ref.reward_per_token_stored;
        let adjusted_reward = stored_reward;
        let total_stake_amount = pool_ref.total_stake;
        if (total_stake_amount > 0) {
            assert!(total_stake_amount != 0, error::invalid_argument(E_ZERO_TOTAL_POWER));
            adjusted_reward = stored_reward + (((((math64::min(timestamp::now_seconds(), pool_ref.reward_period_finish) - pool_ref.last_update_time) as u128) as u256) * (pool_ref.reward_rate as u256) / (total_stake_amount as u256)) as u128);
        };
        adjusted_reward
    }

    public fun reward_rate(pool: Object<RewardsPool>) : u128 acquires RewardsPool {
        borrow_global<RewardsPool>(object::object_address<RewardsPool>(&pool)).reward_rate / 100000000
    }

    public(friend) fun stake(user_address: address, pool: Object<RewardsPool>, stake_amount: u64) acquires RewardsPool {
        update_reward(user_address, pool);
        let pool_ref = borrow_global_mut<RewardsPool>(object::object_address<RewardsPool>(&pool));
        let user_stake_amount = smart_table::borrow_mut_with_default<address, u64>(&mut pool_ref.stakes, user_address, 0);
        *user_stake_amount = *user_stake_amount + stake_amount;
        pool_ref.total_stake = pool_ref.total_stake + (stake_amount as u128);
    }

    public fun stake_balance(user_address: address, pool: Object<RewardsPool>) : u64 acquires RewardsPool {
        let default_stake_value = 0;
        *smart_table::borrow_with_default<address, u64>(&borrow_global<RewardsPool>(object::object_address<RewardsPool>(&pool)).stakes, user_address, &default_stake_value)
    }

    public fun total_stake(pool: Object<RewardsPool>) : u128 acquires RewardsPool {
        borrow_global<RewardsPool>(object::object_address<RewardsPool>(&pool)).total_stake
    }

    public fun total_unclaimed_rewards(pool: Object<RewardsPool>) : u64 {
        fungible_asset::balance<RewardsPool>(pool)
    }

    public(friend) fun unstake(user_address: address, pool: Object<RewardsPool>, stake_amount: u64) acquires RewardsPool {
        update_reward(user_address, pool);
        let pool_ref = borrow_global_mut<RewardsPool>(object::object_address<RewardsPool>(&pool));
        assert!(smart_table::contains<address, u64>(&pool_ref.stakes, user_address), E_MIN_LOCK_TIME);
        let user_stake_amount = smart_table::borrow_mut_with_default<address, u64>(&mut pool_ref.stakes, user_address, 0);
        assert!(stake_amount > 0 && stake_amount <= *user_stake_amount, E_INSUFFICIENT_BALANCE);
        *user_stake_amount = *user_stake_amount - stake_amount;
        pool_ref.total_stake = pool_ref.total_stake - (stake_amount as u128);
        if (*user_stake_amount == 0) {
            smart_table::remove<address, u64>(&mut pool_ref.stakes, user_address);
            smart_table::remove<address, u128>(&mut pool_ref.user_reward_per_token_paid, user_address);
        };
    }

    fun update_reward(user_address: address, pool: Object<RewardsPool>) acquires RewardsPool {
        let pool_ref = borrow_global_mut<RewardsPool>(object::object_address<RewardsPool>(&pool));
        pool_ref.reward_per_token_stored = reward_per_token_internal(pool_ref);
        pool_ref.last_update_time = math64::min(timestamp::now_seconds(), pool_ref.reward_period_finish);
        let claimable_amount = claimable_internal(user_address, pool_ref);
        if (claimable_amount > 0) {
            smart_table::upsert<address, u64>(&mut pool_ref.rewards, user_address, claimable_amount);
        };
        smart_table::upsert<address, u128>(&mut pool_ref.user_reward_per_token_paid, user_address, pool_ref.reward_per_token_stored);
    }

    #[test_only]
    public fun add_rewards_test(pool: Object<RewardsPool>, asset: fungible_asset::FungibleAsset) acquires RewardsPool {
        add_rewards(pool, asset);
    }

    #[test_only]
    public fun create_test(metadata: Object<fungible_asset::Metadata>, duration: u64) : Object<RewardsPool> { 
        let rewards_pool = create(metadata, duration);
        rewards_pool
    }

    #[test_only]
    public fun stake_test(user_address: address, pool: Object<RewardsPool>, stake_amount: u64)  acquires RewardsPool {
        stake(user_address, pool, stake_amount);
    }

    #[test_only]
    public fun claim_rewards_test(user_address: address, pool: Object<RewardsPool>) : fungible_asset::FungibleAsset acquires RewardsPool {
        claim_rewards(user_address, pool)
    }

    #[test_only]
    public fun unstake_test(user_address: address, pool: Object<RewardsPool>, stake_amount: u64) acquires RewardsPool{
        unstake(user_address, pool, stake_amount);
    }
}