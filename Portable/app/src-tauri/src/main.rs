// Empêche l'ouverture d'une console en plus de la fenêtre sous Windows (version finale).
#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

fn main() {
    cardinal_lib::run();
}
