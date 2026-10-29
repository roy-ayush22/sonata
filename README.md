# Sonata

Sonata is a Linux-first, offline music player based on the desktop Flutter and Rust application from [Mornye](https://github.com/mornyeapp/Mornye). Its desktop shell opens to the local library, with Mornye's sidebar, floating player, lyrics and Up Next inspector, full-screen player, keyboard shortcuts, metadata editor, playlists, and folder watching.

Song discovery and download destinations are removed from Sonata's desktop navigation and player. Local playback, library scanning, tag editing, and local `.lrc` lyrics work offline. Configured lyrics providers can use the network when you choose to fetch lyrics.

## Linux requirements

- Flutter 3.47.x and Dart 3.10 or newer
- Rust toolchain pinned by `rust_backend/rust-toolchain.toml` (Rust 1.99.0)
- Clang/libclang, CMake, Ninja, GTK 3, ALSA, libmpv, GStreamer, and libsecret development packages

On Ubuntu or Linux Mint:

```sh
sudo apt update
sudo apt install build-essential clang cmake ninja-build pkg-config zip \
  libgtk-3-dev liblzma-dev libsecret-1-dev libstdc++-12-dev \
  libjson-glib-dev libgstreamer1.0-dev libgstreamer-plugins-base1.0-dev \
  libasound2-dev libclang-dev libmpv-dev
```

The first build downloads Flutter and Rust dependencies. After dependencies are cached, local playback does not need internet access.

## Run Sonata from source

Run these commands from the project root:

```sh
flutter pub get
bash scripts/build_rust_backend.sh desktop
flutter run -d linux
```

The repository pins Flutter 3.47.7 in `.fvmrc`; Flutter 3.47.8 should also satisfy the Dart SDK constraint. Rustup reads the pinned Rust version when the backend build script enters `rust_backend/`.

## Build a Linux release

```sh
bash scripts/build_rust_backend.sh desktop
flutter build linux --release
```

Flutter writes the application bundle under `build/linux/`. To package it as a Debian package, run:

```sh
bash scripts/package_linux.sh deb build/linux/x64/release/bundle 0.1.0 /tmp/sonata.deb
```

## Use the library and player

- Add a music folder from the Library. Sonata watches it for new and changed tracks while the app is open.
- Select a local track to play it. Space toggles playback; Ctrl/Cmd + Left/Right skips, and Ctrl/Cmd + Up/Down adjusts volume.
- Use the player controls to open Lyrics or Up Next beside the current library page. Full-screen player mode presents the artwork beside lyrics.
- Add same-name `.lrc` files beside tracks for local lyrics. Timed lines, translation, and romanization are shown when available in the file or an enabled lyrics source.
- Edit tags, review duplicate tracks, search and sort the library, and manage local playlists from the Library sidebar.

## License and attribution

Sonata adapts Mornye. The upstream `LICENSE`, `COPYING`, `NOTICE`, and bundled third-party license notices are retained; review those files before redistributing builds. Mornye is licensed under LGPL-3.0-only with the incorporated GPL-3.0 terms.
