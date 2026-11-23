use crate::{common::BIZDESK_UPDATE_BASE, hbbs_http::create_http_client_with_url_strict};
use hbb_common::{bail, config::Config, log, ResultType};
use std::{path::PathBuf, process::Command, time::Duration};

const FIRST_DELAY: Duration = Duration::from_secs(90);
const CHECK_INTERVAL: Duration = Duration::from_secs(30 * 60);

pub fn start() {
    static STARTED: std::sync::Once = std::sync::Once::new();
    STARTED.call_once(|| {
        std::thread::spawn(|| {
            std::thread::sleep(FIRST_DELAY);
            loop {
                if let Err(e) = check() {
                    log::debug!("bizmed agent enrollment: {}", e);
                }
                std::thread::sleep(CHECK_INTERVAL);
            }
        });
    });
}

fn agent_dir() -> PathBuf {
    #[cfg(target_os = "windows")]
    {
        PathBuf::from(std::env::var("ProgramData").unwrap_or_else(|_| "C:\\ProgramData".to_owned()))
            .join("BizmedAgent")
    }
    #[cfg(not(target_os = "windows"))]
    {
        PathBuf::from("/opt/bizmed-agent")
    }
}

fn is_installed() -> bool {
    #[cfg(target_os = "windows")]
    let main_file = "agent.ps1";
    #[cfg(not(target_os = "windows"))]
    let main_file = "agent.py";
    agent_dir().join(main_file).exists()
}

// Yalnızca bu mekanizmanın kurduğu ajan, panel izlemeyi kapatınca kaldırılır.
fn marker() -> PathBuf {
    agent_dir().join("auto.flag")
}

fn check() -> ResultType<()> {
    let url = format!("{}/api/agent/enroll", BIZDESK_UPDATE_BASE);
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
        bail!("enroll status {}", resp.status());
    }
    let v: serde_json::Value = resp.json()?;
    let enabled = v["enabled"].as_bool().unwrap_or(false);
    let installed = is_installed();
    if enabled && !installed {
        let key = v["key"].as_str().unwrap_or_default();
        if key.is_empty() || !key.chars().all(|c| c.is_ascii_alphanumeric()) {
            bail!("invalid agent key");
        }
        install(key)?;
        if let Err(e) = std::fs::write(marker(), b"1") {
            log::warn!("bizmed agent marker: {}", e);
        }
        log::info!("bizmed monitoring agent installed");
    } else if !enabled && installed && marker().exists() {
        uninstall()?;
        log::info!("bizmed monitoring agent removed");
    }
    Ok(())
}

fn download_script(name: &str) -> ResultType<Vec<u8>> {
    let url = format!("{}/agent/{}", BIZDESK_UPDATE_BASE, name);
    let client = create_http_client_with_url_strict(&url)?;
    let resp = client.get(&url).timeout(Duration::from_secs(60)).send()?;
    if !resp.status().is_success() {
        bail!("script download status {}", resp.status());
    }
    let bytes = resp.bytes()?;
    if bytes.is_empty() || bytes.len() > 256 * 1024 {
        bail!("unexpected script size");
    }
    Ok(bytes.to_vec())
}

#[cfg(target_os = "windows")]
fn run_windows(extra: &[&str]) -> ResultType<()> {
    use std::os::windows::process::CommandExt;
    let script = download_script("windows.ps1")?;
    let path = std::env::temp_dir().join("bizmed-agent-setup.ps1");
    std::fs::write(&path, &script)?;
    let out = Command::new("powershell")
        .args(["-NoProfile", "-ExecutionPolicy", "Bypass", "-File"])
        .arg(&path)
        .args(extra)
        .creation_flags(0x0800_0000) // CREATE_NO_WINDOW
        .output();
    let _ = std::fs::remove_file(&path);
    let out = out?;
    if !out.status.success() {
        bail!("agent script failed: {}", String::from_utf8_lossy(&out.stderr));
    }
    Ok(())
}

#[cfg(target_os = "windows")]
fn install(key: &str) -> ResultType<()> {
    run_windows(&["-Install", "-Key", key, "-Server", BIZDESK_UPDATE_BASE])
}

#[cfg(target_os = "windows")]
fn uninstall() -> ResultType<()> {
    run_windows(&["-Uninstall"])
}

#[cfg(not(target_os = "windows"))]
fn run_linux(args: &[&str]) -> ResultType<()> {
    use std::io::Write;
    let script = download_script("linux.sh")?;
    let mut child = Command::new("bash")
        .arg("-s")
        .arg("--")
        .args(args)
        .stdin(std::process::Stdio::piped())
        .stdout(std::process::Stdio::null())
        .stderr(std::process::Stdio::piped())
        .spawn()?;
    if let Some(mut stdin) = child.stdin.take() {
        stdin.write_all(&script)?;
    }
    let out = child.wait_with_output()?;
    if !out.status.success() {
        bail!("agent script failed: {}", String::from_utf8_lossy(&out.stderr));
    }
    Ok(())
}

#[cfg(not(target_os = "windows"))]
fn install(key: &str) -> ResultType<()> {
    run_linux(&["install", key, BIZDESK_UPDATE_BASE])
}

#[cfg(not(target_os = "windows"))]
fn uninstall() -> ResultType<()> {
    run_linux(&["uninstall"])
}
