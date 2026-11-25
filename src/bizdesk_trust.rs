use crate::{common::BIZDESK_UPDATE_BASE, hbbs_http::create_http_client_with_url_strict};
use hbb_common::{bail, config::Config, log, ResultType};
use std::time::Duration;

const KEY: &str = "bizdesk-trusted-ids";
const FIRST_DELAY: Duration = Duration::from_secs(45);
const INTERVAL: Duration = Duration::from_secs(5 * 60);

pub fn start() {
    static STARTED: std::sync::Once = std::sync::Once::new();
    STARTED.call_once(|| {
        std::thread::spawn(|| {
            std::thread::sleep(FIRST_DELAY);
            loop {
                if let Err(e) = fetch() {
                    log::debug!("bizmed trusted ids: {}", e);
                }
                std::thread::sleep(INTERVAL);
            }
        });
    });
}

// Panelin varsayilan izin listesi. Bos ise zorunlu tutulmaz.
pub fn trusted_ids() -> Vec<String> {
    Config::get_option(KEY)
        .split(',')
        .map(|x| x.trim().to_owned())
        .filter(|x| !x.is_empty())
        .collect()
}

fn fetch() -> ResultType<()> {
    let url = format!("{}/api/trust/ids", BIZDESK_UPDATE_BASE);
    let client = create_http_client_with_url_strict(&url)?;
    let body = serde_json::json!({
        "id": Config::get_id(),
        "uuid": crate::encode64(hbb_common::get_uuid()),
    });
    let resp = client
        .post(&url)
        .json(&body)
        .timeout(Duration::from_secs(30))
        .send()?;
    if !resp.status().is_success() {
        bail!("status {}", resp.status());
    }
    let v: serde_json::Value = resp.json()?;
    let enforce = v["enforce"].as_bool().unwrap_or(false);
    let ids: Vec<String> = v["ids"]
        .as_array()
        .map(|a| {
            a.iter()
                .filter_map(|x| x.as_str())
                .filter(|x| !x.is_empty() && x.chars().all(|c| c.is_ascii_digit()))
                .map(|x| x.to_owned())
                .collect()
        })
        .unwrap_or_default();
    let value = if enforce { ids.join(",") } else { String::new() };
    if Config::get_option(KEY) != value {
        Config::set_option(KEY.to_owned(), value);
    }
    Ok(())
}
