//! Request filtering for Cinder: Adblock Plus syntax (EasyList, EasyPrivacy,
//! uBlock-style lists) parsed and matched by Brave's `adblock` crate.
//!
//! The engine lives in Rust; Dart feeds it list text and asks yes/no per URL.
//! Nothing here touches the network.

use adblock::lists::{FilterSet, ParseOptions};
use adblock::request::Request;
use adblock::Engine;
use std::sync::Mutex;

static ENGINE: Mutex<Option<Engine>> = Mutex::new(None);

#[flutter_rust_bridge::frb(init)]
pub fn init_app() {
    flutter_rust_bridge::setup_default_user_utils();
}

/// Replaces the active rule set. `lists` is the text of each filter list.
/// Returns the number of lines handed to the parser (invalid rules are skipped).
pub fn adblock_load(lists: Vec<String>) -> u32 {
    let mut set = FilterSet::new(false);
    let mut lines = 0u32;
    for list in &lists {
        lines += list.lines().count() as u32;
        set.add_filter_list(list.clone(), ParseOptions::default());
    }
    let engine = Engine::new_with_filter_set(set);
    if let Ok(mut guard) = ENGINE.lock() {
        *guard = Some(engine);
    }
    lines
}

/// True when the request should be blocked.
/// `request_type` is a CDP resource type ("Document", "Script", "Image", ...).
#[flutter_rust_bridge::frb(sync)]
pub fn adblock_should_block(url: String, source_url: String, request_type: String) -> bool {
    let kind = match request_type.to_ascii_lowercase().as_str() {
        "document" => "document",
        "stylesheet" => "stylesheet",
        "image" => "image",
        "media" => "media",
        "font" => "font",
        "script" => "script",
        "xhr" | "fetch" => "xmlhttprequest",
        "websocket" => "websocket",
        "ping" => "ping",
        _ => "other",
    };
    let Ok(req) = Request::new(&url, &source_url, kind, "GET") else {
        return false;
    };
    match ENGINE.lock() {
        Ok(guard) => guard
            .as_ref()
            .map(|e| e.check_network_request(&req).should_block())
            .unwrap_or(false),
        Err(_) => false,
    }
}

/// Cosmetic selectors to hide on a page (empty when no engine is loaded).
pub fn adblock_hidden_selectors(url: String) -> Vec<String> {
    match ENGINE.lock() {
        Ok(guard) => guard
            .as_ref()
            .map(|e| {
                let r = e.url_cosmetic_resources(&url);
                let mut v: Vec<String> = r.hide_selectors.into_iter().collect();
                v.sort();
                v
            })
            .unwrap_or_default(),
        Err(_) => Vec::new(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn blocks_listed_hosts_only() {
        adblock_load(vec!["||ads.example.com^\n||tracker.test^$third-party".into()]);
        assert!(adblock_should_block(
            "https://ads.example.com/a.js".into(),
            "https://news.test/".into(),
            "Script".into()
        ));
        assert!(!adblock_should_block(
            "https://news.test/a.js".into(),
            "https://news.test/".into(),
            "Script".into()
        ));
        // third-party-only rule does not hit same-site requests
        assert!(!adblock_should_block(
            "https://tracker.test/p.gif".into(),
            "https://tracker.test/".into(),
            "Image".into()
        ));
    }

    #[test]
    fn garbage_urls_are_not_blocked() {
        assert!(!adblock_should_block("not a url".into(), "".into(), "Other".into()));
    }
}
