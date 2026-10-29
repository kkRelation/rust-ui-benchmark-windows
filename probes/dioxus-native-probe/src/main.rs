#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

use std::io;
use std::sync::OnceLock;
use std::thread;
use std::time::{Duration, Instant};

use blitz_shell::{BlitzShellProxy, WindowConfig, create_default_event_loop};
use dioxus::prelude::*;
use dioxus_native::{
    DioxusDocument, DioxusNativeApplication, DioxusNativeWindowRenderer, DocumentConfig,
    LogicalSize, WindowAttributes,
};
use serde_json::json;
use tokio::sync::watch;
use ui_bench_protocol::{
    Command, EventKind, EventLog, WORKLOAD_STEP_MILLIS, WORKLOAD_STEPS, read_commands,
};
use windows_sys::Win32::Foundation::HWND;
use windows_sys::Win32::UI::WindowsAndMessaging::{
    FindWindowW, GetWindowThreadProcessId, PostMessageW, SW_HIDE, SW_SHOWNOACTIVATE, ShowWindow,
    WM_CLOSE,
};

const FRAMEWORK: &str = "dioxus-native";
const MAIN_TITLE: &str = "UI Framework Bench - Main";
const AUXILIARY_TITLE: &str = "UI Framework Bench - Auxiliary Canvas";

struct Startup {
    selected: watch::Sender<usize>,
}

static STARTUP: OnceLock<Startup> = OnceLock::new();

const STYLE: &str = r#"
*{box-sizing:border-box}html,body,#main{width:100%;height:100%;margin:0;overflow:hidden}
body{background:#080b10;color:#c9d1d9;font-family:'Segoe UI',sans-serif}.main{height:100%;padding:18px;background:#0d1117}
.masthead{display:flex;align-items:center;justify-content:space-between;margin-bottom:12px}h1{margin:0;color:#f0f6fc;font-size:25px}.badge{padding:8px 16px;border-radius:99px;color:#79c0ff;background:#1f6feb33;font-size:11px;font-weight:700}
.search{height:54px;padding:8px 16px;border:1px solid #30363d;border-radius:12px;background:#161b22}.muted{display:block;margin-top:3px;color:#8b949e;font-size:11px}.list{height:calc(100% - 108px);margin-top:12px;overflow:auto;border:1px solid #30363d;border-radius:12px}.shortcut-row{display:flex;align-items:center;min-height:44px;padding:0 14px;border-bottom:1px solid #21262d}.shortcut-row:nth-child(even){background:#11161c}.shortcut-row.selected{border-left:4px solid #58a6ff;background:#1f6feb44}.shortcut{width:128px;color:#f0f6fc;font-size:13px;font-weight:700}.description{width:360px;font-size:13px}.section{margin-left:auto;color:#8b949e;font-size:12px}
.aux{height:100%;padding:22px 24px}.panel{border:1px solid #30363d;border-radius:16px;background:#161b22}.preview{height:114px;padding:16px 20px}.eyebrow{color:#79c0ff;font-size:13px;font-weight:700}.preview h2{margin:8px 0 0;color:#f0f6fc;font-size:18px}.aux-body{display:flex;gap:18px;height:560px;margin-top:18px}.atlas{width:854px;padding:18px 22px;background:#0d1117}.atlas h3{margin:0 0 16px;color:#f0f6fc;font-size:16px}.keys{display:grid;grid-template-columns:repeat(11,1fr);gap:10px}.key{display:grid;height:42px;place-items:center;border:1px solid #30363d;border-radius:8px;background:#21262d;font-size:12px;font-weight:700}.key.selected{color:white;border-color:#79c0ff;background:#2f81f7}.side{display:flex;width:266px;flex-direction:column;gap:18px}.side-panel{min-height:162px;padding:15px 18px}.large{margin:14px 0;color:#f0f6fc;font-size:21px;font-weight:700}.medium{margin:9px 0;color:#f0f6fc;font-size:18px}.detail{margin:8px 0;font-size:12px}
"#;

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

fn main_scene() -> Element {
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

fn auxiliary_scene() -> Element {
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

fn window_config(
    app: fn() -> Element,
    title: &str,
    width: f64,
    height: f64,
    initial_build: bool,
) -> WindowConfig<DioxusNativeWindowRenderer> {
    let mut document = DioxusDocument::new(VirtualDom::new(app), DocumentConfig::default());
    if initial_build {
        document.initial_build();
    }
    let attributes = WindowAttributes::default()
        .with_title(title)
        .with_surface_size(LogicalSize::new(width, height))
        .with_visible(false);
    WindowConfig::with_attributes(
        Box::new(document),
        DioxusNativeWindowRenderer::new(),
        attributes,
    )
}

fn benchmark_windows() -> Vec<HWND> {
    [MAIN_TITLE, AUXILIARY_TITLE]
        .into_iter()
        .filter_map(|title| {
            let wide = title.encode_utf16().chain([0]).collect::<Vec<_>>();
            let window = unsafe { FindWindowW(std::ptr::null(), wide.as_ptr()) };
            if window.is_null() {
                return None;
            }
            let mut process_id = 0_u32;
            unsafe { GetWindowThreadProcessId(window, &mut process_id) };
            (process_id == std::process::id()).then_some(window)
        })
        .collect()
}

fn wait_for_windows() -> Result<Vec<HWND>, String> {
    let deadline = Instant::now() + Duration::from_secs(60);
    loop {
        let windows = benchmark_windows();
        if windows.len() == 2 {
            return Ok(windows);
        }
        if Instant::now() >= deadline {
            return Err(format!(
                "expected two native windows, found {}",
                windows.len()
            ));
        }
        thread::sleep(Duration::from_millis(20));
    }
}

fn set_visible(windows: &[HWND], visible: bool) {
    for window in windows {
        unsafe {
            ShowWindow(*window, if visible { SW_SHOWNOACTIVATE } else { SW_HIDE });
        }
    }
}

fn run_command_loop(log: EventLog, selected: watch::Sender<usize>) {
    let windows = match wait_for_windows() {
        Ok(windows) => windows,
        Err(error) => {
            let _ = log.emit(EventKind::Error, Some(json!({ "message": error })));
            return;
        }
    };
    set_visible(&windows, false);
    log.emit(EventKind::ReadyHidden, None).unwrap();

    let input = io::stdin();
    let result = read_commands(input.lock(), |command| {
        match command {
            Command::Show => {
                log.emit(EventKind::ShowStart, None)
                    .map_err(|error| error.to_string())?;
                set_visible(&windows, true);
                log.emit(EventKind::ShowEnd, None)
                    .map_err(|error| error.to_string())?;
            }
            Command::Workload => {
                log.emit(EventKind::WorkloadStart, None)
                    .map_err(|error| error.to_string())?;
                let started = Instant::now();
                for update in 0..WORKLOAD_STEPS {
                    selected.send_replace((update + 1) % 72);
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
                set_visible(&windows, false);
                log.emit(EventKind::HideEnd, None)
                    .map_err(|error| error.to_string())?;
            }
            Command::Cycle { count } => {
                log.emit(EventKind::CycleStart, Some(json!({ "count": count })))
                    .map_err(|error| error.to_string())?;
                for _ in 0..count {
                    set_visible(&windows, true);
                    thread::sleep(Duration::from_millis(50));
                    set_visible(&windows, false);
                    thread::sleep(Duration::from_millis(50));
                }
                log.emit(EventKind::CycleEnd, Some(json!({ "count": count })))
                    .map_err(|error| error.to_string())?;
            }
            Command::Quit => {
                log.emit(EventKind::Quit, None)
                    .map_err(|error| error.to_string())?;
                for window in &windows {
                    unsafe {
                        PostMessageW(*window, WM_CLOSE, 0, 0);
                    }
                }
                return Ok(false);
            }
        }
        Ok(true)
    });
    if let Err(error) = result {
        let _ = log.emit(EventKind::Error, Some(json!({ "message": error })));
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

fn main() {
    let log = EventLog::create(FRAMEWORK, event_log_path())
        .expect("failed to create benchmark event log");
    let (selected, _) = watch::channel(0_usize);
    STARTUP
        .set(Startup {
            selected: selected.clone(),
        })
        .ok()
        .unwrap();
    thread::spawn(move || run_command_loop(log, selected));

    let event_loop = create_default_event_loop();
    let (proxy, event_queue) = BlitzShellProxy::new(event_loop.create_proxy());
    let main_window = window_config(main_scene, MAIN_TITLE, 700.0, 480.0, false);
    let auxiliary_window = window_config(auxiliary_scene, AUXILIARY_TITLE, 1200.0, 760.0, true);
    let mut application = DioxusNativeApplication::new(proxy, event_queue, main_window);
    application.add_window(auxiliary_window);
    event_loop.run_app(application).unwrap();
}
