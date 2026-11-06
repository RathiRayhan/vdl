# Changelog

All notable changes to **vdl** are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [2.2.10] - 2026-11-06

### Fixed

- Made the browser-UA smoke test deterministic: the probe-launch assertion
  raced the probe's process kill and could fail spuriously on fast machines.

## [2.2.9] - 2026-11-06

### Added

- A bare `--download-dir` name (`custom-dir`, `albums/xyz`) is created
  inside the default vdl folder instead of the current directory.  Paths
  starting with `/`, `~/`, or `./` keep their literal meaning.  A quoted
  `~/path` now also expands to the home directory.

## [2.2.8] - 2026-11-06

### Changed

- Branded as **vdl — Versatile Downloader for Linux** across the banner,
  README, man page, usage text, and the user guide.

## [2.2.7] - 2026-11-06

### Fixed

- Removed an unused variable in the clipboard reader that ShellCheck 0.9
  flagged, restoring a green lint job in CI.

## [2.2.6] - 2026-11-06

### Fixed

- The clipboard fallback now queues **every** URL line instead of only the
  first, so copying several links (one per line) and running bare `vdl`
  downloads all of them.

## [2.2.5] - 2026-11-06

### Changed

- The probed browser User-Agent is cached per browser version in
  `~/.cache/vdl/`, so the headless probe runs only after a browser update
  instead of on every cookie-enabled run.

## [2.2.4] - 2026-11-06

### Added

- When cookies come from a browser, vdl mirrors that browser's exact
  User-Agent (probed headlessly from the installed binary), so Cloudflare
  clearance cookies stay valid.  An explicit `--user-agent` still wins.
- A run that fails with a 403 now suggests opening the page in the browser
  once to solve a possible Cloudflare challenge, then rerunning to reuse
  the session cookies.

## [2.2.3] - 2026-11-06

### Fixed

- Browser impersonation now resolves real targets from yt-dlp's capability
  list: versioned names (`Chrome-133`, `Chrome-136`) are matched instead of
  the bare client name, and the newest target of the family's primary OS is
  picked — the ones the installed curl_cffi actually supports.  This makes
  `--impersonate` engage on machines where it previously stayed silent, and
  never passes a target the installed curl_cffi cannot produce (such as
  `chrome152`).

## [2.2.2] - 2026-11-06

### Changed

- yt-dlp's lowercase log tags (`[download]`, `[info]`, `[generic]`, ...)
  are now capitalized in vdl's output, matching the rest of the UI.

## [2.2.1] - 2026-11-06

### Fixed

- A trailing slash in `--download-dir`, `--output` or `VDL_SAVE_DIR` no
  longer produces `dir//file` paths (the slash is normalized away).
- Empty download phases no longer print a zero-progress `Run 0/n` line;
  the run counter appears only after something completes.

## [2.2.0] - 2026-11-06

### Changed

- aria2c leftovers are swept automatically on exit: a `.aria2` control file
  and its partial, both older than `VDL_TMP_KEEP_DAYS`, are removed.  When
  aria2c fails and yt-dlp is unavailable, the partial is kept for a later
  resume instead of being deleted.
- Terminal output polish: an aligned label column with the colon at a fixed
  position, `✓`/`✗` result glyphs, a bracket-free `Run n/m` counter,
  capitalized engine/mode values, title-cased section headers, and a
  `Failed` section in the summary.
- CI apt steps use retries and explicit timeouts so a stalled mirror fails
  fast instead of hanging.

### Fixed

- `--zip` no longer passes `--` to the archive command (real Info-ZIP
  rejects it; the test shim had masked this).
- The HTML image extractor prefers `data-src`/`src` over `data-rotate-src`
  when both appear on the same tag (grid thumbnails were hiding real photo
  URLs).

## [2.1.0] - 2026-11-05

### Added

- `--output PATH`: pins a single URL to an exact file path or folder.
- `--zip[=NAME.zip]`: archives a run's downloads into a single zip in the
  save directory (runs after `--dedupe`; requires the `zip` command).
- Multi-line URL paste: pasted blocks are split into one URL per line.
- Run-level progress counter, a failure recap with per-URL reasons in the
  summary, a scanning indicator during `--images`, and a
  terminal-width-adaptive progress bar.
- Integration test suite (`test/integration.sh`) that drives the real
  yt-dlp/aria2c/ffmpeg against a local fixture, wired into CI.
- A python3 HTML image extractor (`lib/vdl/scrape.py`) for `--images`,
  replacing the fragile regex pipeline when python3 is available.

### Changed

- `--images` scans pages only after the media downloads finish, so videos
  always complete first (a light preflight still drops image-only pages
  from the media queue early).
- CI runs ShellCheck, smoke, unit, and integration suites.

## [2.0.0] - 2026-11-04

### Added

- Smart per-URL routing: direct files, magnet links and `.torrent` files go
  to aria2c (16 connections, resume); pages, playlists and streams go to
  yt-dlp (aria2c for HTTP(S) media, native for HLS/DASH).
- Redesigned terminal output: banner, per-phase section headers, per-URL
  status, end-of-run summary, and a live progress bar with downloaded/total
  size, speed and ETA.
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
- Custom destinations: `--name` (filename or playlist folder name).
- Configuration: `VDL_*` environment variables and a `KEY=VALUE` config
  file with CLI > environment > config > defaults precedence.
- Browser cookies (auto-detected or `-b NAME:PROFILE`), TLS impersonation
  probing, custom headers, proxy, and clipboard URL pickup.
- `--dry-run` plan preview, `--quiet`, `--download-dir`, `--aria-opts`,
  audio extraction (`-a`, MP3 320k), and quality caps with `2k`/`4k`/`8k`
  aliases.
- Friendly Ctrl+C handling with a resume hint (exit 130).
- Installer/uninstaller with bash/zsh/fish completions and a man page.
- Network-free smoke test suite and unit tests for pure helpers.

### Changed

- Code base restructured into a thin `bin/vdl` orchestrator and focused
  libraries under `lib/vdl/`.
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
