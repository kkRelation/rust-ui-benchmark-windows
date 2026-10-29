use std::time::{Duration, Instant};

use windows_sys::Win32::Foundation::HWND;
use windows_sys::Win32::System::Threading::GetCurrentProcessId;
use windows_sys::Win32::UI::HiDpi::GetDpiForWindow;
use windows_sys::Win32::UI::WindowsAndMessaging::{
    FindWindowExW, GetWindowThreadProcessId, IsWindowVisible, SW_HIDE, SW_SHOWNOACTIVATE,
    SWP_NOACTIVATE, SWP_NOMOVE, SWP_NOZORDER, SetWindowPos, ShowWindow,
};

use crate::scene::{AUXILIARY_OUTER_SIZE, AUXILIARY_TITLE, MAIN_OUTER_SIZE, MAIN_TITLE};

fn is_benchmark_window(process_id: u32, expected_process_id: u32, title: &str) -> bool {
    process_id == expected_process_id && (title == MAIN_TITLE || title == AUXILIARY_TITLE)
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
            if is_benchmark_window(process_id, expected_process_id, title) {
                windows.push((window, title));
            }
            previous = window;
        }
    }
    windows
}

pub fn wait_for_benchmark_windows(timeout: Duration) -> Result<(), String> {
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
        std::thread::sleep(Duration::from_millis(25));
    }
    Err(format!(
        "expected two initially visible benchmark windows within {} ms, found {}",
        timeout.as_millis(),
        benchmark_windows().len()
    ))
}

pub fn stabilize_benchmark_windows_hidden(
    timeout: Duration,
    stable_for: Duration,
) -> Result<(), String> {
    let started = Instant::now();
    let mut hidden_since = None;
    while started.elapsed() < timeout {
        set_visible_for_benchmark_windows(false)?;
        let all_hidden = benchmark_windows()
            .iter()
            .all(|(window, _)| unsafe { IsWindowVisible(*window) } == 0);
        if all_hidden {
            let since = hidden_since.get_or_insert_with(Instant::now);
            if since.elapsed() >= stable_for {
                return Ok(());
            }
        } else {
            hidden_since = None;
        }
        std::thread::sleep(Duration::from_millis(25));
    }
    Err(format!(
        "benchmark windows did not remain hidden for {} ms",
        stable_for.as_millis()
    ))
}

pub fn set_visible_for_benchmark_windows(visible: bool) -> Result<(), String> {
    let windows = benchmark_windows();
    if windows.len() != 2 {
        return Err(format!(
            "expected two benchmark windows, found {}",
            windows.len()
        ));
    }
    for (window, _) in windows {
        unsafe {
            ShowWindow(window, if visible { SW_SHOWNOACTIVATE } else { SW_HIDE });
        }
    }
    Ok(())
}

pub fn normalize_benchmark_window_sizes() -> Result<(), String> {
    let windows = benchmark_windows();
    if windows.len() != 2 {
        return Err(format!(
            "expected two benchmark windows, found {}",
            windows.len()
        ));
    }
    for (window, title) in windows {
        let (logical_width, logical_height) = if title == MAIN_TITLE {
            MAIN_OUTER_SIZE
        } else {
            AUXILIARY_OUTER_SIZE
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
            return Err(format!("failed to size benchmark window: {title}"));
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
    }
}
