// Cardinal pour Windows et Linux : une fenêtre native autour de l'interface web.
// Le moteur (Swift compilé en WebAssembly) tourne dans la page ; Rust ne fait que la fenêtre,
// les boîtes de dialogue de fichiers et la transmission du fichier ouvert par double-clic.

use std::path::PathBuf;

/// Fichier passé au lancement (double-clic sur un .mcd ou un .loo, ou « Ouvrir avec »).
#[tauri::command]
fn fichier_initial() -> Option<String> {
    std::env::args_os()
        .skip(1)
        .map(PathBuf::from)
        .find(|chemin| {
            chemin
                .extension()
                .and_then(|e| e.to_str())
                .map(|e| e.eq_ignore_ascii_case("mcd") || e.eq_ignore_ascii_case("loo"))
                .unwrap_or(false)
                && chemin.is_file()
        })
        .map(|chemin| chemin.to_string_lossy().into_owned())
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_dialog::init())
        .plugin(tauri_plugin_fs::init())
        .invoke_handler(tauri::generate_handler![fichier_initial])
        .run(tauri::generate_context!())
        .expect("Cardinal n'a pas pu démarrer");
}
