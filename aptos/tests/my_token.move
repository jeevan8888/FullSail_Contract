#[test_only]
module fullsail::my_token {
    struct MyToken has copy, drop, store {
        name: vector<u8>,
        symbol: vector<u8>,
        decimals: u8,
    }

    struct MyToken1 has copy, drop, store {
        name: vector<u8>,
        symbol: vector<u8>,
        decimals: u8,
    }

    public fun create_my_token(name: vector<u8>, symbol: vector<u8>, decimals: u8): MyToken {
        MyToken {
            name,
            symbol,
            decimals
        }
    }

    public fun default_my_token(): MyToken {
        create_my_token(b"MyToken", b"MTK", 8)
    }
}