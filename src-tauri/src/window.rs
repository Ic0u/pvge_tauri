use tauri::{Manager, WebviewUrl, WebviewWindowBuilder};
use tauri_plugin_notification::NotificationExt;

use crate::error::Error;

const VERSION: &str = env!("CARGO_PKG_VERSION");

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
            .title("What's New in v0.8.2")
            .body("• Added Asparagus, Pineapple, Anthurium\n• Added Battleplane, Transport Boat, Double-Cabin Aircraft, Lightning Gun, Imp Paratrooper, Airborne Gargantuar\n• Added Aerial Fortress Levels\n• Added Recommended & Challenging Card Decks for Aerial Fortress")
            .show();
    }

    Ok(())
}

fn is_first_launch(app: &tauri::App) -> bool {
    let dir = match app.path().app_data_dir() {
        Ok(d) => d,
        Err(_) => return false,
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
const INIT_SCRIPT: &str = r#"(function(){
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
})();"#;
