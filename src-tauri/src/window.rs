use tauri::{Manager, WebviewUrl, WebviewWindowBuilder};
use tauri_plugin_notification::NotificationExt;

use crate::error::Error;

const VERSION: &str = env!("CARGO_PKG_VERSION");
const REPO: &str = "Ic0u/pvge_tauri";

pub fn setup(app: &tauri::App, port: u16) -> Result<(), Error> {
    let url: tauri::Url = format!("http://127.0.0.1:{port}")
        .parse()
        .map_err(|_| Error::ServerBind("invalid server URL".into()))?;

    WebviewWindowBuilder::new(app, "main", WebviewUrl::External(url))
        .title("PvZ2 Gardendless")
        .inner_size(1280.0, 720.0)
        .min_inner_size(800.0, 500.0)
        .initialization_script(INIT_SCRIPT)
        .build()?;

    if is_first_launch(app) {
        // Native macOS / Linux notification — appears in Notification Center, not in-game.
        let _ = app
            .notification()
            .builder()
            .title(format!("PvZ2 Gardendless v{VERSION}"))
            .body("Game by Gaozih & the PvZ2 Gardendless Team\n\nmacOS port by Marcus Nguyen ❤️")
            .show();

        let _ = app
            .notification()
            .builder()
            .title("What's New in v0.9.3")
            .body("PvZ2_Prerelease_AF_P2\n\n• Aerial Fortress Part 2\n• Plant-Decoding Minigame\n• New plants, zombies, and card decks")
            .show();
    }

    spawn_update_check(app.handle().clone());

    Ok(())
}

// Background check against GitHub Releases. Uses the system `curl` (always present
// on macOS and pulled in by the Linux build deps) so we add no HTTP/TLS crates.
// On a newer release it fires a native notification — never blocks startup.
fn spawn_update_check(handle: tauri::AppHandle) {
    std::thread::spawn(move || {
        let Some((latest_tag, release_notes)) = fetch_latest_release() else {
            return;
        };
        if version_is_newer(&latest_tag, VERSION) {
            let clean_notes = if release_notes.is_empty() {
                format!("You're on v{VERSION}. Re-run the installer to update.")
            } else {
                let lines: Vec<&str> = release_notes
                    .lines()
                    .map(str::trim)
                    .filter(|l| {
                        !l.is_empty()
                            && (l.starts_with('•') || l.starts_with('*') || l.starts_with('-'))
                    })
                    .collect();
                if lines.is_empty() {
                    format!("New updates available in {latest_tag}!")
                } else {
                    let summary = lines
                        .iter()
                        .take(3)
                        .copied()
                        .collect::<Vec<&str>>()
                        .join("\n");
                    if lines.len() > 3 {
                        format!("{summary}\n• ... and more!")
                    } else {
                        summary
                    }
                }
            };

            let _ = handle
                .notification()
                .builder()
                .title(format!("Update available · {latest_tag}"))
                .body(format!(
                    "New in {latest_tag}:\n{clean_notes}\n\nRe-run the installer to update!"
                ))
                .show();
        }
    });
}

fn fetch_latest_release() -> Option<(String, String)> {
    let url = format!("https://api.github.com/repos/{REPO}/releases/latest");
    let output = std::process::Command::new("curl")
        .args([
            "-fsSL",
            "--max-time",
            "8",
            "-H",
            "User-Agent: pvzge-desktop",
            &url,
        ])
        .output()
        .ok()?;
    if !output.status.success() {
        return None;
    }
    let body = String::from_utf8_lossy(&output.stdout);

    // Extract tag_name
    let after_tag = body.split("\"tag_name\"").nth(1)?;
    let tag_start = after_tag.find('"')? + 1;
    let tag_end = after_tag[tag_start..].find('"')? + tag_start;
    let tag = after_tag[tag_start..tag_end].trim().to_string();

    // Extract body (release notes)
    let notes = if let Some(after_body) = body.split("\"body\"").nth(1) {
        let body_start = after_body.find('"')? + 1;
        let body_end = after_body[body_start..].find('"')? + body_start;
        let escaped_notes = &after_body[body_start..body_end];
        escaped_notes
            .replace("\\r\\n", "\n")
            .replace("\\n", "\n")
            .replace("\\\"", "\"")
            .replace("\\\\", "\\")
    } else {
        String::new()
    };

    if tag.is_empty() {
        None
    } else {
        Some((tag, notes))
    }
}

// Numeric, dot-separated comparison tolerant of a leading 'v' and trailing suffixes.
fn version_is_newer(latest: &str, current: &str) -> bool {
    fn parts(v: &str) -> Vec<u64> {
        v.trim()
            .trim_start_matches('v')
            .split('.')
            .map(|p| {
                p.chars()
                    .take_while(char::is_ascii_digit)
                    .collect::<String>()
                    .parse()
                    .unwrap_or(0)
            })
            .collect()
    }
    let (a, b) = (parts(latest), parts(current));
    for i in 0..a.len().max(b.len()) {
        let x = a.get(i).copied().unwrap_or(0);
        let y = b.get(i).copied().unwrap_or(0);
        if x != y {
            return x > y;
        }
    }
    false
}

#[cfg(test)]
mod tests {
    use super::version_is_newer;

    #[test]
    fn detects_newer_versions() {
        assert!(version_is_newer("v0.9.3", "0.8.3"));
        assert!(version_is_newer("v1.0.0", "0.9.9"));
        assert!(version_is_newer("0.8.10", "0.8.2"));
    }

    #[test]
    fn ignores_same_or_older() {
        assert!(!version_is_newer("v0.8.2", "0.8.2"));
        assert!(!version_is_newer("v0.8.1", "0.8.2"));
        assert!(!version_is_newer("v0.8.2-beta", "0.8.2"));
    }
}

fn is_first_launch(app: &tauri::App) -> bool {
    let Ok(dir) = app.path().app_data_dir() else {
        return false;
    };
    let marker = dir.join(format!(".seen-{VERSION}"));
    if marker.exists() {
        return false;
    }
    let _ = std::fs::create_dir_all(&dir);
    let _ = std::fs::write(&marker, []);
    true
}

// Injected into every page load: forces the canvas to fill the window
// and wires F4/F11 to toggle native fullscreen.
const INIT_SCRIPT: &str = r"(function(){
function applyDesktopCss(){
  if(document.getElementById('pvzge-desktop-css')) return;
  var s=document.createElement('style');
  s.id='pvzge-desktop-css';
  s.textContent='html,body,#GameDiv,#Cocos3dGameContainer,#GameCanvas{width:100%!important;height:100%!important;margin:0!important;overflow:hidden!important;}';
  (document.head||document.documentElement).appendChild(s);
}
function isFullscreen(){
  return document.fullscreenElement||document.webkitFullscreenElement||
         document.mozFullScreenElement||document.msFullscreenElement;
}
function toggleFullscreen(){
  if(isFullscreen()){
    var ex=document.exitFullscreen||document.webkitExitFullscreen||
            document.mozCancelFullScreen||document.msExitFullscreen;
    if(ex) ex.call(document);
  } else {
    var el=document.documentElement;
    var en=el.requestFullscreen||el.webkitRequestFullscreen||
            el.mozRequestFullScreen||el.msRequestFullscreen;
    if(en) en.call(el);
  }
}
document.addEventListener('keydown',function(e){
  if(e.key==='F4'||e.key==='F11'){e.preventDefault();toggleFullscreen();}
},true);
if(document.readyState==='loading'){
  document.addEventListener('DOMContentLoaded',applyDesktopCss,{once:true});
}else{
  applyDesktopCss();
}
})();";
