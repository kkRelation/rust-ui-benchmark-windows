#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

mod app;
mod controller;
mod scene;
mod visibility;

fn main() {
    app::app_main()
}
