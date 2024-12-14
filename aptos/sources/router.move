module fullsail::router {
    use std::vector;
    use std::error;
    use aptos_framework::object::{Self, Object};
    use aptos_framework::fungible_asset::{Self, FungibleAsset, Metadata};
    use aptos_framework::primary_fungible_store;
    use aptos_framework::coin::{Self, Coin};
    use aptos_framework::aptos_account;
    use fullsail::liquidity_pool::{Self, LiquidityPool};
    use fullsail::coin_wrapper;
    use fullsail::gauge;
    use fullsail::vote_manager;

    // --- errors ---
    const E_INSUFFICIENT_OUTPUT_AMOUNT: u64 = 1;
    const E_INSUFFICIENT_WITHDRAWN_AMOUNT: u64 = 2;
    const E_DEPOSIT_AMOUNT_MISMATCH: u64 = 3;
    const E_WITHDRAW_AMOUNT_MISMATCH: u64 = 4;
    const E_VECTOR_LENGTH_MISMATCH: u64 = 5;
    const E_VECTOR_LENGTH_MISMATCH_INTERNAL: u64 = 6;
    const E_ZERO_AMOUNT: u64 = 7;
    const E_ZERO_RESERVE: u64 = 8;
    const E_OUTPUT_IS_WRAPPER: u64 =9;
    const E_OTHER_ASSET_IS_WRAPPER: u64 = 10;
    const E_ASSETS_ARE_WRAPPERS: u64 = 11;

    public fun swap(
        input_asset: FungibleAsset,
        min_output_amount: u64,
        output_metadata: Object<Metadata>,
        stable: bool
    ): FungibleAsset {
        let pool = liquidity_pool::liquidity_pool(fungible_asset::asset_metadata(&input_asset), output_metadata, stable);
        let output_asset = liquidity_pool::swap(pool, input_asset);

        assert!(fungible_asset::amount(&output_asset) >= min_output_amount, E_INSUFFICIENT_OUTPUT_AMOUNT);
        output_asset
    }

    public fun get_amount_out(amount_in: u64, token_in_metadata: Object<Metadata>, token_out_metadata: Object<Metadata>, stable: bool): (u64, u64) {
        liquidity_pool::get_amount_out(
            liquidity_pool::liquidity_pool(token_in_metadata, token_out_metadata, stable),
            token_in_metadata,
            amount_in
        )
    }

    public fun get_trade_diff(amount_in: u64, token_in_metadata: Object<Metadata>, token_out_metadata: Object<Metadata>, stable: bool): (u64, u64) {
        liquidity_pool::get_trade_diff(
            liquidity_pool::liquidity_pool(token_in_metadata, token_out_metadata, stable),
            token_in_metadata,
            amount_in
        )
    }

    public fun add_liquidity(_account: &signer, _asset_a: FungibleAsset, _asset_b: FungibleAsset, _stable: bool) {
        abort 0
    }

    public entry fun add_liquidity_and_stake_both_coins_entry<CoinTypeA, CoinTypeB>(
        account: &signer,
        stable: bool,
        amount_a: u64,
        amount_b: u64
    ) {
        let (optimal_a, optimal_b) = get_optimal_amounts(
            coin_wrapper::get_wrapper<CoinTypeA>(),
            coin_wrapper::get_wrapper<CoinTypeB>(),
            stable,
            amount_a,
            amount_b
        );

        let pool = liquidity_pool::liquidity_pool(
            coin_wrapper::get_wrapper<CoinTypeA>(),
            coin_wrapper::get_wrapper<CoinTypeB>(),
            stable
        );

        let lp_tokens = liquidity_pool::mint_lp(
            account,
            coin_wrapper::wrap<CoinTypeA>(coin::withdraw<CoinTypeA>(account, optimal_a)),
            coin_wrapper::wrap<CoinTypeB>(coin::withdraw<CoinTypeB>(account, optimal_b)),
            stable
        );

        gauge::stake(account, vote_manager::get_gauge(pool), lp_tokens);
    }

    public entry fun add_liquidity_and_stake_coin_entry<CoinType>(
        account: &signer,
        other_metadata: Object<Metadata>,
        stable: bool,
        amount_a: u64,
        amount_b: u64
    ) {
        let (optimal_a, optimal_b) = get_optimal_amounts(coin_wrapper::get_wrapper<CoinType>(), other_metadata, stable, amount_a, amount_b);
        let asset_b = exact_withdraw<Metadata>(account, other_metadata, optimal_b);
        
        assert!(optimal_b == fungible_asset::amount(&asset_b), E_INSUFFICIENT_WITHDRAWN_AMOUNT);
        
        fullsail::gauge::stake(
            account,
            fullsail::vote_manager::get_gauge(fullsail::liquidity_pool::liquidity_pool(coin_wrapper::get_wrapper<CoinType>(), other_metadata, stable)),
            fullsail::liquidity_pool::mint_lp(account, coin_wrapper::wrap<CoinType>(coin::withdraw<CoinType>(account, optimal_a)), asset_b, stable)
        );
    }

    public entry fun add_liquidity_and_stake_entry(
        account: &signer,
        metadata_a: Object<Metadata>,
        metadata_b: Object<Metadata>,
        stable: bool,
        amount_a: u64,
        amount_b: u64
    ) {
        let (optimal_a, optimal_b) = get_optimal_amounts(metadata_a, metadata_b, stable, amount_a, amount_b);
        let asset_a = exact_withdraw<Metadata>(account, metadata_a, optimal_a);
        assert!(optimal_a == fungible_asset::amount(&asset_a), E_INSUFFICIENT_WITHDRAWN_AMOUNT);
        
        let asset_b = exact_withdraw<Metadata>(account, metadata_b, optimal_b);
        assert!(optimal_b == fungible_asset::amount(&asset_b), E_INSUFFICIENT_WITHDRAWN_AMOUNT);
        
        fullsail::gauge::stake(
            account,
            fullsail::vote_manager::get_gauge(fullsail::liquidity_pool::liquidity_pool(metadata_a, metadata_b, stable)),
            fullsail::liquidity_pool::mint_lp(account, asset_a, asset_b, stable)
        );
    }

    public fun add_liquidity_both_coins<CoinTypeA, CoinTypeB>(_account: &signer, _coin_a: Coin<CoinTypeA>, _coin_b: Coin<CoinTypeB>, _stable: bool) {
        abort 0
    }

    public entry fun add_liquidity_both_coins_entry<CoinTypeA, CoinTypeB>(_account: &signer, _stable: bool, _amount_a: u64, _amount_b: u64) {
        abort 0
    }

    public fun add_liquidity_coin<CoinType>(_account: &signer, _coin: Coin<CoinType>, _asset: FungibleAsset, _stable: bool) {
        abort 0
    }

    public entry fun add_liquidity_coin_entry<CoinType>(_account: &signer, _other_metadata: Object<Metadata>, _stable: bool, _amount_coin: u64, _amount_other: u64) {
        abort 0
    }

    public entry fun add_liquidity_entry(_account: &signer, _metadata_a: Object<Metadata>, _metadata_b: Object<Metadata>, _stable: bool, _amount_a: u64, _amount_b: u64) {
        abort 0
    }

    public entry fun create_pool(metadata_a: Object<Metadata>, metadata_b: Object<Metadata>, stable: bool) {
        let pool = liquidity_pool::create(metadata_a, metadata_b, stable);
        
        vote_manager::whitelist_default_reward_pool(pool);
        vote_manager::create_gauge_internal(pool);
    }

    public entry fun create_pool_both_coins<CoinTypeA, CoinTypeB>(stable: bool) {
        let pool = liquidity_pool::create(
            coin_wrapper::create_fungible_asset<CoinTypeA>(),
            coin_wrapper::create_fungible_asset<CoinTypeB>(),
            stable
        );

        vote_manager::whitelist_default_reward_pool(pool);
        vote_manager::create_gauge_internal(pool);
    }

    public entry fun create_pool_coin<CoinType>(
        other_metadata: Object<Metadata>,
        stable: bool
    ) {
        let pool = liquidity_pool::create(
            coin_wrapper::create_fungible_asset<CoinType>(),
            other_metadata,
            stable
        );
        vote_manager::whitelist_default_reward_pool(pool);
        vote_manager::create_gauge_internal(pool);
    }

    public(friend) fun exact_deposit(recipient: address, asset: FungibleAsset) {
        let deposit_amount = fungible_asset::amount(&asset);
        let asset_metadata = fungible_asset::asset_metadata(&asset);
        let initial_balance = primary_fungible_store::balance<Metadata>(recipient, asset_metadata);

        primary_fungible_store::deposit(recipient, asset);
        
        let final_balance = primary_fungible_store::balance<Metadata>(recipient, asset_metadata);
        assert!(deposit_amount == final_balance - initial_balance, E_DEPOSIT_AMOUNT_MISMATCH);
    }

    public(friend) fun exact_withdraw<CoinType: key>( account: &signer, metadata: Object<CoinType>, amount: u64): FungibleAsset {
        let withdrawn_asset = primary_fungible_store::withdraw<CoinType>(account, metadata, amount);
        
        assert!(fungible_asset::amount(&withdrawn_asset) == amount, E_INSUFFICIENT_WITHDRAWN_AMOUNT);
        withdrawn_asset
    }

    public fun get_amounts_out(amount_in: u64, token_in: Object<Metadata>, intermediary_tokens: vector<address>, is_stable: vector<bool>): u64 {
        assert!(vector::length(&intermediary_tokens) == vector::length(&is_stable), E_VECTOR_LENGTH_MISMATCH);
        
        let current_amount = amount_in;      
    
        vector::reverse(&mut intermediary_tokens);
        vector::reverse(&mut is_stable);
        
        let token_count = vector::length(&intermediary_tokens);
        assert!(token_count == vector::length(&is_stable), E_VECTOR_LENGTH_MISMATCH_INTERNAL);
        
        let current_token = token_in;
        while (token_count > 0) {
            let next_token = object::address_to_object<Metadata>(vector::pop_back(&mut intermediary_tokens));
            let (amount_out, _) = get_amount_out(current_amount, current_token, next_token, vector::pop_back(&mut is_stable));
            current_amount = amount_out;
            token_count = token_count - 1;
        };
        
        vector::destroy_empty(intermediary_tokens);
        vector::destroy_empty(is_stable);
        current_amount
    }

    fun get_optimal_amounts(metadata_a: Object<Metadata>, metadata_b: Object<Metadata>, stable: bool, amount_a: u64, amount_b: u64): (u64, u64) {
        assert!(amount_a > 0 && amount_b > 0, E_ZERO_AMOUNT);
        
        let quoted_b = quote_liquidity(metadata_a, metadata_b, stable, amount_a);
        if (quoted_b == 0) {
            (amount_a, amount_b)
        } else if (quoted_b <= amount_b) {
            (amount_a, quoted_b)
        } else {
            (quote_liquidity(metadata_b, metadata_a, stable, amount_b), amount_b)
        }
    }

    public fun liquidity_amount_out(metadata_a: Object<Metadata>, metadata_b: Object<Metadata>, stable: bool, amount_a: u64, amount_b: u64): u64 {
        liquidity_pool::liquidity_out(metadata_a, metadata_b, stable, amount_a, amount_b)
    }

    public fun quote_liquidity(metadata_a: Object<Metadata>, metadata_b: Object<Metadata>, stable: bool, amount_in: u64): u64 {
        let (reserve_a, reserve_b) = liquidity_pool::pool_reserves<LiquidityPool>(
            liquidity_pool::liquidity_pool(metadata_a, metadata_b, stable)
        );

        let reserve_out = reserve_b;
        let reserve_in = reserve_a;
        if (!liquidity_pool::is_sorted(metadata_a, metadata_b)) {
            reserve_out = reserve_a;
            reserve_in = reserve_b;
        };
        if (reserve_in == 0 || reserve_out == 0) {
            0
        } else {
            assert!(reserve_in != 0, error::invalid_argument(E_ZERO_RESERVE));
            (((amount_in as u128) * (reserve_out as u128) / (reserve_in as u128)) as u64)
        }
    }

    public fun redeemable_liquidity(pool: Object<LiquidityPool>, liquidity_amount: u64): (u64, u64) {
        liquidity_pool::liquidity_amounts(pool, liquidity_amount)
    }

    public fun remove_liquidity(_account: &signer, _metadata_a: Object<Metadata>, _metadata_b: Object<Metadata>, _stable: bool, _liquidity_amount: u64, _min_amount_a: u64, _min_amount_b: u64): (FungibleAsset, FungibleAsset) {
        abort 0
    }

    public fun remove_liquidity_both_coins<CoinTypeA, CoinTypeB>(_account: &signer, _stable: bool, _liquidity_amount: u64, _min_amount_a: u64, _min_amount_b: u64): (Coin<CoinTypeA>, Coin<CoinTypeB>) {
        abort 0
    }

    public entry fun remove_liquidity_both_coins_entry<CoinTypeA, CoinTypeB>(_account: &signer, _stable: bool, _liquidity_amount: u64, _min_amount_a: u64, _min_amount_b: u64, _recipient: address) {
        abort 0
    }

    public fun remove_liquidity_coin<CoinType>(_account: &signer, _other_metadata: Object<Metadata>, _stable: bool, _liquidity_amount: u64, _min_amount_coin: u64, _min_amount_other: u64): (Coin<CoinType>, FungibleAsset) {
        abort 0
    }

    public entry fun remove_liquidity_coin_entry<CoinType>(_account: &signer, _other_metadata: Object<Metadata>, _stable: bool, _liquidity_amount: u64, _min_amount_coin: u64, _min_amount_other: u64, _recipient: address) {
        abort 0
    }

    public entry fun remove_liquidity_entry(_account: &signer, _metadata_a: Object<Metadata>, _metadata_b: Object<Metadata>, _stable: bool, _liquidity_amount: u64, _min_amount_a: u64, _min_amount_b: u64, _recipient: address) {
        abort 0
    }

    fun remove_liquidity_internal(account: &signer, metadata_a: Object<Metadata>, metadata_b: Object<Metadata>, stable: bool, liquidity_amount: u64, min_amount_a: u64, min_amount_b: u64): (FungibleAsset, FungibleAsset) {
        let (asset_a, asset_b) = liquidity_pool::burn(account, metadata_a, metadata_b, stable, liquidity_amount);
        let amount_b = asset_b;
        let amount_a = asset_a;
        
        assert!(fungible_asset::amount(&amount_a) >= min_amount_a && fungible_asset::amount(&amount_b) >= min_amount_b, E_INSUFFICIENT_OUTPUT_AMOUNT);
        (amount_a, amount_b)
    }

    public fun swap_asset_for_coin<CoinType>(asset_in: FungibleAsset, min_amount_out: u64, stable: bool): Coin<CoinType> {
        coin_wrapper::unwrap<CoinType>(swap(asset_in, min_amount_out, coin_wrapper::get_wrapper<CoinType>(), stable))
    }

    public entry fun swap_asset_for_coin_entry<CoinType>(account: &signer, amount_in: u64, min_amount_out: u64, asset_metadata: Object<Metadata>, stable: bool, recipient: address) {
        coin::register<CoinType>(account);
        aptos_account::deposit_coins<CoinType>(recipient, swap_asset_for_coin<CoinType>(exact_withdraw<Metadata>(account, asset_metadata, amount_in), min_amount_out, stable));
    }

    public fun swap_coin_for_asset<CoinType>(coin_in: Coin<CoinType>, min_amount_out: u64, asset_metadata: Object<Metadata>, stable: bool): FungibleAsset {
        swap(coin_wrapper::wrap<CoinType>(coin_in), min_amount_out, asset_metadata, stable)
    }

    public entry fun swap_coin_for_asset_entry<CoinType>(account: &signer, amount_in: u64, min_amount_out: u64, asset_metadata: Object<Metadata>, stable: bool, recipient: address) {
        exact_deposit(recipient, swap_coin_for_asset<CoinType>(coin::withdraw<CoinType>(account, amount_in), min_amount_out, asset_metadata, stable));
    }

    public fun swap_coin_for_coin<CoinTypeIn, CoinTypeOut>(coin_in: Coin<CoinTypeIn>, min_amount_out: u64, stable: bool): Coin<CoinTypeOut> {
        swap_asset_for_coin<CoinTypeOut>(coin_wrapper::wrap<CoinTypeIn>(coin_in), min_amount_out, stable)
    }

    public entry fun swap_coin_for_coin_entry<CoinTypeIn, CoinTypeOut>(account: &signer, amount_in: u64, min_amount_out: u64, stable: bool, recipient: address) {
        coin::register<CoinTypeOut>(account);
        coin::deposit<CoinTypeOut>(recipient, swap_coin_for_coin<CoinTypeIn, CoinTypeOut>(coin::withdraw<CoinTypeIn>(account, amount_in), min_amount_out, stable));
    }

    public entry fun swap_entry(account: &signer, amount_in: u64, min_amount_out: u64, metadata_in: Object<Metadata>, metadata_out: Object<Metadata>, stable: bool, recipient: address) {
        assert!(!coin_wrapper::is_wrapper(metadata_out), E_OUTPUT_IS_WRAPPER);
        exact_deposit(recipient, swap(exact_withdraw<Metadata>(account, metadata_in, amount_in), min_amount_out, metadata_out, stable));
    }

    public entry fun swap_route_entry(account: &signer, amount_in: u64, min_amount_out: u64, metadata_in: Object<Metadata>, route_metadata: vector<Object<Metadata>>, route_stable: vector<bool>, recipient: address) {
        assert!(!coin_wrapper::is_wrapper(*vector::borrow(&route_metadata, vector::length(&route_metadata) - 1)), E_OUTPUT_IS_WRAPPER);
        exact_deposit(recipient, swap_router(exact_withdraw<Metadata>(account, metadata_in, amount_in), min_amount_out, route_metadata, route_stable));
    }

    public entry fun swap_route_entry_both_coins<CoinTypeIn, CoinTypeOut>(account: &signer, amount_in: u64, min_amount_out: u64, route_metadata: vector<Object<Metadata>>, route_stable: vector<bool>, recipient: address) {
        coin::register<CoinTypeOut>(account);
        coin::deposit<CoinTypeOut>(recipient, coin_wrapper::unwrap<CoinTypeOut>(swap_router(coin_wrapper::wrap<CoinTypeIn>(coin::withdraw<CoinTypeIn>(account, amount_in)), min_amount_out, route_metadata, route_stable)));
    }

    public entry fun swap_route_entry_from_coin<CoinType>(account: &signer, amount_in: u64, min_amount_out: u64, route_metadata: vector<Object<Metadata>>, route_stable: vector<bool>, recipient: address) {
        assert!(!coin_wrapper::is_wrapper(*vector::borrow(&route_metadata, vector::length(&route_metadata) - 1)), E_OUTPUT_IS_WRAPPER);
        exact_deposit(recipient, swap_router(coin_wrapper::wrap<CoinType>(coin::withdraw<CoinType>(account, amount_in)), min_amount_out, route_metadata, route_stable));
    }

    public entry fun swap_route_entry_to_coin<CoinType>(account: &signer, amount_in: u64, min_amount_out: u64, metadata_in: Object<Metadata>, route_metadata: vector<Object<Metadata>>, route_stable: vector<bool>, recipient: address) {
        coin::register<CoinType>(account);
        coin::deposit<CoinType>(recipient, coin_wrapper::unwrap<CoinType>(swap_router(exact_withdraw<Metadata>(account, metadata_in, amount_in), min_amount_out, route_metadata, route_stable)));
    }

    public fun swap_router(input_asset: FungibleAsset, min_output_amount: u64, route_metadata: vector<Object<Metadata>>, route_stable: vector<bool>): FungibleAsset {
        let current_asset = input_asset;
        vector::reverse(&mut route_metadata);
        vector::reverse(&mut route_stable);

        let route_length = vector::length(&route_metadata);
        assert!(route_length == vector::length(&route_stable), E_VECTOR_LENGTH_MISMATCH);

        while (route_length > 0) {
            let swap_input = current_asset;
            current_asset = swap(
                swap_input,
                0,
                vector::pop_back(&mut route_metadata),
                vector::pop_back(&mut route_stable)
            );
            route_length = route_length - 1;
        };

        vector::destroy_empty(route_metadata);
        vector::destroy_empty(route_stable);
        assert!(fungible_asset::amount(&current_asset) >= min_output_amount, E_INSUFFICIENT_OUTPUT_AMOUNT);
        current_asset
    }

    public entry fun unstake_and_remove_liquidity_both_coins_entry<CoinTypeA, CoinTypeB>(account: &signer, stable: bool, lp_amount: u64, min_amount_a: u64, min_amount_b: u64, recipient: address) {
        let wrapper_a = coin_wrapper::get_wrapper<CoinTypeA>();
        let wrapper_b = coin_wrapper::get_wrapper<CoinTypeB>();
        gauge::unstake_lp(account, vote_manager::get_gauge(liquidity_pool::liquidity_pool(wrapper_a, wrapper_b, stable)), lp_amount);
        let (asset_a, asset_b) = remove_liquidity_internal(account, wrapper_a, wrapper_b, stable, lp_amount, min_amount_a, min_amount_b);
        aptos_account::deposit_coins<CoinTypeA>(recipient, coin_wrapper::unwrap<CoinTypeA>(asset_a));
        aptos_account::deposit_coins<CoinTypeB>(recipient, coin_wrapper::unwrap<CoinTypeB>(asset_b));
    }

    public entry fun unstake_and_remove_liquidity_coin_entry<CoinType>(account: &signer, other_metadata: Object<Metadata>, stable: bool, lp_amount: u64, min_amount_coin: u64, min_amount_other: u64, recipient: address) {
        let coin_wrapper = coin_wrapper::get_wrapper<CoinType>();
        gauge::unstake_lp(account, vote_manager::get_gauge(liquidity_pool::liquidity_pool(coin_wrapper, other_metadata, stable)), lp_amount);
        assert!(!coin_wrapper::is_wrapper(other_metadata), E_OTHER_ASSET_IS_WRAPPER);
        let (coin_asset, other_asset) = remove_liquidity_internal(account, coin_wrapper, other_metadata, stable, lp_amount, min_amount_coin, min_amount_other);
        aptos_account::deposit_coins<CoinType>(recipient, coin_wrapper::unwrap<CoinType>(coin_asset));
        primary_fungible_store::deposit(recipient, other_asset);
    }
    
    public entry fun unstake_and_remove_liquidity_entry(account: &signer, metadata_a: Object<Metadata>, metadata_b: Object<Metadata>, stable: bool, lp_amount: u64, min_amount_a: u64, min_amount_b: u64, recipient: address) {
        gauge::unstake_lp(account, vote_manager::get_gauge(liquidity_pool::liquidity_pool(metadata_a, metadata_b, stable)), lp_amount);
        assert!(!coin_wrapper::is_wrapper(metadata_a) && !coin_wrapper::is_wrapper(metadata_b), E_ASSETS_ARE_WRAPPERS);
        let (asset_a, asset_b) = remove_liquidity_internal(account, metadata_a, metadata_b, stable, lp_amount, min_amount_a, min_amount_b);
        primary_fungible_store::deposit(recipient, asset_a);
        primary_fungible_store::deposit(recipient, asset_b);
    }
}

