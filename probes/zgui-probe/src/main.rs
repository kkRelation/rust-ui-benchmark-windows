#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

use std::cell::RefCell;
use std::io;
use std::rc::Rc;
use std::thread;
use std::time::{Duration, Instant};

use serde_json::json;
use tokio::sync::mpsc;
use ui_bench_protocol::{
    Command, EventKind, EventLog, WORKLOAD_STEP_MILLIS, WORKLOAD_STEPS, read_commands,
};
use windows_sys::Win32::Foundation::{HWND, LPARAM};
use windows_sys::Win32::System::Threading::GetCurrentProcessId;
use windows_sys::Win32::UI::WindowsAndMessaging::{
    EnumWindows, GetWindowTextLengthW, GetWindowTextW, GetWindowThreadProcessId, PostMessageW,
    SW_HIDE, SW_SHOWNOACTIVATE, ShowWindow, WM_CLOSE,
};
use windows_sys::core::BOOL;
use zgui::prelude::*;

const FRAMEWORK: &str = "zgui";
const MAIN_TITLE: &str = "UI Framework Bench - Main";
const AUXILIARY_TITLE: &str = "UI Framework Bench - Auxiliary Canvas";

#[derive(Clone)]
struct BenchState {
    selected: RwSignal<usize>,
    selections: Rc<RefCell<Option<mpsc::Receiver<usize>>>>,
}

#[component]
fn MainBench() -> impl IntoView {
    let state = use_local_context::<BenchState>().expect("missing benchmark state");
    let windows = use_windows();
    let main_window = use_window();

    let auxiliary_window = windows.open(
        WindowOptions::new(AUXILIARY_TITLE).with_size(1200.0, 760.0),
        AuxiliaryBench,
    );

    install_controller(state.clone(), Rc::new([main_window, auxiliary_window]));

    view! {
        column(class = "main-page") {
            row(class = "masthead") {
                text(class = "title") {"Shortcut Palette"}
                spacer()
                text(class = "badge") {"72 ENTRIES"}
            }
            column(class = "search") {
                text(class = "search__primary") {
                    "Search shortcuts, commands, facets, and object memory"
                }
                text(class = "muted") {
                    "Static benchmark corpus · selection drives the auxiliary canvas"
                }
            }
            column(class = "list") {
                for index in || (0_usize..72).collect::<Vec<_>>(), key = |index: &usize| *index {
                    row(
                        class = "shortcut-row",
                        class:selected = move || state.selected.get() == index,
                    ) {
                        text(class = "shortcut") {
                            {format!("u{}+{}", index % 3, (b'a' + (index % 26) as u8) as char)}
                        }
                        text(class = "description") {
                            {format!("Representative shortcut action {:02}", index + 1)}
                        }
                        spacer()
                        text(class = "section") {
                            {[
                                "Focus", "Move", "Stack", "Layout", "Workspace", "System",
                            ][index % 6]}
                        }
                    }
                }
            }
        }
    }
}

fn install_controller(state: BenchState, handles: Rc<[WindowHandle; 2]>) {
    let receiver = state
        .selections
        .borrow_mut()
        .take()
        .expect("benchmark selection receiver already installed");

    let controller_state = state.clone();
    let controller = zgui::tokio::spawn_receiver(receiver, move |selected| {
        controller_state.selected.set(selected);
    });

    // WindowHandle lifetime is part of zgui's window ownership. Keep both handles
    // with the receiver so an initially hidden auxiliary window is never dropped.
    let _retained = RwSignal::new_local((controller, handles));
}

#[component]
fn AuxiliaryBench() -> impl IntoView {
    let state = use_local_context::<BenchState>().expect("missing benchmark state");

    view! {
        column(class = "aux-page") {
            column(class = "preview panel") {
                text(class = "eyebrow") {"Object Memory Preview"}
                text(class = "preview__title") {
                    {move || format!(
                        "Selected action {}: move, focus, or transform the active object",
                        state.selected.get() + 1,
                    )}
                }
                text(class = "muted") {
                    "Representative defining expression, scenario annotation, availability note, source path, and extended explanation."
                }
            }
            row(class = "aux-body") {
                column(class = "atlas panel") {
                    text(class = "atlas__title") {
                        "Binding Atlas · modifier plane and related bindings"
                    }
                    box(class = "key-grid") {
                        for index in || (0_usize..66).collect::<Vec<_>>(), key = |index: &usize| *index {
                            box(
                                class = "key",
                                class:selected = move || state.selected.get() % 66 == index,
                            ) {
                                text() {
                                    {if index < 26 {
                                        ((b'A' + index as u8) as char).to_string()
                                    } else {
                                        format!("K{:02}", index + 1)
                                    }}
                                }
                            }
                        }
                    }
                }
                column(class = "side") {
                    column(class = "side-panel panel") {
                        text(class = "eyebrow") {"Navigation"}
                        text(class = "side-panel__large") {"H  J  K  L"}
                        text(class = "muted") {"word · line · page · history"}
                        text(class = "muted") {
                            {move || format!("selected relation {}", state.selected.get() % 12)}
                        }
                    }
                    column(class = "side-panel panel") {
                        text(class = "eyebrow") {"Numpad / Operations"}
                        text(class = "side-panel__medium") {"7   8   9   +"}
                        text(class = "side-panel__medium") {"4   5   6   -"}
                        text(class = "side-panel__medium") {"1   2   3   Enter"}
                    }
                    column(class = "side-panel panel") {
                        text(class = "eyebrow") {"Dossier"}
                        text(class = "detail") {"Provider       kanata"}
                        text(class = "detail") {"Family         komorebi"}
                        text(class = "detail") {"Target         window"}
                        text(class = "detail") {"Applicability  available"}
                        text(class = "muted") {
                            {move || format!("Generation     {}", state.selected.get())}
                        }
                    }
                }
            }
        }
    }
}

const SHEET: &str = css!(
    ":root {
        background-color: #080b10;
        color: #c9d1d9;
        font-family: sans-serif;
    }

    .main-page { gap: 12px; padding: 18px; background-color: #0d1117; }
    .masthead { align-items: center; }
    .title { color: #f0f6fc; font-size: 25px; font-weight: 700; }
    .badge {
        padding: 8px 16px; border-radius: 999px; color: #79c0ff;
        background-color: rgba(31, 111, 235, 0.2); font-size: 11px; font-weight: 700;
    }
    .search {
        gap: 3px; padding: 11px 16px; border-radius: 12px;
        border: 1px solid #30363d; background-color: #161b22;
    }
    .search__primary { font-size: 15px; }
    .muted { color: #8b949e; font-size: 11px; }
    .list { overflow: auto; border: 1px solid #30363d; border-radius: 12px; }
    .shortcut-row {
        min-height: 44px; align-items: center; gap: 10px; padding: 0 14px;
        border-bottom: 1px solid #21262d; background-color: #0d1117;
    }
    .shortcut-row:nth-child(even) { background-color: #11161c; }
    .shortcut-row.selected { background-color: rgba(31, 111, 235, 0.27); }
    .shortcut { width: 128px; font-size: 13px; font-weight: 700; }
    .description { width: 360px; font-size: 13px; }
    .section { color: #8b949e; font-size: 12px; }

    .aux-page { gap: 18px; padding: 22px 24px; background-color: #080b10; }
    .panel { border: 1px solid #30363d; border-radius: 16px; background-color: #161b22; }
    .preview { gap: 7px; min-height: 114px; padding: 16px 20px; }
    .eyebrow { color: #79c0ff; font-size: 13px; font-weight: 700; }
    .preview__title { color: #f0f6fc; font-size: 18px; font-weight: 700; }
    .aux-body { gap: 18px; }
    .atlas { width: 854px; gap: 16px; padding: 18px 22px; background-color: #0d1117; }
    .atlas__title { color: #f0f6fc; font-size: 16px; font-weight: 700; }
    .key-grid { display: grid; grid-template-columns: repeat(11, 1fr); gap: 10px; }
    .key {
        height: 42px; align-items: center; justify-content: center; border-radius: 8px;
        border: 1px solid #30363d; background-color: #21262d; font-size: 12px; font-weight: 700;
    }
    .key.selected { color: #ffffff; border-color: #79c0ff; background-color: #2f81f7; }
    .side { width: 266px; gap: 18px; }
    .side-panel { min-height: 162px; gap: 8px; padding: 15px 18px; }
    .side-panel__large { color: #f0f6fc; font-size: 21px; font-weight: 700; }
    .side-panel__medium { color: #f0f6fc; font-size: 18px; }
    .detail { font-size: 12px; }
    "
);

unsafe extern "system" fn enum_window(hwnd: HWND, parameter: LPARAM) -> BOOL {
    let windows = unsafe { &mut *(parameter as *mut Vec<HWND>) };
    let mut process_id = 0_u32;
    unsafe { GetWindowThreadProcessId(hwnd, &mut process_id) };
    if process_id != unsafe { GetCurrentProcessId() } {
        return 1;
    }
    let length = unsafe { GetWindowTextLengthW(hwnd) };
    if length <= 0 {
        return 1;
    }
    let mut buffer = vec![0_u16; length as usize + 1];
    let copied = unsafe { GetWindowTextW(hwnd, buffer.as_mut_ptr(), buffer.len() as i32) };
    let title = String::from_utf16_lossy(&buffer[..copied as usize]);
    if title == MAIN_TITLE || title == AUXILIARY_TITLE {
        windows.push(hwnd);
    }
    1
}

fn benchmark_windows() -> Vec<HWND> {
    let mut windows = Vec::new();
    unsafe {
        EnumWindows(Some(enum_window), &mut windows as *mut Vec<HWND> as LPARAM);
    }
    windows
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

fn set_native_visible(windows: &[HWND], visible: bool) {
    for window in windows {
        unsafe {
            ShowWindow(*window, if visible { SW_SHOWNOACTIVATE } else { SW_HIDE });
        }
    }
}

fn run_command_loop(log: EventLog, selections: mpsc::Sender<usize>) {
    let windows = match wait_for_windows() {
        Ok(windows) => windows,
        Err(error) => {
            let _ = log.emit(EventKind::Error, Some(json!({ "message": error })));
            return;
        }
    };
    set_native_visible(&windows, false);
    if let Err(error) = log.emit(EventKind::ReadyHidden, None) {
        let _ = log.emit(
            EventKind::Error,
            Some(json!({ "message": error.to_string() })),
        );
        return;
    }
    let input = io::stdin();
    let result = read_commands(input.lock(), |command| {
        match command {
            Command::Show => {
                log.emit(EventKind::ShowStart, None)
                    .map_err(|error| error.to_string())?;
                set_native_visible(&windows, true);
                log.emit(EventKind::ShowEnd, None)
                    .map_err(|error| error.to_string())?;
            }
            Command::Workload => {
                log.emit(EventKind::WorkloadStart, None)
                    .map_err(|error| error.to_string())?;
                let started = Instant::now();
                for update in 0..WORKLOAD_STEPS {
                    selections
                        .blocking_send((update + 1) % 72)
                        .map_err(|error| error.to_string())?;
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
                set_native_visible(&windows, false);
                log.emit(EventKind::HideEnd, None)
                    .map_err(|error| error.to_string())?;
            }
            Command::Cycle { count } => {
                log.emit(EventKind::CycleStart, Some(json!({ "count": count })))
                    .map_err(|error| error.to_string())?;
                for _ in 0..count {
                    set_native_visible(&windows, true);
                    thread::sleep(Duration::from_millis(50));
                    set_native_visible(&windows, false);
                    thread::sleep(Duration::from_millis(50));
                }
                log.emit(EventKind::CycleEnd, Some(json!({ "count": count })))
                    .map_err(|error| error.to_string())?;
            }
            Command::Quit => {
                log.emit(EventKind::Quit, None)
                    .map_err(|error| error.to_string())?;
                for window in &windows {
                    unsafe { PostMessageW(*window, WM_CLOSE, 0, 0) };
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

fn main() -> Result<(), zgui::Error> {
    let mut arguments = std::env::args_os().skip(1);
    let mut event_log_path = None;
    while let Some(argument) = arguments.next() {
        if argument == "--event-log" {
            event_log_path = arguments.next().map(std::path::PathBuf::from);
        }
    }
    let event_log_path = event_log_path.expect("missing required --event-log <path>");
    let log =
        EventLog::create(FRAMEWORK, event_log_path).expect("failed to create benchmark event log");
    let (selection_sender, selection_receiver) = mpsc::channel(WORKLOAD_STEPS + 1);
    let thread_log = log.clone();
    thread::spawn(move || run_command_loop(thread_log, selection_sender));

    let selections = Rc::new(RefCell::new(Some(selection_receiver)));
    app()
        .with_application_id("dev.komorebi.UiFrameworkBench")
        .with_title(MAIN_TITLE)
        .with_size(700.0, 480.0)
        .with_stylesheet(SHEET)
        .with_context(move || {
            provide_local_context(BenchState {
                selected: RwSignal::new(0),
                selections: Rc::clone(&selections),
            })
        })
        .run(MainBench)
}
