#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

mod controller;
mod scene;
mod visibility;

use kas::runner::Runner;
use ui_bench_protocol::EventLog;

use controller::{BenchData, start_controller};
use scene::{auxiliary_window, main_window};

const FRAMEWORK: &str = "kas";

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

    // Select KAS's normal WGPU runner explicitly. Only the DX12 backend is
    // compiled for this Windows benchmark contestant.
    let mut runner = Runner::with_wgpu_pipe(())
        .with_wgpu_options(kas_wgpu::Options::default())
        .read_env_vars(false)
        .with_default_theme()
        .build(BenchData::default())
        .expect("failed to create KAS WGPU runner");
    runner.add(main_window());
    runner.add(auxiliary_window());

    let proxy = runner.create_proxy();
    start_controller(proxy, log);
    runner.run().expect("KAS runner failed");
}
