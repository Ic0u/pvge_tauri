// Local HTTP server that serves compiled game assets from docs/.
// Binds to a stable port on 127.0.0.1 or fallbacks to a free port.

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
    handles: Mutex<Vec<JoinHandle<()>>>,
}

impl AssetServer {
    /// Preferred port keeps localStorage stable across launches so game saves persist.
    const PREFERRED_PORT: u16 = 21073;

    pub fn start(docs_dir: PathBuf) -> Result<Self, Error> {
        let docs_dir = docs_dir.canonicalize().unwrap_or(docs_dir);

        // Try binding to the preferred port first to see if it is available.
        // If available, we use it to preserve localStorage (game saves) across launches.
        // Otherwise, fallback to port 0 (random port).
        let bind_addr = if std::net::TcpListener::bind(("127.0.0.1", Self::PREFERRED_PORT)).is_ok()
        {
            format!("127.0.0.1:{}", Self::PREFERRED_PORT)
        } else {
            "127.0.0.1:0".to_string()
        };

        let server =
            tiny_http::Server::http(bind_addr).map_err(|e| Error::ServerBind(e.to_string()))?;

        let tiny_http::ListenAddr::IP(addr) = server.server_addr() else {
            return Err(Error::ServerBind("invalid server address".into()));
        };
        let server = Arc::new(server);

        let shutdown = Arc::new(AtomicBool::new(false));
        let mut handles = Vec::new();

        // Spawn a small pool of worker threads (e.g., 4 threads) to handle game asset requests
        // in parallel. This prevents single-threaded blocking of heavy Cocos asset loads.
        for _ in 0..4 {
            let flag = Arc::clone(&shutdown);
            let srv = Arc::clone(&server);
            let dir = docs_dir.clone();
            let handle = thread::spawn(move || {
                while !flag.load(Ordering::Relaxed) {
                    match srv.try_recv() {
                        Ok(Some(req)) => handle_request(req, &dir),
                        Ok(None) => thread::sleep(Duration::from_millis(15)),
                        Err(_) => break,
                    }
                }
            });
            handles.push(handle);
        }

        Ok(Self {
            addr,
            shutdown,
            handles: Mutex::new(handles),
        })
    }

    pub fn port(&self) -> u16 {
        self.addr.port()
    }
}

impl Drop for AssetServer {
    fn drop(&mut self) {
        self.shutdown.store(true, Ordering::Relaxed);
        if let Ok(mut handles) = self.handles.lock() {
            for h in handles.drain(..) {
                let _ = h.join();
            }
        }
    }
}

fn handle_request(req: tiny_http::Request, docs_dir: &Path) {
    let method = req.method().as_str();
    let url = req.url().to_owned();

    let mut response = if method == "OPTIONS" {
        make_response(
            204,
            vec![
                tiny_http::Header::from_bytes(
                    b"Access-Control-Allow-Methods",
                    b"GET, HEAD, OPTIONS",
                )
                .unwrap(),
                tiny_http::Header::from_bytes(b"Access-Control-Allow-Headers", b"Content-Type")
                    .unwrap(),
            ],
            Box::new(std::io::empty()),
            Some(0),
        )
    } else if method == "GET" || method == "HEAD" {
        match request_path(&url) {
            Ok(path) => serve_file(docs_dir, &path),
            Err(()) => make_response(403, vec![], Box::new(std::io::empty()), Some(0)),
        }
    } else {
        make_response(405, vec![], Box::new(std::io::empty()), Some(0))
    };

    // Extract Origin header and apply local CORS
    let origin_header = req
        .headers()
        .iter()
        .find(|h| h.field.as_str().as_str().eq_ignore_ascii_case("Origin"))
        .map(|h| h.value.as_str());

    if let Some(origin) = origin_header {
        if is_local_origin(origin) {
            if let Ok(h) =
                tiny_http::Header::from_bytes(b"Access-Control-Allow-Origin", origin.as_bytes())
            {
                response = response.with_header(h);
            }
            if let Ok(h) = tiny_http::Header::from_bytes(b"Vary", b"Origin") {
                response = response.with_header(h);
            }
        }
    }

    let _ = req.respond(response);
}

fn make_response(
    status: u16,
    headers: Vec<tiny_http::Header>,
    reader: Box<dyn std::io::Read + Send>,
    size: Option<usize>,
) -> tiny_http::Response<Box<dyn std::io::Read + Send>> {
    tiny_http::Response::new(tiny_http::StatusCode(status), headers, reader, size, None)
}

fn serve_file(docs_dir: &Path, path: &Path) -> tiny_http::Response<Box<dyn std::io::Read + Send>> {
    let full_path = docs_dir.join(path);
    let resolved = match full_path.canonicalize() {
        Ok(path) if path.starts_with(docs_dir) && path.is_file() => path,
        _ => return make_response(404, vec![], Box::new(std::io::empty()), Some(0)),
    };

    let extension = resolved
        .extension()
        .and_then(|ext| ext.to_str())
        .unwrap_or_default()
        .to_ascii_lowercase();

    let Ok(file) = std::fs::File::open(&resolved) else {
        return make_response(404, vec![], Box::new(std::io::empty()), Some(0));
    };

    let file_len = file
        .metadata()
        .ok()
        .and_then(|m| usize::try_from(m.len()).ok());

    let mime = content_type(&resolved);
    let mut headers =
        vec![tiny_http::Header::from_bytes(b"Content-Type", mime.as_bytes()).unwrap()];

    let cache_control = if extension == "html" || extension == "json" {
        "no-cache, no-store, must-revalidate"
    } else {
        "public, max-age=31536000, immutable"
    };

    headers
        .push(tiny_http::Header::from_bytes(b"Cache-Control", cache_control.as_bytes()).unwrap());

    make_response(200, headers, Box::new(file), file_len)
}

fn request_path(url: &str) -> Result<PathBuf, ()> {
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
        assert_eq!(request_path("/").unwrap(), PathBuf::from("index.html"));
        assert_eq!(
            request_path("/index.html").unwrap(),
            PathBuf::from("index.html")
        );
    }

    #[test]
    fn request_paths_are_decoded_and_normalized() {
        assert_eq!(
            request_path("/assets/main/config.json?cache=1").unwrap(),
            PathBuf::from("assets/main/config.json")
        );
        assert_eq!(
            request_path("/assets/a%20b.json").unwrap(),
            PathBuf::from("assets/a b.json")
        );
    }

    #[test]
    fn traversal_paths_are_rejected() {
        assert!(request_path("/../Cargo.toml").is_err());
        assert!(request_path("/%2e%2e/Cargo.toml").is_err());
        assert!(request_path("/%2fetc/passwd").is_err());
    }

    #[test]
    fn wasm_is_served_with_wasm_mime_type() {
        assert_eq!(content_type(Path::new("bullet.wasm")), "application/wasm");
    }

    #[test]
    fn local_origins_are_validated() {
        assert!(is_local_origin("http://127.0.0.1:8080"));
        assert!(is_local_origin("http://localhost:3000"));
        assert!(is_local_origin("http://localhost:1"));
        assert!(!is_local_origin("http://example.com"));
        assert!(!is_local_origin("https://play.pvzge.com"));
        assert!(!is_local_origin("http://127.0.0.1.attacker.com:8080"));
        assert!(!is_local_origin("http://localhost.attacker.com:3000"));
    }
}
