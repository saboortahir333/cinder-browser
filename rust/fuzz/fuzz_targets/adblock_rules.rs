#![no_main]
//! Untrusted filter-list text (downloaded from the network) must never panic.
use libfuzzer_sys::fuzz_target;
use rust_lib_saboor_browser::api::adblock_engine::{adblock_load, adblock_should_block};

fuzz_target!(|data: &[u8]| {
    let list = String::from_utf8_lossy(data).into_owned();
    adblock_load(vec![list]);
    let _ = adblock_should_block("https://ads.example.com/a.js".into(), "https://site.test/".into(), "Script".into());
});
