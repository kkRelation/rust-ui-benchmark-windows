use std::io;
use std::sync::mpsc::{self, Receiver};
use std::thread;
use std::time::{Duration, Instant};

use iced::{Element, Size, Subscription, Task, Theme, time, window};
use serde_json::json;
use ui_bench_protocol::{
    Command, EventKind, EventLog, WORKLOAD_STEP_MILLIS, WORKLOAD_STEPS, read_commands,
};

use crate::scene;
use crate::windows::{
    AUXILIARY_TITLE, MAIN_TITLE, benchmark_windows_ready, set_benchmark_windows_visible,
};

const TICK_MILLIS: u64 = 5;

#[derive(Debug, Clone)]
pub enum Message {
    Opened(window::Id),
    Tick(Instant),
}

#[derive(Debug, Clone, Copy)]
enum Activity {
    Idle,
    Workload {
        completed: usize,
        next: Instant,
    },
    Cycle {
        count: u16,
        turns: u16,
        next: Instant,
    },
}

pub struct BenchState {
    main: window::Id,
    auxiliary: window::Id,
    selected: usize,
    ready: bool,
    opened: usize,
    commands: Receiver<Command>,
    activity: Activity,
    log: EventLog,
}

impl BenchState {
    pub fn boot(log: EventLog) -> (Self, Task<Message>) {
        let (command_sender, commands) = mpsc::channel();
        let thread_log = log.clone();
        thread::spawn(move || {
            let input = io::stdin();
            if let Err(error) = read_commands(input.lock(), |command| {
                let quitting = matches!(command, Command::Quit);
                command_sender
                    .send(command)
                    .map_err(|send_error| send_error.to_string())?;
                Ok(!quitting)
            }) {
                let _ = thread_log.emit(EventKind::Error, Some(json!({ "message": error })));
            }
        });

        let (main, open_main) = window::open(window::Settings {
            size: Size::new(700.0, 480.0),
            visible: false,
            exit_on_close_request: false,
            ..window::Settings::default()
        });
        let (auxiliary, open_auxiliary) = window::open(window::Settings {
            size: Size::new(1200.0, 760.0),
            visible: false,
            exit_on_close_request: false,
            ..window::Settings::default()
        });

        (
            Self {
                main,
                auxiliary,
                selected: 0,
                ready: false,
                opened: 0,
                commands,
                activity: Activity::Idle,
                log,
            },
            Task::batch([
                open_main.map(Message::Opened),
                open_auxiliary.map(Message::Opened),
            ]),
        )
    }

    pub fn title(&self, id: window::Id) -> String {
        if id == self.main {
            MAIN_TITLE.to_owned()
        } else {
            AUXILIARY_TITLE.to_owned()
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
        time::every(Duration::from_millis(TICK_MILLIS)).map(Message::Tick)
    }

    pub fn update(&mut self, message: Message) -> Task<Message> {
        match message {
            Message::Opened(id) => {
                if id == self.main || id == self.auxiliary {
                    self.opened += 1;
                }
            }
            Message::Tick(now) => {
                if !self.ready {
                    if self.opened == 2 {
                        match benchmark_windows_ready() {
                            Ok(true) => {
                                if let Err(error) = set_benchmark_windows_visible(false) {
                                    return self.fail(error);
                                }
                                self.ready = true;
                                if let Err(error) = self.log.emit(EventKind::ReadyHidden, None) {
                                    return self.fail(error.to_string());
                                }
                            }
                            Ok(false) => {}
                            Err(error) => return self.fail(error),
                        }
                    }
                    return Task::none();
                }

                if let Err(error) = self.advance_activity(now) {
                    return self.fail(error);
                }
                if matches!(self.activity, Activity::Idle) {
                    match self.commands.try_recv() {
                        Ok(command) => return self.start_command(command, now),
                        Err(mpsc::TryRecvError::Empty) => {}
                        Err(mpsc::TryRecvError::Disconnected) => {}
                    }
                }
            }
        }
        Task::none()
    }

    fn start_command(&mut self, command: Command, now: Instant) -> Task<Message> {
        let result = match command {
            Command::Show => self.emit_around(EventKind::ShowStart, EventKind::ShowEnd, || {
                set_benchmark_windows_visible(true)
            }),
            Command::Workload => {
                if let Err(error) = self.log.emit(EventKind::WorkloadStart, None) {
                    return self.fail(error.to_string());
                }
                self.activity = Activity::Workload {
                    completed: 0,
                    next: now + Duration::from_millis(WORKLOAD_STEP_MILLIS),
                };
                Ok(())
            }
            Command::Hide => self.emit_around(EventKind::HideStart, EventKind::HideEnd, || {
                set_benchmark_windows_visible(false)
            }),
            Command::Cycle { count } => {
                if let Err(error) = self
                    .log
                    .emit(EventKind::CycleStart, Some(json!({ "count": count })))
                {
                    return self.fail(error.to_string());
                }
                self.activity = Activity::Cycle {
                    count,
                    turns: 0,
                    next: now,
                };
                Ok(())
            }
            Command::Quit => {
                if let Err(error) = self.log.emit(EventKind::Quit, None) {
                    return self.fail(error.to_string());
                }
                return iced::exit();
            }
        };

        match result {
            Ok(()) => Task::none(),
            Err(error) => self.fail(error),
        }
    }

    fn emit_around(
        &self,
        start: EventKind,
        end: EventKind,
        action: impl FnOnce() -> Result<(), String>,
    ) -> Result<(), String> {
        self.log
            .emit(start, None)
            .map_err(|error| error.to_string())?;
        action()?;
        self.log.emit(end, None).map_err(|error| error.to_string())
    }

    fn advance_activity(&mut self, now: Instant) -> Result<(), String> {
        match self.activity {
            Activity::Idle => {}
            Activity::Workload {
                mut completed,
                mut next,
            } => {
                while completed < WORKLOAD_STEPS && now >= next {
                    completed += 1;
                    self.selected = completed % 72;
                    next += Duration::from_millis(WORKLOAD_STEP_MILLIS);
                }
                if completed == WORKLOAD_STEPS {
                    self.activity = Activity::Idle;
                    self.log
                        .emit(EventKind::WorkloadEnd, None)
                        .map_err(|error| error.to_string())?;
                } else {
                    self.activity = Activity::Workload { completed, next };
                }
            }
            Activity::Cycle {
                count,
                mut turns,
                mut next,
            } => {
                while turns < count * 2 && now >= next {
                    let visible = turns % 2 == 0;
                    set_benchmark_windows_visible(visible)?;
                    turns += 1;
                    next += Duration::from_millis(50);
                }
                if turns == count * 2 {
                    self.activity = Activity::Idle;
                    self.log
                        .emit(EventKind::CycleEnd, Some(json!({ "count": count })))
                        .map_err(|error| error.to_string())?;
                } else {
                    self.activity = Activity::Cycle { count, turns, next };
                }
            }
        }
        Ok(())
    }

    fn fail(&self, error: String) -> Task<Message> {
        let _ = self
            .log
            .emit(EventKind::Error, Some(json!({ "message": error })));
        iced::exit()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn workload_reducer_performs_exactly_four_hundred_shared_updates() {
        let started = Instant::now();
        let mut selected = 0;
        let mut completed = 0;
        let mut next = started + Duration::from_millis(WORKLOAD_STEP_MILLIS);
        let finished = started + Duration::from_millis(WORKLOAD_STEP_MILLIS * 400);
        while completed < WORKLOAD_STEPS && finished >= next {
            completed += 1;
            selected = completed % 72;
            next += Duration::from_millis(WORKLOAD_STEP_MILLIS);
        }
        assert_eq!(completed, 400);
        assert_eq!(selected, 400 % 72);
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
