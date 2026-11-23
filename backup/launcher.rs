#![windows_subsystem = "windows"]

use std::env;
use std::fs;
use std::net::{SocketAddr, TcpStream};
use std::os::windows::process::CommandExt;
use std::path::{Path, PathBuf};
use std::process::{Child, Command, Stdio};
use std::thread;
use std::time::{Duration, Instant};

const CREATE_NO_WINDOW: u32 = 0x08000000;
const SERVER_PORT: u16 = 3000;

fn is_port_listening(port: u16) -> bool {
    let addr = SocketAddr::from(([127, 0, 0, 1], port));
    TcpStream::connect_timeout(&addr, Duration::from_millis(200)).is_ok()
}

fn start_local_server(project_dir: &Path) -> Option<Child> {
    Command::new("cmd.exe")
        .args([
            "/c",
            "npx.cmd serve -l 3000 . || npx serve -l 3000 . || npx serve .",
        ])
        .current_dir(project_dir)
        .creation_flags(CREATE_NO_WINDOW)
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn()
        .ok()
}

fn wait_for_server(port: u16, timeout: Duration) -> bool {
    let start = Instant::now();
    while start.elapsed() < timeout {
        if is_port_listening(port) {
            return true;
        }
        thread::sleep(Duration::from_millis(150));
    }
    false
}

fn stop_server_on_port(port: u16) {
    let script = format!(
        "Get-NetTCPConnection -LocalPort {} -ErrorAction SilentlyContinue | ForEach-Object {{ Stop-Process -Id $_.OwningProcess -Force -ErrorAction SilentlyContinue }}",
        port
    );
    let _ = Command::new("powershell")
        .args(["-NoProfile", "-NonInteractive", "-Command", &script])
        .creation_flags(CREATE_NO_WINDOW)
        .output();
}

fn find_app_browser() -> Option<PathBuf> {
    let mut candidates = Vec::new();

    // 1. Prioritize Microsoft Edge (native Chromium app mode on Windows, avoids Chrome entirely)
    if let Ok(pf86) = env::var("ProgramFiles(x86)") {
        candidates.push(PathBuf::from(&pf86).join(r"Microsoft\Edge\Application\msedge.exe"));
    }
    if let Ok(pf) = env::var("ProgramFiles") {
        candidates.push(PathBuf::from(&pf).join(r"Microsoft\Edge\Application\msedge.exe"));
    }
    if let Ok(local_app_data) = env::var("LOCALAPPDATA") {
        candidates.push(PathBuf::from(&local_app_data).join(r"Microsoft\Edge\Application\msedge.exe"));
    }

    // 2. Google Chrome (in --app mode as fallback if Edge is not found)
    if let Ok(pf) = env::var("ProgramFiles") {
        candidates.push(PathBuf::from(&pf).join(r"Google\Chrome\Application\chrome.exe"));
    }
    if let Ok(pf86) = env::var("ProgramFiles(x86)") {
        candidates.push(PathBuf::from(&pf86).join(r"Google\Chrome\Application\chrome.exe"));
    }
    if let Ok(local_app_data) = env::var("LOCALAPPDATA") {
        candidates.push(PathBuf::from(&local_app_data).join(r"Google\Chrome\Application\chrome.exe"));
    }

    for path in candidates {
        if path.exists() {
            return Some(path);
        }
    }

    None
}

fn main() {
    let exe_path = env::current_exe().unwrap_or_else(|_| PathBuf::from("."));
    let project_dir = exe_path.parent().unwrap_or_else(|| Path::new("."));

    // Check if the server is already running on port 3000
    let was_already_running = is_port_listening(SERVER_PORT);
    let mut server_child: Option<Child> = None;

    if !was_already_running {
        server_child = start_local_server(project_dir);
        // Wait up to 6 seconds for the server to bind port 3000
        wait_for_server(SERVER_PORT, Duration::from_secs(6));
    }

    // Prepare profile directory for isolated app session
    let local_app_data = env::var("LOCALAPPDATA").unwrap_or_else(|_| ".".to_string());
    let profile_dir = PathBuf::from(local_app_data).join(r"ModuCut\Profile");
    let _ = fs::create_dir_all(&profile_dir);

    let app_url = format!("http://localhost:{}", SERVER_PORT);

    if let Some(browser_exe) = find_app_browser() {
        let profile_arg = format!("--user-data-dir={}", profile_dir.display());
        let app_arg = format!("--app={}", app_url);

        let mut browser_cmd = Command::new(&browser_exe);
        browser_cmd
            .arg(&app_arg)
            .arg(&profile_arg)
            .arg("--name=ModuCut")
            .arg("--window-size=1440,900")
            .arg("--hide-crash-restore-bubble")
            .arg("--no-first-run")
            .arg("--no-default-browser-check");

        if let Ok(mut child) = browser_cmd.spawn() {
            // Block until the standalone window is closed by the user
            let _ = child.wait();
        }
    } else {
        // Fallback: standard shell launch
        let _ = Command::new("cmd.exe")
            .args(["/c", "start", &app_url])
            .creation_flags(CREATE_NO_WINDOW)
            .status();
    }

    // Cleanup: If this instance started the server, shut it down when the window closes
    if let Some(child) = server_child {
        let pid = child.id();
        let _ = Command::new("taskkill")
            .args(["/F", "/T", "/PID", &pid.to_string()])
            .creation_flags(CREATE_NO_WINDOW)
            .output();
        stop_server_on_port(SERVER_PORT);
    }
}
