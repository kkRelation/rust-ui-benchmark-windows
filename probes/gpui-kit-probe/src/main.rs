#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

mod controller;
mod scene;
mod windows;

use async_channel::bounded;
use gpui_kit::{App, AppContext};
use ui_bench_protocol::EventLog;

use controller::{run_controller, start_command_reader};
use scene::{AuxiliaryView, MainView, window_options};
use windows::normalize_benchmark_window_sizes;

const FRAMEWORK: &str = "gpui-kit";

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

    gpui_kit::application().run(move |cx: &mut App| {
        // This is the production-facing boundary under test: init installs
        // gpui-component/gpui-base, and open_window wraps content in Base Root.
        gpui_kit::init(cx);
        let (main_window, main_view) = gpui_kit::open_window(
            window_options("UI Framework Bench - Main", 700.0, 480.0, cx),
            cx,
            |_, cx| cx.new(|_| MainView::new()),
        )
        .expect("failed to open main benchmark window");
        let (auxiliary_window, auxiliary_view) = gpui_kit::open_window(
            window_options("UI Framework Bench - Auxiliary Canvas", 1200.0, 760.0, cx),
            cx,
            |_, cx| cx.new(|_| AuxiliaryView::new()),
        )
        .expect("failed to open auxiliary benchmark window");

        let main_window = main_window
            .downcast::<gpui_kit::base::Root>()
            .expect("gpui-kit main window must be Base Root wrapped");
        let auxiliary_window = auxiliary_window
            .downcast::<gpui_kit::base::Root>()
            .expect("gpui-kit auxiliary window must be Base Root wrapped");

        // gpui-pre 0.3.10 creates initially hidden Windows HWNDs at the work
        // area size. Normalize the native frames before the ready checkpoint;
        // 15x34 is the measured decoration inset at this fixed DPI/environment.
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
