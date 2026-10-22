# Changelog

All notable changes to **vdl** are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
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

### Removed
- Dead `rc_clean` variable in `install.sh` (it was always `0`).
