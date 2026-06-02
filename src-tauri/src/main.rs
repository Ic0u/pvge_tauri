// Entry point. Starts the local asset server, then launches the Tauri window.
#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

mod error;
mod server;
mod window;

use tauri::Manager;

fn main() {
    tauri::Builder::default()
        .plugin(tauri_plugin_notification::init())
        .setup(|app| {
            let docs_dir = server::find_docs_dir(app)?;
            let asset_server = server::AssetServer::start(docs_dir)?;
            let port = asset_server.port();

            app.manage(asset_server);
            window::setup(app, port)?;

            Ok(())
        })
        .run(tauri::generate_context!())
        .expect("tauri application crashed");
}
