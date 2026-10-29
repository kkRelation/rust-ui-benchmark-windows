use std::thread;
use std::time::{Duration, Instant};

use windows_sys::Win32::Foundation::HWND;
use windows_sys::Win32::System::Threading::GetCurrentProcessId;
use windows_sys::Win32::UI::WindowsAndMessaging::{
    FindWindowExW, GetWindowThreadProcessId, SW_HIDE, SW_SHOWNOACTIVATE, ShowWindow,
};

pub const MAIN_TITLE: &str = "UI Framework Bench - Main";
pub const AUXILIARY_TITLE: &str = "UI Framework Bench - Auxiliary Canvas";

fn is_benchmark_window(process_id: u32, expected_process_id: u32, title: &str) -> bool {
    process_id == expected_process_id && (title == MAIN_TITLE || title == AUXILIARY_TITLE)
}

fn benchmark_windows() -> Vec<HWND> {
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
            if is_benchmark_window(process_id, expected_process_id, title) {
                windows.push(window);
            }
            previous = window;
        }
    }
    windows
}

pub fn benchmark_windows_ready() -> Result<bool, String> {
    let count = benchmark_windows().len();
    match count {
        0 | 1 => Ok(false),
        2 => Ok(true),
        _ => Err(format!("expected two benchmark windows, found {count}")),
    }
}

pub fn wait_for_benchmark_windows() -> Result<(), String> {
    let deadline = Instant::now() + Duration::from_secs(60);
    loop {
        if benchmark_windows_ready()? {
            return Ok(());
        }
        if Instant::now() >= deadline {
            return Err("timed out waiting for two benchmark windows".to_owned());
        }
        thread::sleep(Duration::from_millis(20));
    }
}

pub fn set_benchmark_windows_visible(visible: bool) -> Result<(), String> {
    let windows = benchmark_windows();
    if windows.len() != 2 {
        return Err(format!(
            "expected two benchmark windows, found {}",
            windows.len()
        ));
    }
    for window in windows {
        unsafe {
            ShowWindow(window, if visible { SW_SHOWNOACTIVATE } else { SW_HIDE });
        }
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn filter_accepts_only_exact_titles_in_the_current_process() {
        assert!(is_benchmark_window(42, 42, MAIN_TITLE));
        assert!(is_benchmark_window(42, 42, AUXILIARY_TITLE));
        assert!(!is_benchmark_window(7, 42, MAIN_TITLE));
        assert!(!is_benchmark_window(42, 42, "UI Framework Bench"));
        assert!(!is_benchmark_window(42, 42, "UI Framework Bench - Main "));
    }
}
