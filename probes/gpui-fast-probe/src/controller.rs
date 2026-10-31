use std::io;
use std::thread;
use std::time::{Duration, Instant};

use async_channel::{Receiver, Sender};
use gpui::{AsyncApp, Entity, WindowHandle};
use serde_json::json;
use ui_bench_protocol::{
    Command, EventKind, EventLog, WORKLOAD_STEP_MILLIS, WORKLOAD_STEPS, read_commands,
};

use crate::scene::{AuxiliaryView, MainView};
use crate::windows::set_benchmark_windows_visible;

pub fn start_command_reader(sender: Sender<Command>, log: EventLog) {
    thread::spawn(move || {
        let input = io::stdin();
        if let Err(error) = read_commands(input.lock(), |command| {
            sender
                .send_blocking(command)
                .map_err(|error| error.to_string())?;
            Ok(!matches!(command, Command::Quit))
        }) {
            let _ = log.emit(EventKind::Error, Some(json!({ "message": error })));
        }
    });
}

#[allow(clippy::too_many_arguments)]
pub async fn run_controller(
    commands: Receiver<Command>,
    _main_window: WindowHandle<MainView>,
    main_view: Entity<MainView>,
    _auxiliary_window: WindowHandle<AuxiliaryView>,
    auxiliary_view: Entity<AuxiliaryView>,
    log: EventLog,
    cx: &mut AsyncApp,
) {
    while let Ok(command) = commands.recv().await {
        match command {
            Command::Show => {
                log.emit(EventKind::ShowStart, None).unwrap();
                set_benchmark_windows_visible(true).unwrap();
                log.emit(EventKind::ShowEnd, None).unwrap();
            }
            Command::Workload => {
                log.emit(EventKind::WorkloadStart, None).unwrap();
                let started = Instant::now();
                for update in 0..WORKLOAD_STEPS {
                    let selected = (update + 1) % 72;
                    main_view.update(cx, |view, cx| {
                        view.selected = selected;
                        cx.notify();
                    });
                    auxiliary_view.update(cx, |view, cx| {
                        view.selected = selected;
                        cx.notify();
                    });
                    let deadline =
                        started + Duration::from_millis((update as u64 + 1) * WORKLOAD_STEP_MILLIS);
                    cx.background_executor()
                        .timer(deadline.saturating_duration_since(Instant::now()))
                        .await;
                }
                log.emit(EventKind::WorkloadEnd, None).unwrap();
            }
            Command::Hide => {
                log.emit(EventKind::HideStart, None).unwrap();
                set_benchmark_windows_visible(false).unwrap();
                log.emit(EventKind::HideEnd, None).unwrap();
            }
            Command::Cycle { count } => {
                log.emit(EventKind::CycleStart, Some(json!({ "count": count })))
                    .unwrap();
                for _ in 0..count {
                    set_benchmark_windows_visible(true).unwrap();
                    cx.background_executor()
                        .timer(Duration::from_millis(50))
                        .await;
                    set_benchmark_windows_visible(false).unwrap();
                    cx.background_executor()
                        .timer(Duration::from_millis(50))
                        .await;
                }
                log.emit(EventKind::CycleEnd, Some(json!({ "count": count })))
                    .unwrap();
            }
            Command::Quit => {
                log.emit(EventKind::Quit, None).unwrap();
                cx.update(|cx| cx.quit());
                break;
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn shared_workload_has_exactly_four_hundred_modulo_seventy_two_updates() {
        let selections = (0..WORKLOAD_STEPS)
            .map(|update| (update + 1) % 72)
            .collect::<Vec<_>>();
        assert_eq!(selections.len(), 400);
        assert_eq!(selections.last(), Some(&(400 % 72)));
        assert_eq!(WORKLOAD_STEPS as u64 * WORKLOAD_STEP_MILLIS, 8_000);
    }

    #[test]
    fn cycle_finishes_hidden_after_two_turns_per_count() {
        for count in [1_u16, 30, 1_000] {
            let turns = count * 2;
            assert_eq!(turns % 2, 0);
            assert_eq!((turns - 1) % 2, 1);
        }
    }
}
