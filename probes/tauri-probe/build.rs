use std::{env, fs, path::PathBuf};

fn main() {
    // tauri-build requires a Windows icon even when bundling is disabled. Keep
    // the benchmark source-only by generating a deterministic 1x1 32-bit ICO
    // in Cargo's disposable output directory.
    let icon_path = PathBuf::from(env::var_os("OUT_DIR").expect("OUT_DIR is set by Cargo"))
        .join("benchmark.ico");
    fs::write(&icon_path, benchmark_icon()).expect("write generated benchmark icon");

    let attributes = tauri_build::Attributes::new()
        .windows_attributes(tauri_build::WindowsAttributes::new().window_icon_path(icon_path));
    tauri_build::try_build(attributes).expect("failed to run tauri-build");
}

fn benchmark_icon() -> &'static [u8] {
    // ICONDIR + one ICONDIRENTRY + BITMAPINFOHEADER + BGRA pixel + AND mask.
    &[
        0x00, 0x00, 0x01, 0x00, 0x01, 0x00, // ICONDIR
        0x01, 0x01, 0x00, 0x00, 0x01, 0x00, 0x20, 0x00, 0x30, 0x00, 0x00, 0x00, 0x16, 0x00, 0x00,
        0x00, // ICONDIRENTRY
        0x28, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x02, 0x00, 0x00, 0x00, 0x01, 0x00, 0x20,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x04, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, // BITMAPINFOHEADER
        0xD4, 0x78, 0x00, 0xFF, // one opaque BGRA pixel
        0x00, 0x00, 0x00, 0x00, // one padded transparency-mask row
    ]
}
