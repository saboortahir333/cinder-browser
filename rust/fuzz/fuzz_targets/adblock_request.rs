#![no_main]
//! Hostile URLs must never panic or hang the request matcher.
use libfuzzer_sys::fuzz_target;
use rust_lib_saboor_browser::api::adblock_engine::{adblock_load, adblock_should_block};

fuzz_target!(|data: &[u8]| {
    let s = String::from_utf8_lossy(data).into_owned();
    let (url, rest) = s.split_at(s.len() / 2);
    adblock_load(vec!["||ads.example.com^\n||tracker.test^$third-party".into()]);
    let _ = adblock_should_block(url.to_string(), rest.to_string(), "Script".into());
});
