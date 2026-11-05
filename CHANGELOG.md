# Changelog

All notable changes to **vdl** are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [2.0.0] - 2026-11-06

### Added

- Smart per-URL routing: direct files, magnet links and `.torrent` files go
  to aria2c (16 connections, resume); pages, playlists and streams go to
  yt-dlp (aria2c for HTTP(S) media, native for HLS/DASH).
- Redesigned terminal output: banner, per-phase section headers, per-URL
  `[ok]`/`[fail]` status, end-of-run summary, and a live progress bar with
  downloaded/total size, speed and ETA.
- Ordered passthrough: unknown options are forwarded to yt-dlp with their
  values attached, in their original order.
- Speed limits: `--max-speed` (aria2c overall limit) and `--limit-speed`
  (per-download limit) with `K`/`M`/`G` suffixes; yt-dlp receives the
  stricter non-zero value via `--limit-rate`.
- Safe aria2c fallback: only incomplete direct files are retried via
  yt-dlp, after removing partials and their `.aria2` control files.
- `--dedupe`: removes files downloaded in the same run whose content is
  identical to another (oldest copy kept; opt-in).
- Embedded image scanning: `--images` / `VDL_IMAGES=1` downloads album
  photos from generic/html5 pages into the album folder; favicons, logos,
  avatars, video covers and sidebar thumbnails are skipped; photo-only
  albums work without a failing yt-dlp run.
- Multi-line URL paste: a positional argument containing newlines is split
  into one URL per line (blank and non-URL lines ignored).
- Custom destinations: `--name` (filename or playlist folder name) and
  `--output` (exact file path or folder for a single URL).
- Configuration: `VDL_*` environment variables and a `KEY=VALUE` config
  file with CLI > environment > config > defaults precedence.
- Browser cookies (auto-detected or `-b NAME:PROFILE`), TLS impersonation
  probing, custom headers, proxy, and clipboard URL pickup.
- `--dry-run` plan preview, `--quiet`, `--download-dir`, `--aria-opts`,
  audio extraction (`-a`, MP3 320k), and quality caps with `2k`/`4k`/`8k`
  aliases.
- Friendly Ctrl+C handling with a resume hint (exit 130).
- Installer/uninstaller with bash/zsh/fish completions and a man page.
- Network-free smoke test suite and unit tests for pure helpers; CI runs
  ShellCheck plus both suites.

### Changed

- Code base restructured into a thin `bin/vdl` orchestrator and focused
  libraries under `lib/vdl/` (ui, helpers, images, downloads, args,
  settings, collect, paths, classify, ytdlp, plan).
- yt-dlp runs with `--ignore-config` and vdl's own defaults, optionally
  extended by `~/.config/vdl/yt-dlp.conf`.
- aria2c always receives `-Z`, so multiple URLs download as separate files
  instead of being treated as mirrors of one.

### Fixed

- `.tgz`/`.tbz2`/`.tbz`/`.txz`/`.tlz` URLs are classified as direct files.
- Embedded-image pages are fetched to a temp file and parsed only when the
  response is HTML, so binary responses are never slurped into a variable.
- Symlinked `vdl` binaries can find their libraries.
- `--output` and images-only albums show the correct engine/mode in the
  banner.

## [1.0.0] - 2026-10-28

Initial release as a Bash rewrite of the original fish-function downloader.
