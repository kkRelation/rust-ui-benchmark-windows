#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

mod controller;
mod scene;
mod windows;

use std::path::PathBuf;

use controller::BenchApp;
use eframe::egui::{ViewportBuilder, vec2};
use ui_bench_protocol::EventLog;
use windows::MAIN_TITLE;

const FRAMEWORK: &str = "egui";

fn event_log_path() -> PathBuf {
    let mut arguments = std::env::args_os().skip(1);
    while let Some(argument) = arguments.next() {
        if argument == "--event-log" {
            return arguments
                .next()
                .map(PathBuf::from)
                .expect("--event-log requires a path");
        }
    }
    panic!("missing required --event-log <path>");
}

fn main() -> eframe::Result {
    let log = EventLog::create(FRAMEWORK, event_log_path())
        .expect("failed to create benchmark event log");
    let options = eframe::NativeOptions {
        viewport: ViewportBuilder::default()
            .with_title(MAIN_TITLE)
            .with_inner_size(vec2(700.0, 480.0)),
        renderer: eframe::Renderer::Wgpu,
        ..Default::default()
    };

    eframe::run_native(
        MAIN_TITLE,
        options,
        Box::new(move |creation| Ok(Box::new(BenchApp::new(creation, log.clone())))),
    )
}
