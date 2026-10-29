use std::io;
use std::sync::mpsc;
use std::thread;
use std::time::{Duration, Instant};

use ferroui::base::threading::{Dispatcher, DispatcherPriority};
use serde_json::{json, Value};
use ui_bench_protocol::{
    read_commands, Command, EventKind, EventLog, WORKLOAD_STEPS, WORKLOAD_STEP_MILLIS,
};

use crate::application;
use crate::scene::ENTRY_COUNT;

const FRAMEWORK: &str = "ferroui";

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum UiRequest {
    InitializeHidden,
    SetVisible(bool),
    SetSelection(usize),
    Barrier,
    Quit,
}

pub fn readiness_complete(created: bool, sized: bool, hidden: bool) -> bool {
    created && sized && hidden
}

pub fn selection_for_update(update: usize) -> usize {
    (update + 1) % ENTRY_COUNT
}

pub fn command_requests(command: Command) -> Vec<UiRequest> {
    match command {
        Command::Show => vec![UiRequest::SetVisible(true)],
        Command::Hide => vec![UiRequest::SetVisible(false)],
        Command::Workload => (0..WORKLOAD_STEPS)
            .map(selection_for_update)
            .map(UiRequest::SetSelection)
            .collect(),
        Command::Cycle { count } => (0..count)
            .flat_map(|_| [UiRequest::SetVisible(true), UiRequest::SetVisible(false)])
            .collect(),
        Command::Quit => vec![UiRequest::Quit],
    }
}

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

fn dispatch_request(
    request: UiRequest,
    completion: Option<(EventLog, EventKind, Option<Value>)>,
) -> Result<(), String> {
    let (sender, receiver) = mpsc::sync_channel(1);
    Dispatcher::ui_thread().post(
        move || {
            let mut result = application::apply_request(request);
            if result.is_ok() {
                if let Some((log, event, detail)) = completion {
                    result = log.emit(event, detail).map_err(|error| error.to_string());
                }
            }
            let _ = sender.send(result);
        },
        DispatcherPriority::DEFAULT,
    );
    receiver
        .recv_timeout(Duration::from_secs(30))
        .map_err(|error| format!("FerroUI dispatcher did not acknowledge request: {error}"))?
}

fn handle_command(command: Command, log: &EventLog) -> Result<bool, String> {
    match command {
        Command::Show => {
            log.emit(EventKind::ShowStart, None)
                .map_err(|error| error.to_string())?;
            dispatch_request(
                UiRequest::SetVisible(true),
                Some((log.clone(), EventKind::ShowEnd, None)),
            )?;
        }
        Command::Workload => {
            log.emit(EventKind::WorkloadStart, None)
                .map_err(|error| error.to_string())?;
            let started = Instant::now();
            for update in 0..WORKLOAD_STEPS {
                dispatch_request(UiRequest::SetSelection(selection_for_update(update)), None)?;
                let deadline =
                    started + Duration::from_millis((update as u64 + 1) * WORKLOAD_STEP_MILLIS);
                thread::sleep(deadline.saturating_duration_since(Instant::now()));
            }
            dispatch_request(
                UiRequest::Barrier,
                Some((log.clone(), EventKind::WorkloadEnd, None)),
            )?;
        }
        Command::Hide => {
            log.emit(EventKind::HideStart, None)
                .map_err(|error| error.to_string())?;
            dispatch_request(
                UiRequest::SetVisible(false),
                Some((log.clone(), EventKind::HideEnd, None)),
            )?;
        }
        Command::Cycle { count } => {
            let detail = Some(json!({ "count": count }));
            log.emit(EventKind::CycleStart, detail.clone())
                .map_err(|error| error.to_string())?;
            for request in command_requests(Command::Cycle { count }) {
                dispatch_request(request, None)?;
                thread::sleep(Duration::from_millis(50));
            }
            dispatch_request(
                UiRequest::Barrier,
                Some((log.clone(), EventKind::CycleEnd, detail)),
            )?;
        }
        Command::Quit => {
            dispatch_request(UiRequest::Quit, Some((log.clone(), EventKind::Quit, None)))?;
            return Ok(false);
        }
    }
    Ok(true)
}

pub fn start_controller() {
    let log = EventLog::create(FRAMEWORK, event_log_path())
        .expect("failed to create benchmark event log");
    thread::spawn(move || {
        let result = (|| -> Result<(), String> {
            dispatch_request(
                UiRequest::InitializeHidden,
                Some((log.clone(), EventKind::ReadyHidden, None)),
            )?;
            let input = io::stdin();
            read_commands(input.lock(), |command| handle_command(command, &log))
        })();

        if let Err(error) = result {
            let _ = log.emit(EventKind::Error, Some(json!({ "message": error })));
            let _ = dispatch_request(UiRequest::Quit, None);
        }
    });
}

#[cfg(test)]
mod tests {
    use super::{command_requests, readiness_complete, selection_for_update, UiRequest};
    use crate::scene::{project_selection, ENTRY_COUNT, KEY_COUNT};
    use ui_bench_protocol::{Command, WORKLOAD_STEPS, WORKLOAD_STEP_MILLIS};

    #[test]
    fn readiness_requires_created_sized_and_hidden_windows() {
        assert!(readiness_complete(true, true, true));
        assert!(!readiness_complete(false, true, true));
        assert!(!readiness_complete(true, false, true));
        assert!(!readiness_complete(true, true, false));
    }

    #[test]
    fn workload_dispatches_exactly_400_timed_modulo_72_updates() {
        let requests = command_requests(Command::Workload);
        let selections = requests
            .iter()
            .filter_map(|request| match request {
                UiRequest::SetSelection(selected) => Some(*selected),
                _ => None,
            })
            .collect::<Vec<_>>();

        assert_eq!(WORKLOAD_STEPS, 400);
        assert_eq!(WORKLOAD_STEP_MILLIS, 20);
        assert_eq!(requests.len(), 400);
        assert_eq!(selections.len(), 400);
        assert_eq!(selections.first(), Some(&1));
        assert_eq!(selections.last(), Some(&40));
        assert_eq!(selection_for_update(399), 40);
    }

    #[test]
    fn one_selection_projects_into_both_scenes() {
        assert_eq!(ENTRY_COUNT, 72);
        assert_eq!(KEY_COUNT, 66);

        let projection = project_selection(71);
        assert_eq!(projection.main_row, 71);
        assert_eq!(projection.auxiliary_key, 5);
    }

    #[test]
    fn cycle_count_becomes_exact_alternating_ui_dispatch_requests() {
        let requests = command_requests(Command::Cycle { count: 30 });

        assert_eq!(requests.len(), 60);
        assert_eq!(requests.first(), Some(&UiRequest::SetVisible(true)));
        assert_eq!(requests.last(), Some(&UiRequest::SetVisible(false)));
        assert!(requests.windows(2).all(|pair| pair[0] != pair[1]));
    }

    #[test]
    fn show_hide_and_quit_each_request_one_ui_thread_operation() {
        assert_eq!(
            command_requests(Command::Show),
            vec![UiRequest::SetVisible(true)]
        );
        assert_eq!(
            command_requests(Command::Hide),
            vec![UiRequest::SetVisible(false)]
        );
        assert_eq!(command_requests(Command::Quit), vec![UiRequest::Quit]);
    }
}
