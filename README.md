# vdl

[![CI](https://github.com/rathi/vdl/actions/workflows/ci.yml/badge.svg)](https://github.com/rathi/vdl/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

A portable smart downloader for Linux: direct files go through **aria2c** when
available, pages/playlists/streams go through **yt-dlp**, and either engine can
be used alone. It is a single Bash script with no runtime dependencies beyond
`yt-dlp` (and `bash`), so it behaves the same on any distribution.

## Requirements

| Tool | Needed for | Package hint |
|------|------------|--------------|
| `bash` >= 4 | always | base system |
| `yt-dlp` | pages, playlists, streams | distro package, pipx, or the standalone binary |
| `aria2c` | fast direct-file downloads (optional) | `aria2` |
| `ffmpeg` | `-a` audio extraction, merging | `ffmpeg` |
| `python-curl_cffi` | browser impersonation (optional, auto-detected) | `python-curl-cffi` / `python3-curl_cffi` |
| `wl-clipboard`, `xclip`, or `xsel` | clipboard URL pickup (optional) | `wl-clipboard`, `xclip`, `xsel` |

`vdl` checks what is available at run time: without `aria2c` it downloads
direct files with yt-dlp, and without `curl_cffi` it skips impersonation.

## Install

```sh
./install.sh                 # ~/.local/bin + completions for detected shells
./install.sh --shells bash,zsh,fish
./install.sh --system        # /usr/local (run with sudo)
./install.sh --no-completions
./install.sh --uninstall
```

If `~/.local/bin` is not on your `PATH`, the installer prints the line to add.
For zsh, the installer prints the `fpath` line needed before `compinit`.

## Usage

```sh
vdl                                     # URL from the clipboard
vdl "https://example.com/video"
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
vdl --max-speed 2M "https://example.com/file.iso"     # throttle overall
vdl --aria-opts "--check-interval=30" "https://example.com/file.iso"
vdl 'magnet:?xt=urn:btih:abc123'                      # torrent magnet
```

Run `vdl --help` for the full option list or `man vdl` for the man page.
Unknown options are forwarded to yt-dlp, so `-F`, `--playlist-start`,
`--download-archive`, and friends work.

Routing:

| URL looks like | Engine |
|----------------|--------|
| archive/package/document (`zip`, `iso`, `pdf`, `deb`, ...) | aria2c, 16 connections |
| magnet links, `.torrent` files | aria2c, 16 connections |
| plain video file (`mp4`, `mkv`, `webm`, ...) | aria2c (yt-dlp in `-a` mode) |
| HLS/DASH (`m3u8`, `mpd`) | yt-dlp native, 8 fragments |
| pages, playlists, everything else | yt-dlp + aria2c (10 connections) |

Naming:

- Single videos land flat in the save directory as
  `<title> [<id>].<ext>`.
- Playlist and album entries get a folder named after the playlist/album.
- `-a` writes MP3 files to `<save_dir>/audio` with the same flat/grouped
  layout.

## Environment

| Variable | Default | Meaning |
|----------|---------|---------|
| `VDL_SAVE_DIR` | `$(xdg-user-dir DOWNLOAD)/vdl` | exact download directory |
| `VDL_BROWSER` | auto-detect | default cookie source |
| `VDL_QUALITY` | `1080` | default max height |
| `VDL_TMP_KEEP_DAYS` | `7` | keep interrupted leftovers this long |
| `VDL_IMPERSONATE` | `auto` | `auto` (first target yt-dlp reports as available), `off`, or a target |
| `VDL_CONFIG` | `~/.config/vdl/yt-dlp.conf` | extra yt-dlp options, loaded if present |
| `VDL_CONFIG_DIR` | `~/.config/vdl` | directory for vdl's own config file |
| `NO_COLOR` | unset | disable colored output |

`VDL_CONFIG` is an ordinary yt-dlp config file; it is loaded *in addition* to
the defaults baked into `vdl`. Command-line flags still win over both.

`VDL_CONFIG_DIR` points to vdl's own configuration directory, which may contain
a `config` file — a simple `KEY=VALUE` file (comments with `#` are supported)
that sets defaults mirroring the `VDL_*` variables. It is read before
environment variables, so exported `VDL_*` vars still take precedence.

### vdl config file

```sh
# ~/.config/vdl/config
QUALITY=720
BROWSER=firefox
SAVE_DIR=~/Downloads/vdl
IMPERSONATE=chrome
TMP_KEEP_DAYS=7
```

Impersonation is probed with `yt-dlp --list-impersonate-targets`, so only
targets that yt-dlp actually supports on this machine are used. It only
applies to yt-dlp's own requests. When aria2c downloads a media file, it does
not impersonate a browser; on hosts that reject non-browser clients, retry
with `--no-aria`.

## YouTube HD formats (optional)

YouTube sometimes exposes only format `18` (360p) and warns that it is
"forcing SABR streaming". This is usually account- or client-specific, not a
vdl setting. A PO token provider restores the full format list.

1. Install the provider server (Deno 2 is required):

```sh
git clone --depth 1 --branch 2.0.2 \
  https://github.com/Brainicism/bgutil-ytdlp-pot-provider.git \
  ~/.local/share/bgutil-ytdlp-pot-provider
cd ~/.local/share/bgutil-ytdlp-pot-provider/server
deno install --allow-scripts=npm:canvas --frozen
```

2. Install the yt-dlp plugin from the matching release ZIP:

```sh
tmp=$(mktemp -d)
curl -fL -o "$tmp/plugin.zip" \
  https://github.com/Brainicism/bgutil-ytdlp-pot-provider/releases/download/2.0.2/bgutil-ytdlp-pot-provider.zip
mkdir -p ~/.config/yt-dlp/plugins/bgutil-ytdlp-pot-provider
unzip -q "$tmp/plugin.zip" -d ~/.config/yt-dlp/plugins/bgutil-ytdlp-pot-provider
rm -rf "$tmp"
```

If yt-dlp is installed with pip or pipx, `python3 -m pip install -U
bgutil-ytdlp-pot-provider` is an alternative to the ZIP.

3. Run the provider as a systemd user service (it listens on
   `127.0.0.1:4416`). Create
   `~/.config/systemd/user/bgutil-pot-provider.service`:

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

Rows up to `1920x1080` mean the provider is working. Resource cost is modest:
about 230 MB on disk (including development dependencies), roughly 100 MB of
idle RAM, and a short delay during format lookup; the media transfer itself is
not slowed down.

## What changed from the fish version

- One Bash script instead of a fish function, so it runs under bash, zsh, fish,
  and any other shell on any Linux system.
- The global `~/.config/yt-dlp/config` is no longer hijacked: `vdl` runs
  yt-dlp with `--ignore-config` and its own defaults, so plain `yt-dlp` stays
  untouched and `vdl` behaves identically on every machine.
- No hardcoded Vivaldi default or hardcoded home paths: the browser, download
  directory, clipboard tool, and optional binaries are detected at run time.
- `-q` now selects formats at or below the requested height instead of only
  preferring the closest resolution. If nothing qualifies, it falls back to
  the best available stream rather than failing.
- `--no-aria` (and a missing aria2c) routes direct files through yt-dlp, so
  cookie-protected direct links are still downloadable.
- Single items stay flat and playlist/album entries get their own folder. The
  old literal `NA/` directory is gone, and `-a` uses the same layout under
  `<save_dir>/audio`.
- `--version`, `NO_COLOR`, XDG paths, zsh/bash completions, and a man page
  were added.
- `--dry-run` previews the resolved plan (engine, mode, URLs) without
  downloading.
- `--download-dir`, `--quiet`, `--max-speed`, `--limit-speed`, and
  `--aria-opts` provide per-invocation overrides.
- Magnet links and `.torrent` files are recognised as direct downloads.
- A `~/.config/vdl/config` file provides KEY=VALUE defaults that mirror the
  `VDL_*` environment variables.
- When `aria2c` fails for a direct download, vdl automatically retries via
  yt-dlp.

## Layout

```
bin/vdl               the command
install.sh            installer / uninstaller
completions/          bash, zsh and fish completions
man/vdl.1             man page
test/smoke.sh         stub-based test suite (no network required)
Makefile              convenience targets (test, lint, install)
```

## Uninstall

```sh
./install.sh --uninstall
```

Use the same `--prefix` / `--system` flags you installed with, since those
determine where the files were placed.

If you previously used `~/.config/fish/functions/vdl.fish`, remove it:
fish functions take precedence over binaries on `PATH`, so the old function
would shadow the new command.

To remove the optional YouTube PO token provider as well:

```sh
systemctl --user disable --now bgutil-pot-provider.service
rm -f ~/.config/systemd/user/bgutil-pot-provider.service
rm -rf ~/.local/share/bgutil-ytdlp-pot-provider
rm -rf ~/.config/yt-dlp/plugins/bgutil-ytdlp-pot-provider
```

Remove the `youtube:player_client` line from `~/.config/vdl/yt-dlp.conf` if you
added it.

## Tests

```sh
make test               # or: bash test/smoke.sh
make lint               # shellcheck all scripts
```

The suite stubs `yt-dlp`, `aria2c`, `ffmpeg`, and `wl-paste`, so it runs
without network access or those tools installed.
