module fullsail::epoch {
    use aptos_framework::timestamp;

    public fun now() : u64 {
        timestamp::now_seconds() / 604800
    }
}

