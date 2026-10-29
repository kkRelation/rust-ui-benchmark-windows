use std::io;
use std::sync::mpsc::{self, Receiver, Sender};
use std::thread;
use std::time::{Duration, Instant};

use eframe::egui::{self, ViewportBuilder, ViewportCommand, ViewportId, vec2};
use serde_json::json;
use ui_bench_protocol::{
    Command, EventKind, EventLog, WORKLOAD_STEP_MILLIS, WORKLOAD_STEPS, read_commands,
};

use crate::scene;
use crate::windows::{AUXILIARY_TITLE, set_benchmark_windows_visible, wait_for_benchmark_windows};

enum Message {
    Selected(usize),
    Exit,
}

pub struct BenchApp {
    selected: usize,
    messages: Receiver<Message>,
}

impl BenchApp {
    pub fn new(creation: &eframe::CreationContext<'_>, log: EventLog) -> Self {
        creation.egui_ctx.set_theme(egui::Theme::Dark);
        let (messages, receiver) = mpsc::channel();
        let context = creation.egui_ctx.clone();
        thread::spawn(move || run_command_loop(log, messages, context));
        Self {
            selected: 0,
            messages: receiver,
        }
    }
}

impl eframe::App for BenchApp {
    fn logic(&mut self, context: &egui::Context, _frame: &mut eframe::Frame) {
        while let Ok(message) = self.messages.try_recv() {
            match message {
                Message::Selected(selected) => self.selected = selected,
                Message::Exit => context.send_viewport_cmd(ViewportCommand::Close),
            }
        }
    }

    fn ui(&mut self, ui: &mut egui::Ui, _frame: &mut eframe::Frame) {
        scene::main_view(ui, self.selected);
        let selected = self.selected;
        ui.ctx().show_viewport_deferred(
            ViewportId::from_hash_of("egui-benchmark-auxiliary"),
            ViewportBuilder::default()
                .with_title(AUXILIARY_TITLE)
                .with_inner_size(vec2(1200.0, 760.0)),
            move |ui, _class| scene::auxiliary_view(ui, selected),
        );
    }
}

fn run_command_loop(log: EventLog, messages: Sender<Message>, context: egui::Context) {
    if let Err(error) = wait_for_benchmark_windows() {
        fail(&log, error, &messages, &context);
        return;
    }
    if let Err(error) = set_benchmark_windows_visible(false) {
        fail(&log, error, &messages, &context);
        return;
    }
    if let Err(error) = log.emit(EventKind::ReadyHidden, None) {
        fail(&log, error.to_string(), &messages, &context);
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
                        .send(Message::Selected((update + 1) % 72))
                        .map_err(|error| error.to_string())?;
                    context.request_repaint();
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
                    .send(Message::Exit)
                    .map_err(|error| error.to_string())?;
                context.request_repaint();
                return Ok(false);
            }
        }
        Ok(true)
    });
    if let Err(error) = result {
        fail(&log, error, &messages, &context);
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

fn fail(log: &EventLog, error: String, messages: &Sender<Message>, context: &egui::Context) {
    let _ = log.emit(EventKind::Error, Some(json!({ "message": error })));
    let _ = messages.send(Message::Exit);
    context.request_repaint();
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
