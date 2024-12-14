module fullsail::gauge {
    use aptos_framework::event;
    use fullsail::liquidity_pool::{Self, LiquidityPool};
    use fullsail::rewards_pool_continuous;
    use aptos_framework::fungible_asset;
    use aptos_framework::object::{Self, Object};
    use aptos_framework::signer;

    // --- friends modules ---
    friend fullsail::vote_manager;
    friend fullsail::router;

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
    struct Gauge has key {
        rewards_pool: Object<rewards_pool_continuous::RewardsPool>,
        extend_ref: object::ExtendRef,
        liquidity_pool: Object<LiquidityPool>,
    }

    // --- events ---
    #[event]
    struct StakeEvent has drop, store {
        lp: address,
        gauge: Object<Gauge>,
        amount: u64,
    }

    #[event]
    struct UnstakeEvent has drop, store {
        lp: address,
        gauge: Object<Gauge>,
        amount: u64,
    }

    public fun liquidity_pool(gauge: Object<Gauge>): Object<LiquidityPool> acquires Gauge {
        borrow_global<Gauge>(object::object_address<Gauge>(&gauge)).liquidity_pool
    }

    public(friend) fun claim_fees(gauge: Object<Gauge>): (fungible_asset::FungibleAsset, fungible_asset::FungibleAsset) acquires Gauge {
        let signer = object::generate_signer_for_extending(&borrow_global<Gauge>(object::object_address<Gauge>(&gauge)).extend_ref);
        let pool = liquidity_pool(gauge);
        liquidity_pool::claim_fees(&signer, pool)
    }

    public(friend) fun add_rewards(gauge: Object<Gauge>, rewards: fungible_asset::FungibleAsset) acquires Gauge {
        let pool = rewards_pool(gauge);
        rewards_pool_continuous::add_rewards(pool, rewards);
    }

    public(friend) fun claim_rewards(signer: &signer, gauge: Object<Gauge>): fungible_asset::FungibleAsset acquires Gauge {
        let pool = rewards_pool(gauge);
        rewards_pool_continuous::claim_rewards(signer::address_of(signer), pool)
    }

    public fun claimable_rewards(account: address, gauge: Object<Gauge>): u64 acquires Gauge {
        let pool = rewards_pool(gauge);
        rewards_pool_continuous::claimable_rewards(account, pool)
    }

    public(friend) fun create(pool: Object<LiquidityPool>): Object<Gauge> {
        let signer = fullsail::package_manager::get_signer();
        let gauge_obj = object::create_object_from_account(&signer);
        fungible_asset::create_store<LiquidityPool>(&gauge_obj, pool);
        let gauge = Gauge {
            rewards_pool: rewards_pool_continuous::create(object::convert<fullsail::cellana_token::CellanaToken, fungible_asset::Metadata>(fullsail::cellana_token::token()), rewards_duration()),
            extend_ref: object::generate_extend_ref(&gauge_obj),
            liquidity_pool: pool,
        };
        move_to<Gauge>(&object::generate_signer(&gauge_obj), gauge);
        object::object_from_constructor_ref<Gauge>(&gauge_obj)
    }

    public entry fun stake(signer: &signer, gauge: Object<Gauge>, amount: u64) acquires Gauge {
        let pool = liquidity_pool(gauge);
        liquidity_pool::transfer(signer, object::convert<LiquidityPool, LiquidityPool>(pool), object::object_address<Gauge>(&gauge), amount);
        let account = signer::address_of(signer);
        let pool_rewards = rewards_pool(gauge);
        rewards_pool_continuous::stake(account, pool_rewards, amount);
        event::emit<StakeEvent>(StakeEvent { lp: account, gauge: gauge, amount: amount });
    }

    public fun stake_balance(account: address, gauge: Object<Gauge>): u64 acquires Gauge {
        let pool = rewards_pool(gauge);
        rewards_pool_continuous::stake_balance(account, pool)
    }

    public fun total_stake(gauge: Object<Gauge>): u128 acquires Gauge {
        let pool = rewards_pool(gauge);
        rewards_pool_continuous::total_stake(pool)
    }

    public(friend) fun unstake_lp(signer: &signer, gauge: Object<Gauge>, amount: u64) acquires Gauge {
        let account = signer::address_of(signer);
        let signer_for_extending = object::generate_signer_for_extending(&borrow_global<Gauge>(object::object_address<Gauge>(&gauge)).extend_ref);
        let pool = liquidity_pool(gauge);
        liquidity_pool::transfer(&signer_for_extending, pool, account, amount);
        let rewards_pool = rewards_pool(gauge);
        assert!(rewards_pool_continuous::stake_balance(account, rewards_pool) >= amount, E_INSUFFICIENT_BALANCE);
        rewards_pool_continuous::unstake(account, rewards_pool, amount);
        event::emit<UnstakeEvent>(UnstakeEvent { lp: account, gauge: gauge, amount: amount });
    }

    public fun rewards_pool(gauge: Object<Gauge>): Object<rewards_pool_continuous::RewardsPool> acquires Gauge {
        borrow_global<Gauge>(object::object_address<Gauge>(&gauge)).rewards_pool
    }

    public fun stake_token(gauge: Object<Gauge>): Object<fungible_asset::Metadata> acquires Gauge {
        object::convert<LiquidityPool, fungible_asset::Metadata>(borrow_global<Gauge>(object::object_address<Gauge>(&gauge)).liquidity_pool)
    }

    public fun rewards_duration(): u64 {
        604800
    }

    #[test_only]
    public fun create_test(pool: Object<LiquidityPool>): Object<Gauge> {
        create(pool)
    }

    #[test_only]
    public fun unstake_lp_test(signer: &signer, gauge: Object<Gauge>, amount: u64) acquires Gauge {
        unstake_lp(signer, gauge, amount);
    }

    #[test_only]
    public fun claim_rewards_test(signer: &signer, gauge: Object<Gauge>): fungible_asset::FungibleAsset acquires Gauge {
        claim_rewards(signer, gauge)
    }
}