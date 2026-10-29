use windows_sys::Win32::Foundation::{HWND, LPARAM};
use windows_sys::Win32::System::Threading::GetCurrentProcessId;
use windows_sys::Win32::UI::WindowsAndMessaging::{
    EnumWindows, GetWindowTextLengthW, GetWindowTextW, GetWindowThreadProcessId, SW_HIDE,
    SW_SHOWNOACTIVATE, ShowWindow,
};
use windows_sys::core::BOOL;

pub const MAIN_TITLE: &str = "UI Framework Bench - Main";
pub const AUXILIARY_TITLE: &str = "UI Framework Bench - Auxiliary Canvas";

fn is_benchmark_window(process_id: u32, expected_process_id: u32, title: &str) -> bool {
    process_id == expected_process_id && (title == MAIN_TITLE || title == AUXILIARY_TITLE)
}

unsafe extern "system" fn enum_window(hwnd: HWND, parameter: LPARAM) -> BOOL {
    let windows = unsafe { &mut *(parameter as *mut Vec<HWND>) };
    let mut process_id = 0_u32;
    unsafe { GetWindowThreadProcessId(hwnd, &mut process_id) };

    let expected_process_id = unsafe { GetCurrentProcessId() };
    let length = unsafe { GetWindowTextLengthW(hwnd) };
    if length <= 0 {
        return 1;
    }

    let mut buffer = vec![0_u16; length as usize + 1];
    let copied = unsafe { GetWindowTextW(hwnd, buffer.as_mut_ptr(), buffer.len() as i32) };
    let title = String::from_utf16_lossy(&buffer[..copied as usize]);
    if is_benchmark_window(process_id, expected_process_id, &title) {
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

pub fn benchmark_windows_ready() -> Result<bool, String> {
    let count = benchmark_windows().len();
    match count {
        0 | 1 => Ok(false),
        2 => Ok(true),
        _ => Err(format!("expected two benchmark windows, found {count}")),
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
