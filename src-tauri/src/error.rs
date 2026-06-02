// Unified error type for all application failures.

use std::fmt;

#[derive(Debug)]
pub enum Error {
    DocsNotFound,
    ServerBind(String),
    Tauri(tauri::Error),
}

impl fmt::Display for Error {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::DocsNotFound => write!(f, "game assets directory not found"),
            Self::ServerBind(msg) => write!(f, "failed to start asset server: {msg}"),
            Self::Tauri(e) => write!(f, "tauri: {e}"),
        }
    }
}

impl std::error::Error for Error {
    fn source(&self) -> Option<&(dyn std::error::Error + 'static)> {
        match self {
            Self::Tauri(e) => Some(e),
            _ => None,
        }
    }
}

impl From<tauri::Error> for Error {
    fn from(e: tauri::Error) -> Self {
        Self::Tauri(e)
    }
}
