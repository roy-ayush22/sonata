//! Small, dependency-free library indexer exposed as a C ABI for the Flutter UI.
//! Build with `cargo build --release -p sonata_core` and place the resulting
//! `libsonata_core.so` beside the Linux executable.

use std::{
    ffi::CStr,
    fs,
    os::raw::c_char,
    path::{Path, PathBuf},
};

const AUDIO_EXTENSIONS: &[&str] = &[
    "mp3", "flac", "ogg", "opus", "m4a", "aac", "wav", "aiff", "ape", "wv",
];

#[no_mangle]
pub unsafe extern "C" fn sonata_scan_json(
    folder: *const c_char,
    out: *mut c_char,
    capacity: usize,
) -> isize {
    if folder.is_null() || out.is_null() || capacity == 0 {
        return -1;
    }
    let folder = match CStr::from_ptr(folder).to_str() {
        Ok(v) => Path::new(v),
        Err(_) => return -2,
    };
    let mut paths = Vec::new();
    scan(folder, &mut paths);
    paths.sort();
    let payload = format!(
        "[{}]",
        paths
            .iter()
            .map(|path| {
                let title = path
                    .file_stem()
                    .and_then(|v| v.to_str())
                    .unwrap_or("Unknown track");
                format!(
                    "{{\"path\":\"{}\",\"title\":\"{}\"}}",
                    escape(&path.to_string_lossy()),
                    escape(title)
                )
            })
            .collect::<Vec<_>>()
            .join(",")
    );
    if payload.len() + 1 > capacity {
        return -(payload.len() as isize);
    }
    std::ptr::copy_nonoverlapping(payload.as_ptr(), out.cast(), payload.len());
    *out.add(payload.len()) = 0;
    payload.len() as isize
}

fn scan(dir: &Path, found: &mut Vec<PathBuf>) {
    let Ok(entries) = fs::read_dir(dir) else {
        return;
    };
    for entry in entries.flatten() {
        let path = entry.path();
        if path.is_dir() {
            scan(&path, found);
        } else if path
            .extension()
            .and_then(|e| e.to_str())
            .is_some_and(|e| AUDIO_EXTENSIONS.contains(&e.to_ascii_lowercase().as_str()))
        {
            found.push(path);
        }
    }
}

fn escape(value: &str) -> String {
    value
        .chars()
        .flat_map(|c| match c {
            '"' => "\\\"".chars().collect::<Vec<_>>(),
            '\\' => "\\\\".chars().collect(),
            '\n' => "\\n".chars().collect(),
            '\r' => "\\r".chars().collect(),
            '\t' => "\\t".chars().collect(),
            c if c.is_control() => " ".chars().collect(),
            c => vec![c],
        })
        .collect()
}
