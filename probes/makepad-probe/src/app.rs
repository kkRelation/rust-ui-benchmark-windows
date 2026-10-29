use std::io;
use std::thread;
use std::time::{Duration, Instant};

use makepad_widgets::*;
use serde_json::json;
use ui_bench_protocol::{Command, EventKind, EventLog, read_commands};
use windows_sys::Win32::Foundation::HWND;
use windows_sys::Win32::System::Threading::GetCurrentProcessId;
use windows_sys::Win32::UI::HiDpi::GetDpiForWindow;
use windows_sys::Win32::UI::WindowsAndMessaging::{
    FindWindowExW, GetWindowThreadProcessId, IsWindowVisible, PostMessageW, SW_HIDE,
    SW_SHOWNOACTIVATE, SWP_NOACTIVATE, SWP_NOMOVE, SWP_NOZORDER, SetWindowPos, ShowWindow,
    WM_CLOSE,
};

const FRAMEWORK: &str = "makepad";
const MAIN_TITLE: &str = "UI Framework Bench - Main";
const AUXILIARY_TITLE: &str = "UI Framework Bench - Auxiliary Canvas";

live_design! {
    use link::theme::*;
    use link::shaders::*;
    use link::widgets::*;

    App = {{App}} {
        ui: <MultiWindow> {
            main_window = <Window> {
                window: {
                    title: "UI Framework Bench - Main",
                    inner_size: vec2(700, 480)
                }
                body = <View> {
                    show_bg: true,
                    draw_bg: { color: #0d1117 }
                }
            }
            auxiliary_window = <Window> {
                window: {
                    title: "UI Framework Bench - Auxiliary Canvas",
                    inner_size: vec2(1200, 760)
                }
                body = <View> {
                    show_bg: true,
                    draw_bg: { color: #080b10 }
                }
            }
        }
    }
}

app_main!(App);

#[derive(Live, LiveHook)]
pub struct App {
    #[live]
    ui: WidgetRef,
}

impl LiveRegister for App {
    fn live_register(cx: &mut Cx) {
        makepad_widgets::live_design(cx);
    }
}

impl MatchEvent for App {
    fn handle_startup(&mut self, _cx: &mut Cx) {
        start_controller();
    }
}

impl AppMain for App {
    fn handle_event(&mut self, cx: &mut Cx, event: &Event) {
        self.match_event(cx, event);
        self.ui.handle_event(cx, event, &mut Scope::empty());
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

fn benchmark_windows() -> Vec<(HWND, &'static str)> {
    let mut windows = Vec::new();
    let expected_process_id = unsafe { GetCurrentProcessId() };
    for title in [MAIN_TITLE, AUXILIARY_TITLE] {
        let wide_title = title.encode_utf16().chain(Some(0)).collect::<Vec<_>>();
        let mut previous = std::ptr::null_mut();
        loop {
            let window = unsafe {
                FindWindowExW(
                    std::ptr::null_mut(),
                    previous,
                    std::ptr::null(),
                    wide_title.as_ptr(),
                )
            };
            if window.is_null() {
                break;
            }
            let mut process_id = 0_u32;
            unsafe { GetWindowThreadProcessId(window, &mut process_id) };
            if process_id == expected_process_id {
                windows.push((window, title));
            }
            previous = window;
        }
    }
    windows
}

fn wait_for_initial_windows(timeout: Duration) -> Result<(), String> {
    let started = Instant::now();
    while started.elapsed() < timeout {
        let windows = benchmark_windows();
        if windows.len() == 2
            && windows
                .iter()
                .all(|(window, _)| unsafe { IsWindowVisible(*window) } != 0)
        {
            return Ok(());
        }
        thread::sleep(Duration::from_millis(25));
    }
    Err(format!(
        "expected two initially visible Makepad windows, found {}",
        benchmark_windows().len()
    ))
}

fn set_visible(visible: bool) -> Result<(), String> {
    let windows = benchmark_windows();
    if windows.len() != 2 {
        return Err(format!(
            "expected two Makepad windows, found {}",
            windows.len()
        ));
    }
    for (window, _) in windows {
        unsafe { ShowWindow(window, if visible { SW_SHOWNOACTIVATE } else { SW_HIDE }) };
    }
    Ok(())
}

fn normalize_sizes() -> Result<(), String> {
    let windows = benchmark_windows();
    if windows.len() != 2 {
        return Err(format!(
            "expected two Makepad windows, found {}",
            windows.len()
        ));
    }
    for (window, title) in windows {
        let (logical_width, logical_height) = if title == MAIN_TITLE {
            (715, 514)
        } else {
            (1215, 794)
        };
        let dpi = unsafe { GetDpiForWindow(window) }.max(96);
        let width = (logical_width * dpi as i32 + 48) / 96;
        let height = (logical_height * dpi as i32 + 48) / 96;
        let succeeded = unsafe {
            SetWindowPos(
                window,
                std::ptr::null_mut(),
                0,
                0,
                width,
                height,
                SWP_NOMOVE | SWP_NOZORDER | SWP_NOACTIVATE,
            )
        };
        if succeeded == 0 {
            return Err(format!("failed to size Makepad window: {title}"));
        }
    }
    Ok(())
}

fn close_windows() -> Result<(), String> {
    let windows = benchmark_windows();
    if windows.len() != 2 {
        return Err(format!(
            "expected two Makepad windows, found {}",
            windows.len()
        ));
    }
    for (window, title) in windows {
        let succeeded = unsafe { PostMessageW(window, WM_CLOSE, 0, 0) };
        if succeeded == 0 {
            return Err(format!("failed to request Makepad window close: {title}"));
        }
    }
    Ok(())
}

fn stabilize_hidden() -> Result<(), String> {
    let started = Instant::now();
    let mut hidden_since = None;
    while started.elapsed() < Duration::from_secs(3) {
        set_visible(false)?;
        let all_hidden = benchmark_windows()
            .iter()
            .all(|(window, _)| unsafe { IsWindowVisible(*window) } == 0);
        if all_hidden {
            let since = hidden_since.get_or_insert_with(Instant::now);
            if since.elapsed() >= Duration::from_millis(500) {
                return Ok(());
            }
        } else {
            hidden_since = None;
        }
        thread::sleep(Duration::from_millis(25));
    }
    Err("Makepad windows did not remain hidden for 500 ms".to_string())
}

fn start_controller() {
    let log = EventLog::create(FRAMEWORK, event_log_path())
        .expect("failed to create benchmark event log");
    thread::spawn(move || {
        let result = (|| -> Result<(), String> {
            wait_for_initial_windows(Duration::from_secs(30))?;
            normalize_sizes()?;
            stabilize_hidden()?;
            log.emit(EventKind::ReadyHidden, None)
                .map_err(|error| error.to_string())?;

            let input = io::stdin();
            read_commands(input.lock(), |command| {
                match command {
                    Command::Show => {
                        log.emit(EventKind::ShowStart, None)
                            .map_err(|error| error.to_string())?;
                        set_visible(true)?;
                        log.emit(EventKind::ShowEnd, None)
                            .map_err(|error| error.to_string())?;
                    }
                    Command::Hide => {
                        log.emit(EventKind::HideStart, None)
                            .map_err(|error| error.to_string())?;
                        set_visible(false)?;
                        log.emit(EventKind::HideEnd, None)
                            .map_err(|error| error.to_string())?;
                    }
                    Command::Cycle { count } => {
                        log.emit(EventKind::CycleStart, Some(json!({ "count": count })))
                            .map_err(|error| error.to_string())?;
                        for _ in 0..count {
                            set_visible(true)?;
                            thread::sleep(Duration::from_millis(50));
                            set_visible(false)?;
                            thread::sleep(Duration::from_millis(50));
                        }
                        log.emit(EventKind::CycleEnd, Some(json!({ "count": count })))
                            .map_err(|error| error.to_string())?;
                    }
                    Command::Workload => {
                        log.emit(EventKind::WorkloadStart, None)
                            .map_err(|error| error.to_string())?;
                        log.emit(EventKind::WorkloadEnd, None)
                            .map_err(|error| error.to_string())?;
                    }
                    Command::Quit => {
                        log.emit(EventKind::Quit, None)
                            .map_err(|error| error.to_string())?;
                        close_windows()?;
                        return Ok(false);
                    }
                }
                Ok(true)
            })
        })();

        if let Err(error) = result {
            let _ = log.emit(EventKind::Error, Some(json!({ "message": error })));
            let _ = close_windows();
        }
    });
}
