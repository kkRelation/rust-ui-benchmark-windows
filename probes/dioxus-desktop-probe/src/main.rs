#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

use std::io;
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::{Mutex, OnceLock};
use std::thread;
use std::time::{Duration, Instant};

use dioxus::prelude::*;
use dioxus_desktop::{window, Config, LogicalSize, WindowBuilder};
use serde_json::json;
use tokio::sync::{mpsc, watch, Notify};
use ui_bench_protocol::{
    read_commands, Command, EventKind, EventLog, WORKLOAD_STEPS, WORKLOAD_STEP_MILLIS,
};

const FRAMEWORK: &str = "dioxus-desktop";

struct Startup {
    commands: Mutex<Option<mpsc::Receiver<Command>>>,
    selected: watch::Sender<usize>,
    rendered: AtomicUsize,
    rendered_notify: Notify,
    log: EventLog,
}

static STARTUP: OnceLock<Startup> = OnceLock::new();

const STYLE: &str = r#"
*{box-sizing:border-box}html,body,#main{width:100%;height:100%;margin:0;overflow:hidden}
body{background:#080b10;color:#c9d1d9;font-family:'Segoe UI',sans-serif}.main{height:100%;padding:18px;background:#0d1117}
.masthead{display:flex;align-items:center;justify-content:space-between;margin-bottom:12px}h1{margin:0;color:#f0f6fc;font-size:25px}
.badge{padding:8px 16px;border-radius:99px;color:#79c0ff;background:#1f6feb33;font-size:11px;font-weight:700}
.search{height:54px;padding:8px 16px;border:1px solid #30363d;border-radius:12px;background:#161b22}.muted{display:block;margin-top:3px;color:#8b949e;font-size:11px}
.list{height:calc(100% - 108px);margin-top:12px;overflow:auto;border:1px solid #30363d;border-radius:12px}.shortcut-row{display:flex;align-items:center;min-height:44px;padding:0 14px;border-bottom:1px solid #21262d}.shortcut-row:nth-child(even){background:#11161c}.shortcut-row.selected{border-left:4px solid #58a6ff;background:#1f6feb44}.shortcut{width:128px;color:#f0f6fc;font-size:13px;font-weight:700}.description{width:360px;font-size:13px}.section{margin-left:auto;color:#8b949e;font-size:12px}
.aux{height:100%;padding:22px 24px}.panel{border:1px solid #30363d;border-radius:16px;background:#161b22}.preview{height:114px;padding:16px 20px}.eyebrow{color:#79c0ff;font-size:13px;font-weight:700}.preview h2{margin:8px 0 0;color:#f0f6fc;font-size:18px}.aux-body{display:flex;gap:18px;height:560px;margin-top:18px}.atlas{width:854px;padding:18px 22px;background:#0d1117}.atlas h3{margin:0 0 16px;color:#f0f6fc;font-size:16px}.keys{display:grid;grid-template-columns:repeat(11,1fr);gap:10px}.key{display:grid;height:42px;place-items:center;border:1px solid #30363d;border-radius:8px;background:#21262d;font-size:12px;font-weight:700}.key.selected{color:white;border-color:#79c0ff;background:#2f81f7}.side{display:flex;width:266px;flex-direction:column;gap:18px}.side-panel{min-height:162px;padding:15px 18px}.large{margin:14px 0;color:#f0f6fc;font-size:21px;font-weight:700}.medium{margin:9px 0;color:#f0f6fc;font-size:18px}.detail{margin:8px 0;font-size:12px}
"#;

fn mark_rendered() {
    use_hook(|| {
        let startup = STARTUP.get().unwrap();
        startup.rendered.fetch_add(1, Ordering::AcqRel);
        startup.rendered_notify.notify_waiters();
    });
}

fn use_selected() -> Signal<usize> {
    let mut selected = use_signal(|| 0_usize);
    use_hook(|| {
        let mut receiver = STARTUP.get().unwrap().selected.subscribe();
        spawn(async move {
            while receiver.changed().await.is_ok() {
                selected.set(*receiver.borrow_and_update());
            }
        });
    });
    selected
}

#[component]
fn MainScene() -> Element {
    mark_rendered();
    let selected = use_selected();
    let sections = ["Focus", "Move", "Stack", "Layout", "Workspace", "System"];
    rsx! {
        style { {STYLE} }
        main { class: "main",
            div { class: "masthead", h1 { "Shortcut Palette" } span { class: "badge", "72 ENTRIES" } }
            div { class: "search", "Search shortcuts, commands, facets, and object memory" span { class: "muted", "Static benchmark corpus · selection drives the auxiliary canvas" } }
            div { class: "list",
                for index in 0..72_usize {
                    div { class: if selected() == index { "shortcut-row selected" } else { "shortcut-row" },
                        span { class: "shortcut", "u{index % 3}+{(b'a' + (index % 26) as u8) as char}" }
                        span { class: "description", "Representative shortcut action {index + 1:02}" }
                        span { class: "section", {sections[index % sections.len()]} }
                    }
                }
            }
        }
    }
}

#[component]
fn AuxiliaryScene() -> Element {
    mark_rendered();
    let selected = use_selected();
    rsx! {
        style { {STYLE} }
        main { class: "aux",
            section { class: "preview panel", div { class: "eyebrow", "Object Memory Preview" } h2 { "Selected action {selected() + 1}: move, focus, or transform the active object" } small { class: "muted", "Representative defining expression, scenario annotation, availability note, source path, and extended explanation." } }
            div { class: "aux-body",
                section { class: "atlas panel", h3 { "Binding Atlas · modifier plane and related bindings" }
                    div { class: "keys",
                        for index in 0..66_usize {
                            div { class: if selected() % 66 == index { "key selected" } else { "key" },
                                {if index < 26 { ((b'A' + index as u8) as char).to_string() } else { format!("K{:02}", index + 1) }}
                            }
                        }
                    }
                }
                aside { class: "side",
                    section { class: "side-panel panel", div { class: "eyebrow", "Navigation" } div { class: "large", "H  J  K  L" } small { class: "muted", "word · line · page · history" } small { class: "muted", "selected relation {selected() % 12}" } }
                    section { class: "side-panel panel", div { class: "eyebrow", "Numpad / Operations" } div { class: "medium", "7   8   9   +" } div { class: "medium", "4   5   6   -" } div { class: "medium", "1   2   3   Enter" } }
                    section { class: "side-panel panel", div { class: "eyebrow", "Dossier" } div { class: "detail", "Provider       kanata" } div { class: "detail", "Family         komorebi" } div { class: "detail", "Target         window" } div { class: "detail", "Applicability  available" } small { class: "muted", "Generation     {selected()}" } }
                }
            }
        }
    }
}

fn hidden_window(title: &str, width: f64, height: f64) -> Config {
    Config::new().with_window(
        WindowBuilder::new()
            .with_title(title)
            .with_inner_size(LogicalSize::new(width, height))
            .with_visible(false),
    )
}

async fn run_controller() {
    let startup = STARTUP.get().unwrap();
    let main_service = window();
    let auxiliary_service = main_service
        .new_window(
            VirtualDom::new(AuxiliaryScene),
            hidden_window("UI Framework Bench - Auxiliary Canvas", 1200.0, 760.0),
        )
        .await;

    while startup.rendered.load(Ordering::Acquire) < 2 {
        startup.rendered_notify.notified().await;
    }
    startup.log.emit(EventKind::ReadyHidden, None).unwrap();

    let windows = [
        main_service.window.clone(),
        auxiliary_service.window.clone(),
    ];
    let mut commands = startup.commands.lock().unwrap().take().unwrap();
    while let Some(command) = commands.recv().await {
        match command {
            Command::Show => {
                startup.log.emit(EventKind::ShowStart, None).unwrap();
                for window in &windows {
                    window.set_visible(true);
                }
                startup.log.emit(EventKind::ShowEnd, None).unwrap();
            }
            Command::Workload => {
                startup.log.emit(EventKind::WorkloadStart, None).unwrap();
                let started = Instant::now();
                for update in 0..WORKLOAD_STEPS {
                    startup.selected.send_replace((update + 1) % 72);
                    let deadline =
                        started + Duration::from_millis((update as u64 + 1) * WORKLOAD_STEP_MILLIS);
                    tokio::time::sleep(deadline.saturating_duration_since(Instant::now())).await;
                }
                startup.log.emit(EventKind::WorkloadEnd, None).unwrap();
            }
            Command::Hide => {
                startup.log.emit(EventKind::HideStart, None).unwrap();
                for window in &windows {
                    window.set_visible(false);
                }
                startup.log.emit(EventKind::HideEnd, None).unwrap();
            }
            Command::Cycle { count } => {
                startup
                    .log
                    .emit(EventKind::CycleStart, Some(json!({ "count": count })))
                    .unwrap();
                for _ in 0..count {
                    for window in &windows {
                        window.set_visible(true);
                    }
                    tokio::time::sleep(Duration::from_millis(50)).await;
                    for window in &windows {
                        window.set_visible(false);
                    }
                    tokio::time::sleep(Duration::from_millis(50)).await;
                }
                startup
                    .log
                    .emit(EventKind::CycleEnd, Some(json!({ "count": count })))
                    .unwrap();
            }
            Command::Quit => {
                startup.log.emit(EventKind::Quit, None).unwrap();
                main_service.close_window(auxiliary_service.id());
                main_service.close();
                break;
            }
        }
    }
}

#[component]
fn App() -> Element {
    use_hook(|| spawn(run_controller()));
    rsx! { MainScene {} }
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

fn main() {
    let log = EventLog::create(FRAMEWORK, event_log_path())
        .expect("failed to create benchmark event log");
    let (selected, _) = watch::channel(0_usize);
    let (command_sender, command_receiver) = mpsc::channel(16);
    STARTUP
        .set(Startup {
            commands: Mutex::new(Some(command_receiver)),
            selected,
            rendered: AtomicUsize::new(0),
            rendered_notify: Notify::new(),
            log: log.clone(),
        })
        .ok()
        .expect("benchmark startup already initialized");

    thread::spawn(move || {
        let input = io::stdin();
        if let Err(error) = read_commands(input.lock(), |command| {
            command_sender
                .blocking_send(command)
                .map_err(|error| error.to_string())?;
            Ok(!matches!(command, Command::Quit))
        }) {
            let _ = log.emit(EventKind::Error, Some(json!({ "message": error })));
        }
    });

    dioxus::LaunchBuilder::desktop()
        .with_cfg(hidden_window("UI Framework Bench - Main", 700.0, 480.0))
        .launch(App);
}
