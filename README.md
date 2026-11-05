# vdl

[![CI](https://github.com/RathiRayhan/vdl/actions/workflows/ci.yml/badge.svg)](https://github.com/RathiRayhan/vdl/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

**vdl** is a smart downloader for Linux. Give it any URL — a file, a video,
a playlist, a magnet link — and it picks the right engine: **aria2c** for
direct files (fast, resumable, multi-connection) and **yt-dlp** for pages,
playlists, and streams. One command handles mixed input, browser cookies,
speed limits, custom names, and embedded album images.

## Features

- **Smart per-URL routing** — direct files, torrents and magnets go to
  aria2c; pages, playlists and streams go to yt-dlp; mixed lists use both.
- **Fast, resumable downloads** — 16 aria2c connections per direct file,
  resume support, and 10 connections for media transfers.
- **Flexible input** — multiple URLs, pasted multi-line URL blocks, batch
  files, and clipboard pickup; duplicates are removed automatically.
- **Media handling** — configurable quality cap (`-q`, `2k`/`4k`/`8k`
  aliases), MP4 merging, HLS/DASH via yt-dlp's native downloader.
- **Audio extraction** — `-a` converts to MP3 320k under
  `<save_dir>/audio`.
- **Browser integration** — auto-detects cookies from your browser
  (`firefox:work` profiles supported), `-n` to disable, and optional TLS
  impersonation.
- **Exact destinations** — `--name` renames a file or playlist folder,
  `--output` pins a URL to an exact file path or folder.
- **Bandwidth controls** — overall and per-download limits with `K`/`M`/`G`
  suffixes, mapped correctly to both engines.
- **Safe recovery** — if aria2c fails, only incomplete files are retried
  with yt-dlp; `--dedupe` removes duplicate files from a run.
- **Embedded album images** — `--images` (opt-in) scans generic/html5 pages
  and downloads photos into the album folder.
- **Ordered passthrough** — any unknown option is forwarded to yt-dlp with
  its value attached, in order.
- **Friendly output** — banner, per-URL status, live progress bar, and an
  end-of-run summary; `--quiet` silences it all.
- **Self-contained defaults** — yt-dlp runs with `--ignore-config` plus
  vdl's own settings, optionally extended by `~/.config/vdl/yt-dlp.conf`.

## Quick start

```sh
git clone https://github.com/RathiRayhan/vdl.git
cd vdl
./install.sh                     # installs to ~/.local/bin + completions

vdl "https://example.com/video"
vdl "https://example.com/file.iso" "https://example.com/video"   # mixed input
```

## Install

```sh
./install.sh                     # ~/.local/bin + completions for detected shells
./install.sh --shells bash,zsh,fish
./install.sh --system            # /usr/local (run with sudo)
./install.sh --no-completions
./install.sh --uninstall
```

The installer places `vdl` in `<prefix>/bin`, its libraries in
`<prefix>/lib/vdl`, the man page in `<prefix>/share/man/man1`, and shell
completions for bash, zsh and fish. If `~/.local/bin` is not on your `PATH`,
the installer prints the line to add; for zsh it prints the `fpath` line
needed before `compinit`.

## Usage

```sh
vdl                                     # URL from the clipboard
vdl "https://example.com/video"
vdl "https://example.com/a" "https://example.com/b"   # multiple URLs
vdl 'https://example.com/one
https://example.com/two'                # paste a URL block, one per line
vdl links.txt                           # every URL listed in links.txt
vdl -q 720 links.txt
vdl -a "https://example.com/album"      # MP3 320k
vdl -n "https://example.com/file.iso"   # direct file, no cookies
vdl --no-aria -F "https://example.com/video"

vdl -b firefox:work "https://example.com"
vdl --proxy http://127.0.0.1:8080 "https://example.com"
vdl --dry-run "https://example.com/file.iso"          # preview routing
vdl --download-dir ~/tmp "https://example.com/file.zip"
vdl --quiet "https://example.com/video"               # no banner
vdl --max-speed 2M "https://example.com/file.iso"     # overall limit
vdl --limit-speed 500K "https://example.com/file.iso" # per-download limit
vdl --name my-rom "https://example.com/file.iso"      # custom filename
vdl --output ~/Videos/movie.mp4 "https://example.com/video"  # exact path
vdl --images "https://example.com/album/abc123"       # include album photos
vdl --aria-opts "--check-interval=30" "https://example.com/file.iso"
vdl --download-archive seen.txt -f "bv*+ba" \
  "https://example.com/video"                         # passthrough values stay attached
vdl 'magnet:?xt=urn:btih:abc123'                      # torrent magnet
```

All flags apply to every URL in a run. Unknown options are forwarded to
yt-dlp with their values in order, so `-F`, `--playlist-start`,
`--download-archive`, and friends work.

### Routing

| URL looks like | Engine |
|----------------|--------|
| archive/package/document (`zip`, `iso`, `pdf`, `deb`, ...) | aria2c, 16 connections |
| magnet links, `.torrent` files | aria2c, 16 connections |
| plain video file (`mp4`, `mkv`, `webm`, ...) | aria2c (yt-dlp in `-a` mode) |
| HLS/DASH (`m3u8`, `mpd`) | yt-dlp native, 8 fragments |
| pages, playlists, everything else | yt-dlp + aria2c (10 connections) |

The check uses the last path extension, so stacked suffixes like `.tar.gz`
or `.zip.gz` classify as direct.

### Naming

- Single videos land flat in the save directory as `<title> [<id>].<ext>`.
- Playlist and album entries get a folder named after the playlist/album.
- `-a` writes MP3 files to `<save_dir>/audio` with the same layout.
- `--name` renames a single download (extension appended when missing);
  on a playlist URL it names the folder instead.
- `--output` pins a single URL to an exact file path (extension in the last
  component) or an exact folder (playlist items go directly inside).

## Options

Run `vdl --help` for details, or `man vdl` after installing.

| Flag | Meaning |
|------|---------|
| `-b, --browser NAME` | Browser to take cookies from (`NAME:PROFILE` works); auto-detected by default |
| `-n, --no-cookies` | Do not read browser cookies |
| `-q, --quality HEIGHT` | Max video height (`720`, `1080`, `2k`, `4k`, `8k`) |
| `-a, --audio` | Audio only, converted to MP3 320k |
| `-i, --batch-file FILE` | Read URLs from a file (repeatable) |
| `--no-aria` | Send direct files through yt-dlp |
| `--no-impersonate` | Disable browser TLS impersonation |
| `--download-dir DIR` | Override the save directory for this run |
| `--dry-run` | Print the resolved plan without downloading |
| `--dedupe` | Remove duplicate files downloaded in this run |
| `--images` | Also download images embedded in album pages |
| `--quiet` | Suppress banner, status and progress output |
| `--aria-opts OPTS` | Extra options forwarded to aria2c |
| `--max-speed RATE` | Overall download speed limit |
| `--limit-speed RATE` | Per-download speed limit |
| `--name NAME` | Custom filename (or playlist folder name) |
| `--output PATH` | Exact destination: file or folder for a single URL |
| `--referer URL` | Send this Referer header |
| `--user-agent UA` | Send this User-Agent header |
| `--proxy URL` | Route downloads through this proxy |
| `-h, --help` | Show help |
| `-V, --version` | Show version |

## Configuration

| Variable | Default | Meaning |
|----------|---------|---------|
| `VDL_SAVE_DIR` | `$(xdg-user-dir DOWNLOAD)/vdl` | exact download directory |
| `VDL_BROWSER` | auto-detect | default cookie source |
| `VDL_QUALITY` | `1080` | default max height |
| `VDL_TMP_KEEP_DAYS` | `7` | keep interrupted leftovers this long |
| `VDL_IMPERSONATE` | `auto` | `auto`, `off`, or a browser target |
| `VDL_IMAGES` | unset | `1`/`yes` to always scan album pages for images |
| `VDL_CONFIG` | `~/.config/vdl/yt-dlp.conf` | extra yt-dlp options, loaded if present |
| `VDL_CONFIG_DIR` | `~/.config/vdl` | directory for vdl's own config file |
| `NO_COLOR` | unset | disable colored output |

Precedence: **command line > environment > config file > defaults**.

A small `KEY=VALUE` config file sets the same defaults:

```sh
# ~/.config/vdl/config
QUALITY=720
BROWSER=firefox
SAVE_DIR=~/Downloads/vdl
IMPERSONATE=chrome
TMP_KEEP_DAYS=7
```

`VDL_CONFIG` is an ordinary yt-dlp config file loaded *in addition* to vdl's
built-in defaults.

## Behavior details

**Speed limits** accept a byte rate with an optional case-insensitive `K`,
`M`, or `G` suffix (1024-based); decimals need a suffix (`1.5M`), `0` means
unlimited. `--max-speed` maps to aria2c's overall limit, `--limit-speed` to
its per-download limit; yt-dlp receives `--limit-rate` with the stricter
non-zero value when both are set.

**aria2c fallback:** if aria2c fails, vdl removes interrupted partials and
retries only the incomplete HTTP(S) files with yt-dlp; completed files are
untouched and magnet/torrent payloads are never retried.

**Embedded images (`--images`):** opt-in scan of pages without a dedicated
yt-dlp extractor. Only album-scoped `<img>` sources are taken (favicons,
logos, avatars, video covers and sidebar thumbnails are skipped), `/thumb/`
previews upgrade to the full-size image, and photos land in the album folder
next to the videos.

See **[docs/USAGE.md](docs/USAGE.md)** for the complete walk-through of every
feature, **[docs/SPEC.md](docs/SPEC.md)** for the behavior contract, and
**[CONTRIBUTING.md](CONTRIBUTING.md)** if you want to hack on it.

## How it works

`vdl` is a small Bash program — an orchestrator plus focused libraries —
not a daemon. Each run goes through: parse arguments → resolve settings →
collect URLs → classify and plan → build downloader commands → download →
clean up and summarize. Because direct aria2c downloads are not driven by
yt-dlp, they receive user-agent, referer, proxy and aria2c options, but not
browser cookies or yt-dlp-only flags; use `--no-aria` for cookie-protected
direct links.

## YouTube HD formats (optional)

YouTube sometimes exposes only format `18` (360p) and warns that it is
"forcing SABR streaming". This is account- or client-specific, not a vdl
setting. A PO token provider restores the full format list.

1. Install the provider server (Deno 2 is required):

```sh
git clone --depth 1 --branch 2.0.2 \
  https://github.com/Brainicism/bgutil-ytdlp-pot-provider.git \
  ~/.local/share/bgutil-ytdlp-pot-provider
cd ~/.local/share/bgutil-ytdlp-pot-provider/server
deno install --allow-scripts=npm:canvas --frozen
```

2. Install the yt-dlp plugin from the matching release ZIP (or
   `python3 -m pip install -U bgutil-ytdlp-pot-provider`):

```sh
tmp=$(mktemp -d)
curl -fL -o "$tmp/plugin.zip" \
  https://github.com/Brainicism/bgutil-ytdlp-pot-provider/releases/download/2.0.2/bgutil-ytdlp-pot-provider.zip
mkdir -p ~/.config/yt-dlp/plugins/bgutil-ytdlp-pot-provider
unzip -q "$tmp/plugin.zip" -d ~/.config/yt-dlp/plugins/bgutil-ytdlp-pot-provider
rm -rf "$tmp"
```

3. Run the provider as a systemd user service (listens on `127.0.0.1:4416`).
   Create `~/.config/systemd/user/bgutil-pot-provider.service`:

```ini
[Unit]
Description=bgutil POT provider for yt-dlp
After=network.target

[Service]
Type=simple
WorkingDirectory=%h/.local/share/bgutil-ytdlp-pot-provider/server/node_modules
ExecStart=/usr/bin/deno run --allow-env --allow-net --allow-ffi=. --allow-read=. ../src/main.ts
Restart=on-failure
RestartSec=3

[Install]
WantedBy=default.target
```

```sh
systemctl --user daemon-reload
systemctl --user enable --now bgutil-pot-provider.service
```

4. If the default web client still offers only 360p, select a client that
   exposes the DASH/HLS formats in `~/.config/vdl/yt-dlp.conf`:

```
--extractor-args "youtube:player_client=web_safari"
```

Check the result without downloading:

```sh
vdl -F "https://youtu.be/..."
```

Rows up to `1920x1080` mean the provider is working.

## Layout

```
bin/vdl               the command (orchestrator)
lib/vdl/              sourced libraries: ui, helpers, images, downloads,
                      args, settings, collect, paths, classify, ytdlp, plan
install.sh            installer / uninstaller
completions/          bash, zsh and fish completions
man/vdl.1             man page
docs/USAGE.md         full user guide
docs/SPEC.md          behavior contract for maintainers
test/smoke.sh         stub-based test suite (no network required)
test/unit.sh          unit tests for pure helper functions
Makefile              convenience targets (test, lint, install)
```

## Uninstall

```sh
./install.sh --uninstall          # with the same --prefix/--system used to install
```

If you previously used `~/.config/fish/functions/vdl.fish`, remove it — fish
functions shadow binaries on `PATH`. To remove the optional YouTube PO token
provider:

```sh
systemctl --user disable --now bgutil-pot-provider.service
rm -f ~/.config/systemd/user/bgutil-pot-provider.service
rm -rf ~/.local/share/bgutil-ytdlp-pot-provider
rm -rf ~/.config/yt-dlp/plugins/bgutil-ytdlp-pot-provider
```

## Tests

```sh
make test               # smoke + unit suites
make lint               # shellcheck all scripts
```

The smoke suite stubs `yt-dlp`, `aria2c`, `ffmpeg`, `curl`, and `wl-paste`,
so it runs without network access or those tools installed. CI runs
ShellCheck plus both suites on every push to `main`.

## License

[MIT](LICENSE)
