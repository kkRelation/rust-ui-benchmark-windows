use std::io;
use std::thread;
use std::time::{Duration, Instant};

use makepad_widgets::UiRunner;
use serde_json::json;
use ui_bench_protocol::{
    Command, EventKind, EventLog, WORKLOAD_STEP_MILLIS, WORKLOAD_STEPS, read_commands,
};

use crate::app::App;
use crate::scene::ENTRY_COUNT;
use crate::visibility::{
    close_benchmark_windows, normalize_benchmark_window_sizes, set_benchmark_windows_visible,
    stabilize_benchmark_windows_hidden, wait_for_benchmark_windows,
};

const FRAMEWORK: &str = "makepad";

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

fn selection_for_update(update: usize) -> usize {
    (update + 1) % ENTRY_COUNT
}

fn cycle_visibility(count: u16) -> impl Iterator<Item = bool> {
    (0..count).flat_map(|_| [true, false])
}

fn readiness_complete(initial_visible: bool, normalized: bool, hidden_stable: bool) -> bool {
    initial_visible && normalized && hidden_stable
}

fn handle_command(command: Command, runner: UiRunner<App>, log: &EventLog) -> Result<bool, String> {
    match command {
        Command::Show => {
            log.emit(EventKind::ShowStart, None)
                .map_err(|error| error.to_string())?;
            set_benchmark_windows_visible(true)?;
            log.emit(EventKind::ShowEnd, None)
                .map_err(|error| error.to_string())?;
        }
        Command::Workload => {
            log.emit(EventKind::WorkloadStart, None)
                .map_err(|error| error.to_string())?;
            let started = Instant::now();
            for update in 0..WORKLOAD_STEPS {
                let selected = selection_for_update(update);
                runner.defer(move |app, cx, _scope| app.set_selected(cx, selected));
                let deadline =
                    started + Duration::from_millis((update as u64 + 1) * WORKLOAD_STEP_MILLIS);
                thread::sleep(deadline.saturating_duration_since(Instant::now()));
            }
            log.emit(EventKind::WorkloadEnd, None)
                .map_err(|error| error.to_string())?;
        }
        Command::Hide => {
            log.emit(EventKind::HideStart, None)
                .map_err(|error| error.to_string())?;
            set_benchmark_windows_visible(false)?;
            log.emit(EventKind::HideEnd, None)
                .map_err(|error| error.to_string())?;
        }
        Command::Cycle { count } => {
            log.emit(EventKind::CycleStart, Some(json!({ "count": count })))
                .map_err(|error| error.to_string())?;
            for visible in cycle_visibility(count) {
                set_benchmark_windows_visible(visible)?;
                thread::sleep(Duration::from_millis(50));
            }
            log.emit(EventKind::CycleEnd, Some(json!({ "count": count })))
                .map_err(|error| error.to_string())?;
        }
        Command::Quit => {
            log.emit(EventKind::Quit, None)
                .map_err(|error| error.to_string())?;
            close_benchmark_windows()?;
            return Ok(false);
        }
    }
    Ok(true)
}

pub fn start_controller(runner: UiRunner<App>) {
    let log = EventLog::create(FRAMEWORK, event_log_path())
        .expect("failed to create benchmark event log");
    thread::spawn(move || {
        let result = (|| -> Result<(), String> {
            wait_for_benchmark_windows(Duration::from_secs(30))?;
            normalize_benchmark_window_sizes()?;
            stabilize_benchmark_windows_hidden(Duration::from_secs(3), Duration::from_millis(500))?;
            debug_assert!(readiness_complete(true, true, true));
            log.emit(EventKind::ReadyHidden, None)
                .map_err(|error| error.to_string())?;

            let input = io::stdin();
            read_commands(input.lock(), |command| {
                handle_command(command, runner, &log)
            })
        })();

        if let Err(error) = result {
            let _ = log.emit(EventKind::Error, Some(json!({ "message": error })));
            let _ = close_benchmark_windows();
        }
    });
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn readiness_requires_all_lifecycle_gates() {
        assert!(readiness_complete(true, true, true));
        assert!(!readiness_complete(false, true, true));
        assert!(!readiness_complete(true, false, true));
        assert!(!readiness_complete(true, true, false));
    }

    #[test]
    fn workload_has_exact_count_timing_and_modulo_selection() {
        let selections = (0..WORKLOAD_STEPS)
            .map(selection_for_update)
            .collect::<Vec<_>>();
        assert_eq!(selections.len(), 400);
        assert_eq!(selections.last(), Some(&(400 % ENTRY_COUNT)));
        assert_eq!(WORKLOAD_STEPS as u64 * WORKLOAD_STEP_MILLIS, 8_000);
    }

    #[test]
    fn cycle_alternates_and_finishes_hidden() {
        for count in [1_u16, 30, 1_000] {
            let states = cycle_visibility(count).collect::<Vec<_>>();
            assert_eq!(states.len(), count as usize * 2);
            assert_eq!(states.first(), Some(&true));
            assert_eq!(states.last(), Some(&false));
        }
    }
}
