module fullsail::minter {
    use std::string;
    use std::error;
    use aptos_std::math64;
    use aptos_framework::primary_fungible_store;
    use aptos_framework::fungible_asset::{Self, FungibleAsset};
    use aptos_framework::object;
    use aptos_framework::signer;
    use fullsail::cellana_token::{Self, CellanaToken};
    use fullsail::package_manager;
    use fullsail::voting_escrow;
    use fullsail::epoch;

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

    // --- firends modules ---
    friend fullsail::vote_manager;

    // --- structs ---
    struct MinterConfig has key {
        team_account: address,
        pending_team_account: address,
        team_emission_rate_bps: u64,
        weekly_emission_amount: u64,
        last_emission_update_epoch: u64,
    }

    // init
    public entry fun initialize() {
        if (is_initialized()) {
            return
        };
        cellana_token::initialize();
        let signer = package_manager::get_signer();
        let object_handle = object::create_object_from_account(&signer);
        let object_signer = object::generate_signer(&object_handle);
        let object_signer_ref = &object_signer;
        let minter_config = MinterConfig{
            team_account               : @0xc3bb8488ab1a5815a9d543d7e41b0e0df46a7396f89b22821f07a4362f75ddc5,
            pending_team_account       : @0x0,
            team_emission_rate_bps     : 30,
            weekly_emission_amount     : 150000000000000,
            last_emission_update_epoch : epoch::now(),
        };
        move_to<MinterConfig>(object_signer_ref, minter_config);
        let initial_mint_amount = cellana_token::mint(100000000000000000);
        primary_fungible_store::deposit(@0xc3bb8488ab1a5815a9d543d7e41b0e0df46a7396f89b22821f07a4362f75ddc5, fungible_asset::extract(&mut initial_mint_amount, 100000000000000000 / 5));
        voting_escrow::create_lock_with(initial_mint_amount, voting_escrow::max_lockup_epochs(), @0xc3bb8488ab1a5815a9d543d7e41b0e0df46a7396f89b22821f07a4362f75ddc5);
        package_manager::add_address(string::utf8(b"minter"), signer::address_of(object_signer_ref));
    }

    public(friend) fun mint() : (FungibleAsset, FungibleAsset) acquires MinterConfig {
        let rebase_amount = current_rebase();
        let minter_config = borrow_global_mut<MinterConfig>(minter_address());
        let current_epoch = epoch::now();
        assert!(current_epoch >= minter_config.last_emission_update_epoch + 1, E_MAX_LOCK_TIME);
        let weekly_emission = minter_config.weekly_emission_amount;
        let basis_points = 10000;
        assert!(basis_points != 0, error::invalid_argument(E_ZERO_TOTAL_POWER));
        let minted_tokens = cellana_token::mint(weekly_emission);
        primary_fungible_store::deposit(minter_config.team_account, fungible_asset::extract(&mut minted_tokens, (((weekly_emission as u128) * (minter_config.team_emission_rate_bps as u128) / (basis_points as u128)) as u64)));
        let additional_minted_tokens = if (rebase_amount == 0) {
            fungible_asset::zero<CellanaToken>(cellana_token::token())
        } else {
            cellana_token::mint((rebase_amount as u64))
        };
        let reduction_rate_bps = 10000;
        assert!(reduction_rate_bps != 0, error::invalid_argument(E_ZERO_TOTAL_POWER));
        minter_config.weekly_emission_amount = math64::max((((weekly_emission as u128) * ((10000 - 100) as u128) / (reduction_rate_bps as u128)) as u64), min_weekly_emission());
        minter_config.last_emission_update_epoch = current_epoch;
        (minted_tokens, additional_minted_tokens)
    }

    public entry fun confirm_new_team_account(signer_ref: &signer) acquires MinterConfig {
        let minter_config = borrow_global_mut<MinterConfig>(minter_address());
        assert!(minter_config.pending_team_account == signer::address_of(signer_ref), E_NOT_OWNER);
        minter_config.team_account = minter_config.pending_team_account;
        minter_config.pending_team_account = @0x0;
    }

    public fun current_rebase() : u128 acquires MinterConfig {
        let weekly_emission = current_weekly_emission();
        let total_voting_power = voting_escrow::total_voting_power();
        let total_supply = cellana_token::total_supply();
        assert!(total_supply != 0, error::invalid_argument(E_ZERO_TOTAL_POWER));
        assert!(total_supply != 0, error::invalid_argument(E_ZERO_TOTAL_POWER));
        assert!(total_supply != 0, error::invalid_argument(E_ZERO_TOTAL_POWER));
        ((((((((((weekly_emission as u128) as u256) * (total_voting_power as u256) / (total_supply as u256)) as u128) as u256) * (total_voting_power as u256) / (total_supply as u256)) as u128) as u256) * (total_voting_power as u256) / (total_supply as u256)) as u128) / 2
    }

    public fun current_weekly_emission() : u64 acquires MinterConfig {
        borrow_global<MinterConfig>(minter_address()).weekly_emission_amount
    }

    public fun gauge_emission() : u64 acquires MinterConfig {
        let minter_config = borrow_global<MinterConfig>(minter_address());
        let basis_points = 10000;
        assert!(basis_points != 0, error::invalid_argument(E_ZERO_TOTAL_POWER));
        (((minter_config.weekly_emission_amount as u128) * ((10000 - minter_config.team_emission_rate_bps) as u128) / (basis_points as u128)) as u64)
    }

    public fun get_init_locked_account() : u64 {
        let lock_divisor = 5;
        assert!(lock_divisor != 0, error::invalid_argument(E_ZERO_TOTAL_POWER));
        (((100000000000000000 as u128) * 4 / (lock_divisor as u128)) as u64)
    }


    public fun initial_weekly_emission() : u64 {
        150000000000000
    }

    public fun is_initialized() : bool {
        package_manager::address_exists(string::utf8(b"minter"))
    }

    public fun min_weekly_emission() : u64 {
        ((cellana_token::total_supply() * (2 as u128) / 10000) as u64)
    }

    public fun minter_address() : address {
        package_manager::get_address(string::utf8(b"minter"))
    }

    public entry fun set_team_rate(team_signer: &signer, new_rate_bps: u64) acquires MinterConfig {
        assert!(new_rate_bps <= 50, E_INSUFFICIENT_BALANCE);
        let minter_config = borrow_global_mut<MinterConfig>(minter_address());
        assert!(signer::address_of(team_signer) == minter_config.team_account, E_NOT_OWNER);
        minter_config.team_emission_rate_bps = new_rate_bps;
    }

    public fun team() : address acquires MinterConfig {
        borrow_global<MinterConfig>(minter_address()).team_account
    }

    public fun team_emission_rate_bps() : u64 acquires MinterConfig {
        borrow_global<MinterConfig>(minter_address()).team_emission_rate_bps
    }

    public entry fun update_team_account(team_signer: &signer, new_team_account: address) acquires MinterConfig {
        let minter_config = borrow_global_mut<MinterConfig>(minter_address());
        assert!(signer::address_of(team_signer) == minter_config.team_account, E_NOT_OWNER);
        minter_config.pending_team_account = new_team_account;
    }

    public fun weekly_emission_reduction_rate_bps() : u64 {
        100
    }

    #[test_only]
    public fun mint_test() : (FungibleAsset, FungibleAsset) acquires MinterConfig {
        mint()
    }
}