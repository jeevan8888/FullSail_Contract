module full_sail::full_sail {
    use std::string::{Self, String};
    use sui::coin::{Self, Coin};
    use sui::balance::{Supply};

    public struct FULL_SAIL has drop {}

    // Main struct for the Sail token
    public struct Sail has key, store {
        id: UID, // Add UID as the first field
        name: String,
        symbol: String,
        decimals: u8,
        total_supply: Supply<FULL_SAIL>,
        minter: address,
        owner: address,
    }

    fun init(witness: FULL_SAIL, ctx: &mut TxContext) {
        let (treasury_cap, metadata) = coin::create_currency<FULL_SAIL>(
            witness,
            18,
            b"SAIL",
            b"FullSail",
            b"Coin of FullSail Dex",
            option::none(),
            ctx
        );

        transfer::public_freeze_object(metadata);

        let minter = tx_context::sender(ctx);
        let owner = minter;
        let fullsail = Sail {
            id: object::new(ctx),
            name: string::utf8(b"FullSail"),
            symbol: string::utf8(b"SAIL"),
            decimals: 18,
            total_supply: coin::treasury_into_supply(treasury_cap),
            minter,
            owner
        };
        transfer::share_object(fullsail);
    }

    public entry fun set_minter(self: &mut Sail, new_minter: address, ctx: &mut TxContext) {
        let sender = tx_context::sender(ctx);
        assert!(sender == self.minter, 0);
        self.minter = new_minter;
    }

    public fun mint(self: &mut Sail, treasury_cap: &mut coin::TreasuryCap<FULL_SAIL>, amount: u64, ctx: &mut TxContext): Coin<FULL_SAIL> {
        let sender = tx_context::sender(ctx);
        assert!(sender == self.minter, 0);
        coin::mint(treasury_cap, amount, ctx)
    }
}