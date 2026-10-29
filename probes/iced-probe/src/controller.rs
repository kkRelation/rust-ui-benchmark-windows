use std::io;
use std::thread;
use std::time::{Duration, Instant};

use iced::futures::channel::mpsc;
use iced::{Element, Size, Subscription, Task, Theme, window};
use serde_json::json;
use ui_bench_protocol::{
    Command, EventKind, EventLog, WORKLOAD_STEP_MILLIS, WORKLOAD_STEPS, read_commands,
};

use crate::scene;
use crate::windows::{
    AUXILIARY_TITLE, MAIN_TITLE, set_benchmark_windows_visible, wait_for_benchmark_windows,
};

#[derive(Debug, Clone)]
pub enum Message {
    Opened,
    Selected(usize),
    Exit,
}

pub struct BenchState {
    main: window::Id,
    auxiliary: window::Id,
    selected: usize,
}

impl BenchState {
    pub fn boot(log: EventLog) -> (Self, Task<Message>) {
        let (messages, message_stream) = mpsc::unbounded();
        thread::spawn(move || run_command_loop(log, messages));

        let (main, open_main) = window::open(window::Settings {
            size: Size::new(700.0, 480.0),
            visible: true,
            exit_on_close_request: false,
            ..window::Settings::default()
        });
        let (auxiliary, open_auxiliary) = window::open(window::Settings {
            size: Size::new(1200.0, 760.0),
            visible: true,
            exit_on_close_request: false,
            ..window::Settings::default()
        });

        (
            Self {
                main,
                auxiliary,
                selected: 0,
            },
            Task::batch([
                open_main.map(|_| Message::Opened),
                open_auxiliary.map(|_| Message::Opened),
                Task::run(message_stream, |message| message),
            ]),
        )
    }

    pub fn title(&self, id: window::Id) -> String {
        if id == self.main {
            MAIN_TITLE.to_owned()
        } else if id == self.auxiliary {
            AUXILIARY_TITLE.to_owned()
        } else {
            String::new()
        }
    }

    pub fn theme(&self, _id: window::Id) -> Theme {
        Theme::Dark
    }

    pub fn view(&self, id: window::Id) -> Element<'_, Message> {
        if id == self.main {
            scene::main_view(self.selected)
        } else {
            scene::auxiliary_view(self.selected)
        }
    }

    pub fn subscription(&self) -> Subscription<Message> {
        Subscription::none()
    }

    pub fn update(&mut self, message: Message) -> Task<Message> {
        match message {
            Message::Opened => Task::none(),
            Message::Selected(selected) => {
                self.selected = selected;
                Task::none()
            }
            Message::Exit => iced::exit(),
        }
    }
}

fn run_command_loop(log: EventLog, messages: mpsc::UnboundedSender<Message>) {
    if let Err(error) = wait_for_benchmark_windows() {
        fail(&log, error, &messages);
        return;
    }
    if let Err(error) = set_benchmark_windows_visible(false) {
        fail(&log, error, &messages);
        return;
    }
    if let Err(error) = log.emit(EventKind::ReadyHidden, None) {
        fail(&log, error.to_string(), &messages);
        return;
    }

    let input = io::stdin();
    let result = read_commands(input.lock(), |command| {
        match command {
            Command::Show => emit_around(&log, EventKind::ShowStart, EventKind::ShowEnd, || {
                set_benchmark_windows_visible(true)
            })?,
            Command::Workload => {
                log.emit(EventKind::WorkloadStart, None)
                    .map_err(|error| error.to_string())?;
                let started = Instant::now();
                for update in 0..WORKLOAD_STEPS {
                    messages
                        .unbounded_send(Message::Selected((update + 1) % 72))
                        .map_err(|error| error.to_string())?;
                    let deadline =
                        started + Duration::from_millis((update as u64 + 1) * WORKLOAD_STEP_MILLIS);
                    thread::sleep(deadline.saturating_duration_since(Instant::now()));
                }
                log.emit(EventKind::WorkloadEnd, None)
                    .map_err(|error| error.to_string())?;
            }
            Command::Hide => emit_around(&log, EventKind::HideStart, EventKind::HideEnd, || {
                set_benchmark_windows_visible(false)
            })?,
            Command::Cycle { count } => {
                log.emit(EventKind::CycleStart, Some(json!({ "count": count })))
                    .map_err(|error| error.to_string())?;
                for _ in 0..count {
                    set_benchmark_windows_visible(true)?;
                    thread::sleep(Duration::from_millis(50));
                    set_benchmark_windows_visible(false)?;
                    thread::sleep(Duration::from_millis(50));
                }
                log.emit(EventKind::CycleEnd, Some(json!({ "count": count })))
                    .map_err(|error| error.to_string())?;
            }
            Command::Quit => {
                log.emit(EventKind::Quit, None)
                    .map_err(|error| error.to_string())?;
                messages
                    .unbounded_send(Message::Exit)
                    .map_err(|error| error.to_string())?;
                return Ok(false);
            }
        }
        Ok(true)
    });
    if let Err(error) = result {
        fail(&log, error, &messages);
    }
}

fn emit_around(
    log: &EventLog,
    start: EventKind,
    end: EventKind,
    action: impl FnOnce() -> Result<(), String>,
) -> Result<(), String> {
    log.emit(start, None).map_err(|error| error.to_string())?;
    action()?;
    log.emit(end, None).map_err(|error| error.to_string())
}

fn fail(log: &EventLog, error: String, messages: &mpsc::UnboundedSender<Message>) {
    let _ = log.emit(EventKind::Error, Some(json!({ "message": error })));
    let _ = messages.unbounded_send(Message::Exit);
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn workload_schedule_contains_exactly_four_hundred_shared_updates() {
        let selected = (1..=WORKLOAD_STEPS)
            .map(|completed| completed % 72)
            .collect::<Vec<_>>();
        assert_eq!(selected.len(), 400);
        assert_eq!(selected.last(), Some(&(400 % 72)));
        assert_eq!(WORKLOAD_STEPS as u64 * WORKLOAD_STEP_MILLIS, 8_000);
    }

    #[test]
    fn cycle_has_one_show_and_one_hide_turn_per_count() {
        for count in [1_u16, 30, 1_000] {
            let turns = count * 2;
            assert_eq!(
                (0..turns).filter(|turn| turn % 2 == 0).count(),
                count as usize
            );
            assert_eq!(
                (0..turns).filter(|turn| turn % 2 == 1).count(),
                count as usize
            );
            assert_eq!((turns - 1) % 2, 1);
        }
    }
}
