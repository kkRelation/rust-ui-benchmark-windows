#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

use std::cell::Cell;
use std::io;
use std::rc::Rc;
use std::thread;
use std::time::Duration;

use serde_json::json;
use slint::{ComponentHandle, ModelRc, SharedString, Timer, TimerMode, VecModel};
use ui_bench_protocol::{
    read_commands, Command, EventKind, EventLog, WORKLOAD_STEPS, WORKLOAD_STEP_MILLIS,
};

const FRAMEWORK: &str = "slint";

slint::slint! {
    import { ScrollView } from "std-widgets.slint";

    export struct BenchRow {
        shortcut: string,
        description: string,
        section: string,
    }

    export component MainBench inherits Window {
        in property <[BenchRow]> rows;
        in-out property <int> selected: 0;
        title: "UI Framework Bench - Main";
        width: 700px;
        height: 480px;
        background: #0d1117;
        default-font-family: "Segoe UI";

        VerticalLayout {
            padding: 18px;
            spacing: 12px;
            HorizontalLayout {
                Text { text: "Shortcut Palette"; color: #f0f6fc; font-size: 25px; font-weight: 700; }
                Rectangle {
                    width: 116px; height: 30px; border-radius: 15px; background: #1f6feb33;
                    Text { text: "72 ENTRIES"; color: #79c0ff; font-size: 11px; font-weight: 700; horizontal-alignment: center; vertical-alignment: center; }
                }
            }
            Rectangle {
                height: 54px; border-radius: 12px; background: #161b22; border-width: 1px; border-color: #30363d;
                Text { x: 16px; y: 9px; text: "Search shortcuts, commands, facets, and object memory"; color: #c9d1d9; font-size: 15px; }
                Text { x: 16px; y: 31px; text: "Static benchmark corpus · selection drives the auxiliary canvas"; color: #8b949e; font-size: 11px; }
            }
            Rectangle {
                border-radius: 12px; background: #0d1117; border-width: 1px; border-color: #30363d; clip: true;
                ScrollView {
                    viewport-width: self.width;
                    viewport-height: root.rows.length * 44px;
                    for row[i] in root.rows : Rectangle {
                        y: i * 44px; width: parent.width; height: 44px;
                        background: i == root.selected ? #1f6feb44 : Math.mod(i, 2) == 0 ? #0d1117 : #11161c;
                        Rectangle { width: 4px; height: parent.height; background: i == root.selected ? #58a6ff : #00000000; }
                        Text { x: 14px; y: 12px; width: 128px; text: row.shortcut; color: i == root.selected ? #ffffff : #c9d1d9; font-size: 13px; font-weight: 700; }
                        Text { x: 150px; y: 12px; width: 360px; text: row.description; color: #c9d1d9; font-size: 13px; }
                        Text { x: parent.width - 122px; y: 12px; width: 104px; text: row.section; color: #8b949e; font-size: 12px; horizontal-alignment: right; }
                    }
                }
            }
        }
    }

    component BenchKey inherits Rectangle {
        in property <string> label;
        in property <bool> selected;
        width: 64px; height: 42px; border-radius: 8px;
        background: selected ? #2f81f7 : #21262d;
        border-width: 1px; border-color: selected ? #79c0ff : #30363d;
        Text { text: root.label; color: root.selected ? #ffffff : #c9d1d9; font-size: 12px; font-weight: 700; horizontal-alignment: center; vertical-alignment: center; }
    }

    export component AuxiliaryBench inherits Window {
        in property <[string]> keys;
        in-out property <int> selected: 0;
        title: "UI Framework Bench - Auxiliary Canvas";
        width: 1200px;
        height: 760px;
        background: #080b10;
        default-font-family: "Segoe UI";

        Rectangle {
            x: 24px; y: 22px; width: 1138px; height: 114px; border-radius: 16px; background: #161b22; border-width: 1px; border-color: #30363d;
            Text { x: 20px; y: 16px; text: "Object Memory Preview"; color: #79c0ff; font-size: 13px; font-weight: 700; }
            Text { x: 20px; y: 43px; text: "Selected action " + (root.selected + 1) + ": move, focus, or transform the active object"; color: #f0f6fc; font-size: 18px; font-weight: 700; }
            Text { x: 20px; y: 72px; width: 1050px; text: "Representative defining expression, scenario annotation, availability note, source path, and extended explanation."; color: #8b949e; font-size: 12px; }
        }
        Rectangle {
            x: 24px; y: 154px; width: 854px; height: 560px; border-radius: 18px; background: #0d1117; border-width: 1px; border-color: #30363d;
            Text { x: 22px; y: 16px; text: "Binding Atlas · modifier plane and related bindings"; color: #f0f6fc; font-size: 16px; font-weight: 700; }
            for key[i] in root.keys : BenchKey {
                x: 22px + Math.mod(i, 11) * 74px; y: 58px + floor(i / 11) * 52px;
                label: key; selected: Math.mod(root.selected, root.keys.length) == i;
            }
        }
        Rectangle {
            x: 896px; y: 154px; width: 266px; height: 172px; border-radius: 16px; background: #161b22; border-width: 1px; border-color: #30363d;
            Text { x: 18px; y: 15px; text: "Navigation"; color: #79c0ff; font-size: 14px; font-weight: 700; }
            Text { x: 18px; y: 48px; text: "H  J  K  L"; color: #f0f6fc; font-size: 21px; font-weight: 700; }
            Text { x: 18px; y: 86px; text: "word · line · page · history"; color: #8b949e; font-size: 12px; }
            Text { x: 18px; y: 113px; text: "selected relation " + Math.mod(root.selected, 12); color: #c9d1d9; font-size: 12px; }
        }
        Rectangle {
            x: 896px; y: 344px; width: 266px; height: 172px; border-radius: 16px; background: #161b22; border-width: 1px; border-color: #30363d;
            Text { x: 18px; y: 15px; text: "Numpad / Operations"; color: #79c0ff; font-size: 14px; font-weight: 700; }
            Text { x: 18px; y: 49px; text: "7   8   9   +"; color: #f0f6fc; font-size: 18px; }
            Text { x: 18px; y: 80px; text: "4   5   6   -"; color: #f0f6fc; font-size: 18px; }
            Text { x: 18px; y: 111px; text: "1   2   3   Enter"; color: #f0f6fc; font-size: 18px; }
        }
        Rectangle {
            x: 896px; y: 534px; width: 266px; height: 180px; border-radius: 16px; background: #161b22; border-width: 1px; border-color: #30363d;
            Text { x: 18px; y: 15px; text: "Dossier"; color: #79c0ff; font-size: 14px; font-weight: 700; }
            Text { x: 18px; y: 46px; text: "Provider     kanata"; color: #c9d1d9; font-size: 12px; }
            Text { x: 18px; y: 69px; text: "Family       komorebi"; color: #c9d1d9; font-size: 12px; }
            Text { x: 18px; y: 92px; text: "Target       window"; color: #c9d1d9; font-size: 12px; }
            Text { x: 18px; y: 115px; text: "Applicability available"; color: #c9d1d9; font-size: 12px; }
            Text { x: 18px; y: 138px; text: "Generation   " + root.selected; color: #8b949e; font-size: 12px; }
        }
    }
}

fn rows() -> ModelRc<BenchRow> {
    let sections = ["Focus", "Move", "Stack", "Layout", "Workspace", "System"];
    ModelRc::new(VecModel::from(
        (0..72)
            .map(|index| BenchRow {
                shortcut: format!("u{}+{}", index % 3, (b'a' + (index % 26) as u8) as char).into(),
                description: format!("Representative shortcut action {:02}", index + 1).into(),
                section: sections[index % sections.len()].into(),
            })
            .collect::<Vec<_>>(),
    ))
}

fn keys() -> ModelRc<SharedString> {
    ModelRc::new(VecModel::from(
        (0..66)
            .map(|index| {
                if index < 26 {
                    ((b'A' + index as u8) as char).to_string()
                } else {
                    format!("K{:02}", index + 1)
                }
                .into()
            })
            .collect::<Vec<_>>(),
    ))
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

fn install_command_reader(
    main: slint::Weak<MainBench>,
    auxiliary: slint::Weak<AuxiliaryBench>,
    log: EventLog,
) {
    thread::spawn(move || {
        let input = io::stdin();
        let thread_log = log.clone();
        let result = read_commands(input.lock(), |command| {
            let main = main.clone();
            let auxiliary = auxiliary.clone();
            let log = thread_log.clone();
            slint::invoke_from_event_loop(move || execute_command(main, auxiliary, log, command))
                .map_err(|error| error.to_string())?;
            Ok(!matches!(command, Command::Quit))
        });
        if let Err(error) = result {
            let _ = thread_log.emit(EventKind::Error, Some(json!({ "message": error })));
            let _ = slint::invoke_from_event_loop(|| {
                let _ = slint::quit_event_loop();
            });
        }
    });
}

fn execute_command(
    main: slint::Weak<MainBench>,
    auxiliary: slint::Weak<AuxiliaryBench>,
    log: EventLog,
    command: Command,
) {
    match command {
        Command::Show => {
            log.emit(EventKind::ShowStart, None).unwrap();
            main.upgrade().unwrap().show().unwrap();
            auxiliary.upgrade().unwrap().show().unwrap();
            log.emit(EventKind::ShowEnd, None).unwrap();
        }
        Command::Workload => {
            log.emit(EventKind::WorkloadStart, None).unwrap();
            let updates = Rc::new(Cell::new(0_usize));
            let timer = Rc::new(Timer::default());
            let timer_callback = Rc::clone(&timer);
            timer.start(
                TimerMode::Repeated,
                Duration::from_millis(WORKLOAD_STEP_MILLIS),
                move || {
                    let update = updates.get();
                    let selected = ((update + 1) % 72) as i32;
                    main.upgrade().unwrap().set_selected(selected);
                    auxiliary.upgrade().unwrap().set_selected(selected);
                    if update + 1 == WORKLOAD_STEPS {
                        timer_callback.stop();
                        log.emit(EventKind::WorkloadEnd, None).unwrap();
                    } else {
                        updates.set(update + 1);
                    }
                },
            );
            std::mem::forget(timer);
        }
        Command::Hide => {
            log.emit(EventKind::HideStart, None).unwrap();
            main.upgrade().unwrap().hide().unwrap();
            auxiliary.upgrade().unwrap().hide().unwrap();
            log.emit(EventKind::HideEnd, None).unwrap();
        }
        Command::Cycle { count } => {
            log.emit(EventKind::CycleStart, Some(json!({ "count": count })))
                .unwrap();
            let turns = Rc::new(Cell::new(0_u16));
            let timer = Rc::new(Timer::default());
            let timer_callback = Rc::clone(&timer);
            timer.start(TimerMode::Repeated, Duration::from_millis(50), move || {
                let turn = turns.get();
                if turn % 2 == 0 {
                    main.upgrade().unwrap().show().unwrap();
                    auxiliary.upgrade().unwrap().show().unwrap();
                } else {
                    main.upgrade().unwrap().hide().unwrap();
                    auxiliary.upgrade().unwrap().hide().unwrap();
                }
                if turn + 1 == count * 2 {
                    timer_callback.stop();
                    log.emit(EventKind::CycleEnd, Some(json!({ "count": count })))
                        .unwrap();
                } else {
                    turns.set(turn + 1);
                }
            });
            std::mem::forget(timer);
        }
        Command::Quit => {
            log.emit(EventKind::Quit, None).unwrap();
            slint::quit_event_loop().unwrap();
        }
    }
}

fn main() -> Result<(), slint::PlatformError> {
    let log = EventLog::create(FRAMEWORK, event_log_path())
        .expect("failed to create benchmark event log");
    let main = MainBench::new()?;
    let auxiliary = AuxiliaryBench::new()?;
    main.set_rows(rows());
    auxiliary.set_keys(keys());

    install_command_reader(main.as_weak(), auxiliary.as_weak(), log.clone());
    let ready_main = main.as_weak();
    let ready_auxiliary = auxiliary.as_weak();
    Timer::single_shot(Duration::ZERO, move || {
        ready_main.upgrade().unwrap().show().unwrap();
        ready_auxiliary.upgrade().unwrap().show().unwrap();
        Timer::single_shot(Duration::from_millis(100), move || {
            ready_main.upgrade().unwrap().hide().unwrap();
            ready_auxiliary.upgrade().unwrap().hide().unwrap();
            log.emit(EventKind::ReadyHidden, None).unwrap();
        });
    });
    slint::run_event_loop_until_quit()
}
