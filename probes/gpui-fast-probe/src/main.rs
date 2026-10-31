#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

mod controller;
mod scene;
mod windows;

use async_channel::bounded;
use gpui::{App, AppContext};
use ui_bench_protocol::EventLog;

use controller::{run_controller, start_command_reader};
use scene::{AuxiliaryView, MainView, window_options};
use windows::normalize_benchmark_window_sizes;

const FRAMEWORK: &str = "gpui-fast";

fn event_log_path() -> std::path::PathBuf {
    let mut arguments = std::env::args_os().skip(1);
    while let Some(argument) = arguments.next() {
        if argument == "--event-log" {
            return arguments
                .next()
                .map(Into::into)
                .expect("--event-log requires a path");
        }
    }
    panic!("missing required --event-log <path>");
}

fn main() {
    let log = EventLog::create(FRAMEWORK, event_log_path())
        .expect("failed to create benchmark event log");
    let (command_sender, command_receiver) = bounded(16);
    start_command_reader(command_sender, log.clone());

    gpui_platform::application().run(move |cx: &mut App| {
        let main_view = cx.new(|_| MainView::new());
        let auxiliary_view = cx.new(|_| AuxiliaryView::new());
        let main_window = cx
            .open_window(
                window_options("UI Framework Bench - Main", 700.0, 480.0, cx),
                |_, _| main_view.clone(),
            )
            .expect("failed to open main benchmark window");
        let auxiliary_window = cx
            .open_window(
                window_options("UI Framework Bench - Auxiliary Canvas", 1200.0, 760.0, cx),
                |_, _| auxiliary_view.clone(),
            )
            .expect("failed to open auxiliary benchmark window");

        normalize_benchmark_window_sizes().unwrap();
        log.emit(ui_bench_protocol::EventKind::ReadyHidden, None)
            .unwrap();
        cx.spawn(async move |cx| {
            run_controller(
                command_receiver,
                main_window,
                main_view,
                auxiliary_window,
                auxiliary_view,
                log,
                cx,
            )
            .await
        })
        .detach();
    });
}
