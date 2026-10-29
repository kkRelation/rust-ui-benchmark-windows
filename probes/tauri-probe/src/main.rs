#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

use std::io;
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::Arc;
use std::thread;
use std::time::{Duration, Instant};

use serde_json::json;
use tauri::{Emitter, Manager, WebviewUrl, WebviewWindowBuilder};
use ui_bench_protocol::{
    read_commands, Command, EventKind, EventLog, WORKLOAD_STEPS, WORKLOAD_STEP_MILLIS,
};

const FRAMEWORK: &str = "tauri";
const WINDOW_LABELS: [&str; 2] = ["main", "auxiliary"];

fn event_log_path() -> Result<std::path::PathBuf, String> {
    let mut arguments = std::env::args_os().skip(1);
    while let Some(argument) = arguments.next() {
        if argument == "--event-log" {
            return arguments
                .next()
                .map(Into::into)
                .ok_or_else(|| "--event-log requires a path".to_owned());
        }
    }
    Err("missing required --event-log <path>".to_owned())
}

fn set_visible(app: &tauri::AppHandle, visible: bool) -> Result<(), String> {
    for label in WINDOW_LABELS {
        let window = app
            .get_webview_window(label)
            .ok_or_else(|| format!("missing window {label}"))?;
        if visible {
            window.show().map_err(|error| error.to_string())?;
        } else {
            window.hide().map_err(|error| error.to_string())?;
        }
    }
    Ok(())
}

fn run_workload(app: &tauri::AppHandle) -> Result<(), String> {
    let started = Instant::now();
    for update in 0..WORKLOAD_STEPS {
        let selected = (update + 1) % 72;
        for label in WINDOW_LABELS {
            app.get_webview_window(label)
                .ok_or_else(|| format!("missing window {label}"))?
                .emit("bench-selection", selected)
                .map_err(|error| error.to_string())?;
        }
        let deadline = started + Duration::from_millis((update as u64 + 1) * WORKLOAD_STEP_MILLIS);
        thread::sleep(deadline.saturating_duration_since(Instant::now()));
    }
    Ok(())
}

fn execute_command(
    app: &tauri::AppHandle,
    log: &EventLog,
    command: Command,
) -> Result<bool, String> {
    match command {
        Command::Show => {
            log.emit(EventKind::ShowStart, None)
                .map_err(|error| error.to_string())?;
            set_visible(app, true)?;
            log.emit(EventKind::ShowEnd, None)
                .map_err(|error| error.to_string())?;
        }
        Command::Workload => {
            log.emit(EventKind::WorkloadStart, None)
                .map_err(|error| error.to_string())?;
            run_workload(app)?;
            log.emit(EventKind::WorkloadEnd, None)
                .map_err(|error| error.to_string())?;
        }
        Command::Hide => {
            log.emit(EventKind::HideStart, None)
                .map_err(|error| error.to_string())?;
            set_visible(app, false)?;
            log.emit(EventKind::HideEnd, None)
                .map_err(|error| error.to_string())?;
        }
        Command::Cycle { count } => {
            log.emit(EventKind::CycleStart, Some(json!({ "count": count })))
                .map_err(|error| error.to_string())?;
            for _ in 0..count {
                set_visible(app, true)?;
                thread::sleep(Duration::from_millis(50));
                set_visible(app, false)?;
                thread::sleep(Duration::from_millis(50));
            }
            log.emit(EventKind::CycleEnd, Some(json!({ "count": count })))
                .map_err(|error| error.to_string())?;
        }
        Command::Quit => {
            log.emit(EventKind::Quit, None)
                .map_err(|error| error.to_string())?;
            app.exit(0);
            return Ok(false);
        }
    }
    Ok(true)
}

fn main() {
    let path = event_log_path().unwrap_or_else(|error| panic!("{error}"));
    let log = EventLog::create(FRAMEWORK, path).expect("failed to create benchmark event log");
    let loaded_windows = Arc::new(AtomicUsize::new(0));

    tauri::Builder::default()
        .setup({
            let log = log.clone();
            let loaded_windows = Arc::clone(&loaded_windows);
            move |app| {
                for (label, title, width, height) in [
                    ("main", "UI Framework Bench - Main", 700.0, 480.0),
                    (
                        "auxiliary",
                        "UI Framework Bench - Auxiliary Canvas",
                        1200.0,
                        760.0,
                    ),
                ] {
                    let loaded_windows = Arc::clone(&loaded_windows);
                    let log = log.clone();
                    WebviewWindowBuilder::new(
                        app,
                        label,
                        WebviewUrl::App(format!("index.html?view={label}").into()),
                    )
                    .title(title)
                    .inner_size(width, height)
                    .visible(false)
                    .on_page_load(move |_window, payload| {
                        if matches!(payload.event(), tauri::webview::PageLoadEvent::Finished)
                            && loaded_windows.fetch_add(1, Ordering::AcqRel) == 1
                        {
                            log.emit(EventKind::ReadyHidden, None)
                                .expect("failed to write ready event");
                        }
                    })
                    .build()?;
                }

                let app_handle = app.handle().clone();
                let command_log = log.clone();
                thread::spawn(move || {
                    let input = io::stdin();
                    let result = read_commands(input.lock(), |command| {
                        execute_command(&app_handle, &command_log, command)
                    });
                    if let Err(error) = result {
                        let _ =
                            command_log.emit(EventKind::Error, Some(json!({ "message": error })));
                        app_handle.exit(2);
                    }
                });
                Ok(())
            }
        })
        .run(tauri::generate_context!())
        .expect("failed to run Tauri framework benchmark");
}
