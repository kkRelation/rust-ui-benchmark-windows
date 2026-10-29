use std::io;
use std::thread;
use std::time::{Duration, Instant};

use kas::runner::{AppData, Proxy, ReadMessage};
use serde_json::json;
use ui_bench_protocol::{
    Command, EventKind, EventLog, WORKLOAD_STEP_MILLIS, WORKLOAD_STEPS, read_commands,
};

use crate::visibility::{
    normalize_benchmark_window_sizes, set_visible_for_benchmark_windows,
    stabilize_benchmark_windows_hidden, wait_for_benchmark_windows,
};

#[derive(Default)]
pub struct BenchData {
    pub selected: usize,
}

#[derive(Debug)]
struct Select(usize);

impl AppData for BenchData {
    fn handle_message(&mut self, messages: &mut impl ReadMessage) {
        while let Some(Select(selected)) = messages.try_pop::<Select>() {
            self.selected = selected;
        }
    }
}

fn selection_for_update(update: usize) -> usize {
    (update + 1) % 72
}

fn cycle_visibility(count: u16) -> impl Iterator<Item = bool> {
    (0..count).flat_map(|_| [true, false])
}

fn handle_command(command: Command, proxy: &mut Proxy, log: &EventLog) -> Result<bool, String> {
    match command {
        Command::Show => {
            log.emit(EventKind::ShowStart, None)
                .map_err(|error| error.to_string())?;
            set_visible_for_benchmark_windows(true)?;
            log.emit(EventKind::ShowEnd, None)
                .map_err(|error| error.to_string())?;
        }
        Command::Workload => {
            log.emit(EventKind::WorkloadStart, None)
                .map_err(|error| error.to_string())?;
            let started = Instant::now();
            for update in 0..WORKLOAD_STEPS {
                proxy
                    .push(Select(selection_for_update(update)))
                    .map_err(|_| "KAS runner closed during workload".to_string())?;
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
            set_visible_for_benchmark_windows(false)?;
            log.emit(EventKind::HideEnd, None)
                .map_err(|error| error.to_string())?;
        }
        Command::Cycle { count } => {
            log.emit(EventKind::CycleStart, Some(json!({ "count": count })))
                .map_err(|error| error.to_string())?;
            for visible in cycle_visibility(count) {
                set_visible_for_benchmark_windows(visible)?;
                thread::sleep(Duration::from_millis(50));
            }
            log.emit(EventKind::CycleEnd, Some(json!({ "count": count })))
                .map_err(|error| error.to_string())?;
        }
        Command::Quit => {
            log.emit(EventKind::Quit, None)
                .map_err(|error| error.to_string())?;
            proxy
                .close_all()
                .map_err(|_| "KAS runner closed before quit".to_string())?;
            return Ok(false);
        }
    }
    Ok(true)
}

pub fn start_controller(mut proxy: Proxy, log: EventLog) {
    thread::spawn(move || {
        let result = (|| -> Result<(), String> {
            wait_for_benchmark_windows(Duration::from_secs(30))?;
            normalize_benchmark_window_sizes()?;
            stabilize_benchmark_windows_hidden(Duration::from_secs(3), Duration::from_millis(500))?;
            log.emit(EventKind::ReadyHidden, None)
                .map_err(|error| error.to_string())?;

            let input = io::stdin();
            read_commands(input.lock(), |command| {
                handle_command(command, &mut proxy, &log)
            })
        })();

        if let Err(error) = result {
            let _ = log.emit(EventKind::Error, Some(json!({ "message": error })));
            let _ = proxy.close_all();
        }
    });
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn shared_workload_has_exact_count_timing_and_selection() {
        let selections = (0..WORKLOAD_STEPS)
            .map(selection_for_update)
            .collect::<Vec<_>>();
        assert_eq!(selections.len(), 400);
        assert_eq!(selections.last(), Some(&(400 % 72)));
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

    #[test]
    fn app_data_uses_one_shared_selected_value() {
        let mut data = BenchData::default();
        data.selected = selection_for_update(31);
        assert_eq!(data.selected, 32);
    }
}
