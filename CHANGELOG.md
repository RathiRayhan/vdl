# Changelog

All notable changes to **vdl** are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Redesigned terminal output: a restyled banner, section headers per download
  phase, per-URL status lines with `[ok]`/`[fail]` markers, and an end-of-run
  summary with per-engine results, elapsed time, and save directory.
  `--quiet` still suppresses all of it.
- yt-dlp downloads now render a live progress bar
  (`[#########-----------] 43.3% 149KiB/s | ETA 00:01`) that updates in place;
  aria2c keeps its native per-file progress line.
- `--dedupe` flag: after the run, removes files whose content is identical to
  another file downloaded in the same run.  Only same-size files are hashed
  and the oldest copy is always kept, so pre-existing files are never
  deleted.  Opt-in; off by default.
- Pages without a dedicated yt-dlp extractor (`generic`/`html5`) are scanned
  for embedded images (`.jpg`, `.jpeg`, `.png`, `.webp`, `.gif`), which are
  downloaded with aria2c using a browser user-agent and the album page as
  referer.  The scan is scoped to the album via the playlist's media URLs:
  same-directory images are kept, video covers and sidebar thumbnails are
  skipped, and `/thumb/` previews upgrade to the full-size image (probing a
  `.jpg` sibling for `.webp` previews).  Photo-only albums no longer fail
  with `Unsupported URL`.  Known-site extractors and `--dry-run` are
  untouched.
- `docs/USAGE.md`: a user guide covering installation, setup, every feature
  with examples, and uninstallation.
- `--dry-run` flag: prints the resolved plan (engine, mode, URLs, save dir)
  without invoking yt-dlp or aria2c.
- `--download-dir DIR` flag: override `VDL_SAVE_DIR` for a single invocation.
- `--quiet` flag: suppress the banner and yt-dlp progress output.
- `--aria-opts OPTS` flag: pass extra options through to aria2c.
- `--max-speed RATE` and `--limit-speed RATE` flags: bandwidth throttling,
  forwarded to both aria2c and yt-dlp as appropriate.
- `magnet:` links and `.torrent` files are now recognised as direct downloads
  and routed to aria2c when available.
- Support for a vdl-specific config file at
  `$XDG_CONFIG_HOME/vdl/config` (or `~/.config/vdl/config`).  It is a simple
  `KEY=VALUE` file; recognised keys mirror the `VDL_*` environment variables.
  Command-line flags still take precedence over both.
- `man/vdl.1` man page, installed by `install.sh` alongside the binary.
- `Makefile` with `test`, `lint`, `install`, and `clean` targets.
- `CONTRIBUTING.md` guide.
- GitHub Actions CI workflow (shellcheck + smoke tests).
- README badges.
- `# shellcheck shell=bash` directives in all shell scripts.

### Changed
- The yt-dlp impersonation capability probe now only runs when yt-dlp will
  actually be invoked, avoiding a wasted subprocess on pure aria2c downloads.
- `install.sh` checks for write permission to the target prefix before
  installing and gives a clear error if `--system` is used without `sudo`.

### Fixed
- Forwarded yt-dlp options now keep their values adjacent.  Options such as
  `--download-archive` no longer consume the following flag as their argument.
- `--max-speed` and `--limit-speed` now map to the correct backend options:
  aria2c's overall and per-download limits, and yt-dlp's `--limit-rate`.
  Rates are converted to bytes, so values like `1.5M` and `1G` work.
- When aria2c fails, incomplete direct files are removed before the yt-dlp
  fallback, and only the downloads that actually failed are retried.  This
  avoids reporting success for a truncated file left by aria2c.

### Removed
- Dead `rc_clean` variable in `install.sh` (it was always `0`).
