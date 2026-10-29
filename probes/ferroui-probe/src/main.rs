#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

mod application;
mod controller;
mod scene;

use ferroui::prelude::*;

fn main() -> std::process::ExitCode {
    let arguments: Vec<String> = std::env::args().skip(1).collect();
    let exit_code = AppBuilder::configure::<application::BenchApplication>()
        .use_platform_detect()
        .start_with_classic_desktop_lifetime(&arguments);
    std::process::ExitCode::from(exit_code as u8)
}
