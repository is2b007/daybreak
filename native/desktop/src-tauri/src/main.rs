// Daybreak for Mac and Windows: a window onto a Daybreak server, the hosted one
// or your own. Sign-in runs in the system browser and comes back through a
// daybreak:// link, the same way as on Android.
#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

use std::fs;
use std::path::PathBuf;

use tauri::{AppHandle, Manager, Url, WebviewUrl, WebviewWindow, WebviewWindowBuilder};
use tauri_plugin_deep_link::DeepLinkExt;
use tauri_plugin_opener::OpenerExt;

const WINDOW: &str = "main";

fn main() {
    tauri::Builder::default()
        // A daybreak:// link opened while Daybreak runs reaches the running app.
        .plugin(tauri_plugin_single_instance::init(|app, _argv, _cwd| {
            if let Some(window) = app.get_webview_window(WINDOW) {
                let _ = window.unminimize();
                let _ = window.set_focus();
            }
        }))
        .plugin(tauri_plugin_deep_link::init())
        .plugin(tauri_plugin_opener::init())
        .invoke_handler(tauri::generate_handler![use_server])
        .setup(|app| {
            // Installers register daybreak:// too; this covers running from a build folder.
            #[cfg(any(windows, target_os = "linux"))]
            if let Err(e) = app.deep_link().register_all() {
                eprintln!("Couldn't register daybreak:// links: {e}");
            }

            let handle = app.handle().clone();
            app.deep_link().on_open_url(move |event| {
                for url in event.urls() {
                    open_link(&handle, &url);
                }
            });

            open_window(app.handle())?;

            if let Some(urls) = app.deep_link().get_current()? {
                for url in urls {
                    open_link(app.handle(), &url);
                }
            }
            Ok(())
        })
        .run(tauri::generate_context!())
        .expect("Daybreak didn't start");
}

// Called by the setup page once it has checked the address is a Daybreak.
#[tauri::command]
fn use_server(app: AppHandle, url: String) -> Result<(), String> {
    let url = Url::parse(url.trim_end_matches('/')).map_err(|e| e.to_string())?;
    fs::write(server_file(&app)?, url.as_str()).map_err(|e| e.to_string())?;
    window(&app)?.navigate(url).map_err(|e| e.to_string())
}

fn open_window(app: &AppHandle) -> tauri::Result<WebviewWindow> {
    let start = match saved_server(app) {
        Some(server) => WebviewUrl::External(server),
        None => WebviewUrl::App("index.html".into()),
    };
    let handle = app.clone();

    WebviewWindowBuilder::new(app, WINDOW, start)
        .title("Daybreak")
        .inner_size(1280.0, 840.0)
        .min_inner_size(400.0, 560.0)
        .user_agent(&user_agent())
        .on_navigation(move |url| allow_navigation(&handle, url))
        .build()
}

// Pages on the server stay in the window. Sign-in and other sites open in the
// system browser; daybreak:// links are handled here.
fn allow_navigation(app: &AppHandle, url: &Url) -> bool {
    match url.scheme() {
        "daybreak" => {
            open_link(app, url);
            false
        }
        _ if is_local(url) => true,
        "http" | "https" => {
            let server = saved_server(app);
            let on_server = server.as_ref().is_some_and(|s| s.host() == url.host() && s.port() == url.port());
            if on_server && url.path() != "/auth/basecamp" {
                return true;
            }

            let mut external = url.clone();
            if on_server {
                external.set_query(Some("native=desktop"));
            }
            let _ = app.opener().open_url(external.as_str(), None::<&str>);
            false
        }
        _ => true,
    }
}

// daybreak://signed-in?code=... comes back from the browser after sign-in;
// daybreak://switch-server comes from the link in Settings.
fn open_link(app: &AppHandle, link: &Url) {
    let Ok(window) = window(app) else { return };
    match link.host_str() {
        Some("signed-in") => {
            let Some(server) = saved_server(app) else { return };
            let Some((_, code)) = link.query_pairs().find(|(key, _)| key == "code") else { return };
            if let Ok(mut target) = server.join("/native/sign_in") {
                target.query_pairs_mut().append_pair("code", &code);
                let _ = window.navigate(target);
            }
            let _ = window.set_focus();
        }
        Some("switch-server") => {
            if let Ok(path) = server_file(app) {
                let _ = fs::remove_file(path);
            }
            if let Ok(local) = local_index() {
                let _ = window.navigate(local);
            }
        }
        _ => {}
    }
}

fn window(app: &AppHandle) -> Result<WebviewWindow, String> {
    app.get_webview_window(WINDOW).ok_or_else(|| "no window".to_string())
}

fn saved_server(app: &AppHandle) -> Option<Url> {
    let text = fs::read_to_string(server_file(app).ok()?).ok()?;
    Url::parse(text.trim()).ok()
}

fn server_file(app: &AppHandle) -> Result<PathBuf, String> {
    let dir = app.path().app_config_dir().map_err(|e| e.to_string())?;
    fs::create_dir_all(&dir).map_err(|e| e.to_string())?;
    Ok(dir.join("server.txt"))
}

// The setup page bundled with the app.
fn local_index() -> Result<Url, String> {
    let base = if cfg!(windows) { "http://tauri.localhost" } else { "tauri://localhost" };
    Url::parse(&format!("{base}/index.html")).map_err(|e| e.to_string())
}

fn is_local(url: &Url) -> bool {
    url.scheme() == "tauri" || url.host_str() == Some("tauri.localhost")
}

// "Daybreak Desktop" tells the server to send sign-in through the system
// browser. The rest keeps the server's browser check happy.
fn user_agent() -> String {
    let version = env!("CARGO_PKG_VERSION");
    if cfg!(windows) {
        format!("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36 Edg/130.0.0.0 Daybreak Desktop/{version}")
    } else {
        format!("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15 Daybreak Desktop/{version}")
    }
}
