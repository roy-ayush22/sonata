# Sonata

Sonata is an offline-first Linux music player prototype built with Flutter and a small Rust library indexer. Its visual direction follows the provided desktop reference: cool lavender library surfaces, warm translucent playback panel, pastel accents, and lyrics beside the cover.

## Current app

- Browse a seeded demo album, search and sort the library, open the Up Next pane, and edit track details in the current session.
- Add a local folder. The Rust core scans common audio extensions; if its shared library is not available, Flutter's local filesystem scan is used. Added folders are rescanned every 15 seconds while the app is open.
- Play local files through `just_audio`, seek, change volume, and use Space to play/pause, Ctrl/⌘ + Left/Right to skip, and Ctrl/⌘ + Up/Down to adjust volume.
- The demo album and lyric lines are illustrative UI content. Lyrics, provider ordering, persistent tag writing, playlists, and duplicate matching still need their data and storage implementations.

## Build on Linux

Install the Flutter stable SDK and Linux desktop prerequisites from the official Flutter Linux setup guide. Then, from this directory:

```sh
flutter pub get
cargo build --release -p sonata_core
CXX=/usr/bin/g++ flutter run -d linux
```

Playback uses `just_audio_media_kit` with the Linux native media libraries; the app limits allowed playback sources to local files.

The Rust shared library is searched for as `libsonata_core.so`, `./libsonata_core.so`, `target/release/libsonata_core.so`, and `rust_core/target/release/libsonata_core.so`. Cargo's default workspace output is `target/release/libsonata_core.so`.

Flutter 3.47.8 is installed on the machine. This build sandbox cannot resolve `pub.dev`, so Flutter dependencies cannot be fetched here; run `flutter pub get` from a network-enabled terminal. `clang++` is not installed in the current environment, but `/usr/bin/g++` is available and can be selected with `CXX=/usr/bin/g++` for the Linux build. GTK 3 development headers, CMake, and Ninja are also required.

## Rust C ABI

`sonata_scan_json(folder, output, capacity)` writes a JSON array of audio file paths and filename-based titles into a caller-owned buffer. This keeps ownership straightforward across the Dart FFI boundary and keeps the indexer dependency-free.
