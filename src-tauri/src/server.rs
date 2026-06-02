// Local HTTP server that serves compiled game assets from docs/.
// Binds to a random free port on 127.0.0.1 so multiple instances can coexist.

use std::net::SocketAddr;
use std::path::{Component, Path, PathBuf};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex};
use std::thread::{self, JoinHandle};
use std::time::Duration;

use percent_encoding::percent_decode_str;
use tauri::{path::BaseDirectory, Manager};

use crate::error::Error;

pub struct AssetServer {
    addr: SocketAddr,
    shutdown: Arc<AtomicBool>,
    handle: Mutex<Option<JoinHandle<()>>>,
}

impl AssetServer {
    pub fn start(docs_dir: PathBuf) -> Result<Self, Error> {
        let docs_dir = docs_dir.canonicalize().unwrap_or(docs_dir);
        let server = rouille::Server::new("127.0.0.1:0", move |req| serve_request(req, &docs_dir))
            .map_err(|e| Error::ServerBind(e.to_string()))?;

        let addr = server.server_addr();

        let shutdown = Arc::new(AtomicBool::new(false));
        let flag = Arc::clone(&shutdown);

        let handle = thread::spawn(move || {
            while !flag.load(Ordering::Relaxed) {
                server.poll_timeout(Duration::from_millis(200));
            }
        });

        Ok(Self {
            addr,
            shutdown,
            handle: Mutex::new(Some(handle)),
        })
    }

    pub fn port(&self) -> u16 {
        self.addr.port()
    }
}

impl Drop for AssetServer {
    fn drop(&mut self) {
        self.shutdown.store(true, Ordering::Relaxed);
        if let Ok(mut handle) = self.handle.lock() {
            if let Some(h) = handle.take() {
                let _ = h.join();
            }
        }
    }
}

fn serve_request(req: &rouille::Request, docs_dir: &Path) -> rouille::Response {
    let resp = if req.method() == "OPTIONS" {
        rouille::Response::empty_204()
            .with_additional_header("Access-Control-Allow-Methods", "GET, HEAD, OPTIONS")
            .with_additional_header("Access-Control-Allow-Headers", "Content-Type")
    } else {
        match request_path(req.url()) {
            Ok(path) => serve_file(docs_dir, path),
            Err(_) => rouille::Response::text("forbidden").with_status_code(403),
        }
    };

    with_local_cors(req, resp)
}

fn serve_file(docs_dir: &Path, path: PathBuf) -> rouille::Response {
    let full_path = docs_dir.join(path);
    let resolved = match full_path.canonicalize() {
        Ok(path) if path.starts_with(docs_dir) && path.is_file() => path,
        _ => return rouille::Response::text("not found").with_status_code(404),
    };

    match std::fs::File::open(&resolved) {
        Ok(file) => rouille::Response::from_file(content_type(&resolved), file),
        Err(_) => rouille::Response::text("not found").with_status_code(404),
    }
}

fn request_path(url: String) -> Result<PathBuf, ()> {
    let path = url.split('?').next().unwrap_or("/");
    let path = path.trim_start_matches('/');
    let path = if path.is_empty() { "index.html" } else { path };
    let decoded = percent_decode_str(path).decode_utf8().map_err(|_| ())?;

    let mut clean = PathBuf::new();
    for component in Path::new(decoded.as_ref()).components() {
        match component {
            Component::Normal(part) => clean.push(part),
            Component::CurDir => {}
            _ => return Err(()),
        }
    }

    if clean.as_os_str().is_empty() {
        clean.push("index.html");
    }

    Ok(clean)
}

fn content_type(path: &Path) -> &'static str {
    match path
        .extension()
        .and_then(|ext| ext.to_str())
        .unwrap_or_default()
        .to_ascii_lowercase()
        .as_str()
    {
        "html" => "text/html; charset=utf-8",
        "js" | "mjs" => "application/javascript; charset=utf-8",
        "json" => "application/json; charset=utf-8",
        "css" => "text/css; charset=utf-8",
        "wasm" => "application/wasm",
        "bin" => "application/octet-stream",
        "webp" => "image/webp",
        "png" => "image/png",
        "jpg" | "jpeg" => "image/jpeg",
        "gif" => "image/gif",
        "svg" => "image/svg+xml",
        "ico" => "image/x-icon",
        "mp3" => "audio/mpeg",
        "ogg" => "audio/ogg",
        "wav" => "audio/wav",
        "m4a" => "audio/mp4",
        "mp4" => "video/mp4",
        "ttf" => "font/ttf",
        "otf" => "font/otf",
        "woff" => "font/woff",
        "woff2" => "font/woff2",
        _ => "application/octet-stream",
    }
}

fn with_local_cors(req: &rouille::Request, resp: rouille::Response) -> rouille::Response {
    match req.header("Origin") {
        Some(origin) if is_local_origin(origin) => resp
            .with_additional_header("Access-Control-Allow-Origin", origin.to_owned())
            .with_additional_header("Vary", "Origin"),
        _ => resp,
    }
}

fn is_local_origin(origin: &str) -> bool {
    is_loopback_origin(origin, "http://127.0.0.1:")
        || is_loopback_origin(origin, "http://localhost:")
}

fn is_loopback_origin(origin: &str, prefix: &str) -> bool {
    origin
        .strip_prefix(prefix)
        .is_some_and(|port| !port.is_empty() && port.chars().all(|c| c.is_ascii_digit()))
}

pub fn find_docs_dir(app: &tauri::App) -> Result<PathBuf, Error> {
    let resource = app.path().resolve("docs", BaseDirectory::Resource)?;
    if resource.exists() {
        return Ok(resource.canonicalize().unwrap_or(resource));
    }

    let dev = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../docs");
    if dev.exists() {
        return Ok(dev.canonicalize().unwrap_or(dev));
    }

    Err(Error::DocsNotFound)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn root_requests_resolve_to_index() {
        assert_eq!(
            request_path("/".to_string()).unwrap(),
            PathBuf::from("index.html")
        );
        assert_eq!(
            request_path("/index.html".to_string()).unwrap(),
            PathBuf::from("index.html")
        );
    }

    #[test]
    fn request_paths_are_decoded_and_normalized() {
        assert_eq!(
            request_path("/assets/main/config.json?cache=1".to_string()).unwrap(),
            PathBuf::from("assets/main/config.json")
        );
        assert_eq!(
            request_path("/assets/a%20b.json".to_string()).unwrap(),
            PathBuf::from("assets/a b.json")
        );
    }

    #[test]
    fn traversal_paths_are_rejected() {
        assert!(request_path("/../Cargo.toml".to_string()).is_err());
        assert!(request_path("/%2e%2e/Cargo.toml".to_string()).is_err());
        assert!(request_path("/%2fetc/passwd".to_string()).is_err());
    }

    #[test]
    fn wasm_is_served_with_wasm_mime_type() {
        assert_eq!(content_type(Path::new("bullet.wasm")), "application/wasm");
    }
}
