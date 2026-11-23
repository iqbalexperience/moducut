#![windows_subsystem = "windows"]

use std::env;
use std::fs;
use std::io::{Read, Write};
use std::net::{SocketAddr, TcpListener, TcpStream};
use std::os::windows::process::CommandExt;
use std::path::{Path, PathBuf};
use std::process::Command;
use std::thread;
use std::time::Duration;

const CREATE_NO_WINDOW: u32 = 0x08000000;
const PREFERRED_PORT: u16 = 3000;

// =========================================================================
// Embedded Web Assets (All packed statically into the single executable)
// =========================================================================
static INDEX_HTML: &[u8] = include_bytes!("index.html");
static PATHKIT_WASM: &[u8] = include_bytes!("editor/pathkit.wasm");
static MANIFOLD_WASM: &[u8] = include_bytes!("editor/assets/manifold.wasm");
static INDEX_CSS: &[u8] = include_bytes!("editor/assets/index.css");
static INDEX_JS: &[u8] = include_bytes!("editor/assets/index.js");
static STANDALONE_RUNTIME_JS: &[u8] = include_bytes!("editor/assets/standalone-runtime.js");
static LOCALFORAGE_MIN_JS: &[u8] = include_bytes!("assets/localforage.min.js");
static CUT_ICO: &[u8] = include_bytes!("cut.ico");

fn log_event(msg: &str) {
    if let Ok(local_app_data) = env::var("LOCALAPPDATA") {
        let log_dir = PathBuf::from(&local_app_data).join("ModuCut");
        let _ = fs::create_dir_all(&log_dir);
        let log_path = log_dir.join("moducut.log");
        if let Ok(mut file) = fs::OpenOptions::new().create(true).append(true).open(log_path) {
            let _ = writeln!(file, "{}", msg);
        }
    }
}

fn get_mime_type(path: &str) -> &'static str {
    let lower = path.to_ascii_lowercase();
    if lower.ends_with(".html") || lower.ends_with(".htm") || lower.is_empty() {
        "text/html; charset=utf-8"
    } else if lower.ends_with(".wasm") {
        "application/wasm"
    } else if lower.ends_with(".js") || lower.ends_with(".mjs") {
        "application/javascript; charset=utf-8"
    } else if lower.ends_with(".css") {
        "text/css; charset=utf-8"
    } else if lower.ends_with(".ico") {
        "image/x-icon"
    } else if lower.ends_with(".png") {
        "image/png"
    } else if lower.ends_with(".jpg") || lower.ends_with(".jpeg") {
        "image/jpeg"
    } else if lower.ends_with(".svg") {
        "image/svg+xml"
    } else if lower.ends_with(".json") {
        "application/json; charset=utf-8"
    } else if lower.ends_with(".woff2") {
        "font/woff2"
    } else if lower.ends_with(".woff") {
        "font/woff"
    } else if lower.ends_with(".ttf") {
        "font/ttf"
    } else {
        "application/octet-stream"
    }
}

fn get_embedded_asset(path: &str) -> Option<(&'static [u8], &'static str)> {
    let p = path.trim_start_matches('/').trim_start_matches("./");
    match p {
        "" | "index.html" | "index.htm" => Some((INDEX_HTML, "text/html; charset=utf-8")),
        "editor/pathkit.wasm" | "pathkit.wasm" => Some((PATHKIT_WASM, "application/wasm")),
        "editor/assets/manifold.wasm" | "assets/manifold.wasm" | "manifold.wasm" => {
            Some((MANIFOLD_WASM, "application/wasm"))
        }
        "editor/assets/index.css" | "assets/index.css" | "index.css" => {
            Some((INDEX_CSS, "text/css; charset=utf-8"))
        }
        "editor/assets/index.js" | "assets/index.js" | "index.js" => {
            Some((INDEX_JS, "application/javascript; charset=utf-8"))
        }
        "editor/assets/standalone-runtime.js"
        | "assets/standalone-runtime.js"
        | "standalone-runtime.js" => {
            Some((STANDALONE_RUNTIME_JS, "application/javascript; charset=utf-8"))
        }
        "assets/localforage.min.js" | "localforage.min.js" => {
            Some((LOCALFORAGE_MIN_JS, "application/javascript; charset=utf-8"))
        }
        "cut.ico" | "favicon.ico" | "editor/cut.ico" => Some((CUT_ICO, "image/x-icon")),
        _ => None,
    }
}

fn url_decode(s: &str) -> String {
    let mut result = Vec::new();
    let bytes = s.as_bytes();
    let mut i = 0;
    while i < bytes.len() {
        if bytes[i] == b'%' && i + 2 < bytes.len() {
            if let Ok(val) = u8::from_str_radix(&s[i + 1..i + 3], 16) {
                result.push(val);
                i += 3;
                continue;
            }
        }
        if bytes[i] == b'+' {
            result.push(b' ');
        } else {
            result.push(bytes[i]);
        }
        i += 1;
    }
    String::from_utf8_lossy(&result).into_owned()
}

fn handle_connection(mut stream: TcpStream, project_dir: Option<PathBuf>) {
    let _ = stream.set_read_timeout(Some(Duration::from_secs(5)));
    let _ = stream.set_write_timeout(Some(Duration::from_secs(15)));

    let mut buf = [0u8; 4096];
    let bytes_read = match stream.read(&mut buf) {
        Ok(n) if n > 0 => n,
        _ => return,
    };

    let header_str = String::from_utf8_lossy(&buf[..bytes_read]);
    let mut lines = header_str.lines();
    let request_line = match lines.next() {
        Some(l) => l,
        None => return,
    };

    let mut parts = request_line.split_whitespace();
    let method = parts.next().unwrap_or("");
    let raw_uri = parts.next().unwrap_or("/");

    if method != "GET" && method != "HEAD" {
        let _ = stream.write_all(
            b"HTTP/1.1 405 Method Not Allowed\r\nConnection: close\r\nContent-Length: 0\r\n\r\n",
        );
        return;
    }

    // Strip query string and fragment
    let clean_uri = raw_uri.split('?').next().unwrap_or(raw_uri);
    let clean_uri = clean_uri.split('#').next().unwrap_or(clean_uri);
    let decoded_path = url_decode(clean_uri);
    let trimmed_path = decoded_path.trim_start_matches('/').trim_start_matches("./");

    // Internal health check endpoint for multi-instance detection
    if trimmed_path == "__health" {
        let _ = stream.write_all(
            b"HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nConnection: close\r\nContent-Length: 2\r\n\r\nOK",
        );
        return;
    }

    log_event(&format!("HTTP {} /{}", method, trimmed_path));

    // 1. Check embedded assets first
    if let Some((data, mime)) = get_embedded_asset(trimmed_path) {
        send_response(&mut stream, method == "GET", 200, "OK", mime, data);
        return;
    }

    // 2. Fallback: if running next to loose files on disk, serve them
    if let Some(ref dir) = project_dir {
        let disk_file = dir.join(trimmed_path.replace('/', "\\"));
        if disk_file.is_file() {
            if let Ok(disk_bytes) = fs::read(&disk_file) {
                let mime = get_mime_type(trimmed_path);
                send_response(&mut stream, method == "GET", 200, "OK", mime, &disk_bytes);
                return;
            }
        }
    }

    // 3. Fallback for SPA routing: return index.html if no extension
    if !trimmed_path.contains('.') {
        send_response(
            &mut stream,
            method == "GET",
            200,
            "OK",
            "text/html; charset=utf-8",
            INDEX_HTML,
        );
        return;
    }

    // 4. 404 Not Found
    let not_found = b"HTTP/1.1 404 Not Found\r\nContent-Type: text/plain\r\nConnection: close\r\nContent-Length: 9\r\n\r\nNot Found";
    let _ = stream.write_all(not_found);
}

fn send_response(
    stream: &mut TcpStream,
    send_body: bool,
    status_code: u16,
    status_text: &str,
    content_type: &str,
    body: &[u8],
) {
    let headers = format!(
        "HTTP/1.1 {} {}\r\n\
         Content-Type: {}\r\n\
         Content-Length: {}\r\n\
         Connection: close\r\n\
         Access-Control-Allow-Origin: *\r\n\
         Cache-Control: public, max-age=3600\r\n\
         \r\n",
        status_code,
        status_text,
        content_type,
        body.len()
    );

    let _ = stream.write_all(headers.as_bytes());
    if send_body {
        let _ = stream.write_all(body);
    }
    let _ = stream.flush();
}

fn check_server_health(port: u16) -> bool {
    let addr = SocketAddr::from(([127, 0, 0, 1], port));
    if let Ok(mut stream) = TcpStream::connect_timeout(&addr, Duration::from_millis(300)) {
        let _ = stream.set_read_timeout(Some(Duration::from_millis(500)));
        let req = b"GET /__health HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n";
        if stream.write_all(req).is_ok() {
            let mut buf = [0u8; 64];
            if let Ok(n) = stream.read(&mut buf) {
                return String::from_utf8_lossy(&buf[..n]).contains("200 OK");
            }
        }
    }
    false
}

fn start_server(preferred_port: u16) -> (u16, TcpListener) {
    if let Ok(listener) = TcpListener::bind(format!("127.0.0.1:{}", preferred_port)) {
        return (preferred_port, listener);
    }
    let listener = TcpListener::bind("127.0.0.1:0").expect("Failed to bind local loopback port");
    let port = listener.local_addr().unwrap().port();
    (port, listener)
}

fn find_app_browser() -> Option<PathBuf> {
    let mut candidates = Vec::new();

    // 1. Microsoft Edge (standard Windows paths)
    if let Ok(pf86) = env::var("ProgramFiles(x86)") {
        candidates.push(PathBuf::from(&pf86).join(r"Microsoft\Edge\Application\msedge.exe"));
    }
    if let Ok(pf) = env::var("ProgramFiles") {
        candidates.push(PathBuf::from(&pf).join(r"Microsoft\Edge\Application\msedge.exe"));
    }
    if let Ok(local_app_data) = env::var("LOCALAPPDATA") {
        candidates.push(PathBuf::from(&local_app_data).join(r"Microsoft\Edge\Application\msedge.exe"));
    }

    // 2. Google Chrome (standard Windows paths)
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

fn launch_app_window(browser_exe: &Path, url: &str, profile_dir: &Path) -> Option<std::process::Child> {
    let app_arg = format!("--app={}", url);
    let profile_arg = format!("--user-data-dir={}", profile_dir.display());

    let mut cmd = Command::new(browser_exe);
    cmd.arg(&app_arg)
        .arg(&profile_arg)
        .arg("--name=ModuCut")
        .arg("--window-size=1440,900")
        .arg("--hide-crash-restore-bubble")
        .arg("--no-first-run")
        .arg("--no-default-browser-check");

    cmd.spawn().ok()
}

fn main() {
    let exe_path = env::current_exe().unwrap_or_else(|_| PathBuf::from("."));
    let project_dir = exe_path.parent().map(|p| p.to_path_buf());

    let local_app_data = env::var("LOCALAPPDATA").unwrap_or_else(|_| ".".to_string());
    let moducut_dir = PathBuf::from(&local_app_data).join("ModuCut");
    let profile_dir = moducut_dir.join("Profile");
    let port_file = moducut_dir.join("server.port");
    let _ = fs::create_dir_all(&profile_dir);

    // Check if an existing ModuCut server is already running
    if port_file.exists() {
        if let Ok(saved_port_str) = fs::read_to_string(&port_file) {
            if let Ok(saved_port) = saved_port_str.trim().parse::<u16>() {
                if check_server_health(saved_port) {
                    log_event(&format!("Attaching to existing server on port {}", saved_port));
                    let app_url = format!("http://127.0.0.1:{}", saved_port);
                    if let Some(browser_exe) = find_app_browser() {
                        let _ = launch_app_window(&browser_exe, &app_url, &profile_dir);
                    } else {
                        let _ = Command::new("cmd.exe")
                            .args(["/c", "start", &app_url])
                            .creation_flags(CREATE_NO_WINDOW)
                            .status();
                    }
                    return;
                }
            }
        }
    }

    // Start embedded web server
    let (port, listener) = start_server(PREFERRED_PORT);
    let _ = fs::write(&port_file, port.to_string());
    log_event(&format!("ModuCut server started on port {}", port));

    // Spawn HTTP listener thread
    let dir_clone = project_dir.clone();
    thread::spawn(move || {
        for stream in listener.incoming() {
            if let Ok(stream) = stream {
                let d = dir_clone.clone();
                thread::spawn(move || {
                    handle_connection(stream, d);
                });
            }
        }
    });

    let app_url = format!("http://127.0.0.1:{}", port);

    // Launch standalone window
    if let Some(browser_exe) = find_app_browser() {
        log_event(&format!("Launching browser: {}", browser_exe.display()));
        if let Some(mut child) = launch_app_window(&browser_exe, &app_url, &profile_dir) {
            // Wait for the ModuCut application window to close
            let _ = child.wait();
        }
    } else {
        log_event("Browser not found, falling back to default shell launcher");
        let _ = Command::new("cmd.exe")
            .args(["/c", "start", &app_url])
            .creation_flags(CREATE_NO_WINDOW)
            .status();

        // Keep server alive if standard browser opened
        loop {
            thread::sleep(Duration::from_secs(3600));
        }
    }

    log_event("ModuCut application closed, shutting down.");
    // Cleanup active port file on exit
    let _ = fs::remove_file(&port_file);
}
