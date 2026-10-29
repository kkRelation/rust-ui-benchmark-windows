#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

mod controller;
mod scene;
mod windows;

use std::path::PathBuf;

use controller::BenchState;
use iced::daemon;
use ui_bench_protocol::EventLog;

const FRAMEWORK: &str = "iced";

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

fn main() -> iced::Result {
    let log = EventLog::create(FRAMEWORK, event_log_path())
        .expect("failed to create benchmark event log");

    daemon(
        move || BenchState::boot(log.clone()),
        BenchState::update,
        BenchState::view,
    )
    .title(BenchState::title)
    .subscription(BenchState::subscription)
    .theme(BenchState::theme)
    .run()
}
