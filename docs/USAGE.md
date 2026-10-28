# vdl User Guide

`vdl` is a portable smart downloader for Linux. It picks the right engine for
each URL: direct files go through **aria2c** when it is available, while pages,
playlists, and streams go through **yt-dlp**. This guide covers installation,
setup, every feature with examples, and uninstallation.

See `README.md` for the project overview and `man vdl` for the option
reference.

---

## Requirements

| Tool | Needed for | Package hint |
|------|------------|--------------|
| `bash` >= 4 | always | base system |
| `yt-dlp` | pages, playlists, streams | distro package, pipx, or the standalone binary |
| `aria2c` | fast direct-file downloads (optional) | `aria2` |
| `ffmpeg` | `-a` audio extraction, merging | `ffmpeg` |
| `python-curl_cffi` | browser impersonation (optional, auto-detected) | `python-curl-cffi` |
| `wl-clipboard`, `xclip`, or `xsel` | clipboard URL pickup (optional) | `wl-clipboard`, `xclip`, `xsel` |

Everything optional is detected at run time; without `aria2c`, direct files are
downloaded with yt-dlp, and without `curl_cffi`, impersonation is skipped.

---

## Installation

Clone the repository and run the installer:

```sh
git clone https://github.com/rathi/vdl.git
cd vdl

./install.sh                     # ~/.local/bin + shell completions
./install.sh --shells bash,zsh   # limit completions to specific shells
./install.sh --no-completions    # command only
sudo ./install.sh --system       # /usr/local, system-wide
```

The installer places:

- `vdl` in `<prefix>/bin`
- the man page in `<prefix>/share/man/man1/vdl.1`
- completions for bash, zsh, and fish (auto-detected shells by default)

Make sure `~/.local/bin` is on your `PATH` (the installer prints the line to
add if it is not). For zsh, it also prints the `fpath` line needed before
`compinit`.

Verify the installation:

```sh
vdl --version
vdl --help
man vdl
```

### Alternative: manual install

Copy `bin/vdl` to any directory on your `PATH`:

```sh
install -Dm755 bin/vdl ~/.local/bin/vdl
install -Dm644 man/vdl.1 ~/.local/share/man/man1/vdl.1
```

Completions are optional; see `completions/` for `vdl.bash` (bash),
`_vdl` (zsh), and `vdl.fish` (fish).

---

## Setup

### Environment variables

| Variable | Default | Meaning |
|----------|---------|---------|
| `VDL_SAVE_DIR` | `$(xdg-user-dir DOWNLOAD)/vdl` | exact download directory |
| `VDL_BROWSER` | auto-detect | default cookie source |
| `VDL_QUALITY` | `1080` | default max video height |
| `VDL_TMP_KEEP_DAYS` | `7` | keep interrupted leftovers this long |
| `VDL_IMPERSONATE` | `auto` | `auto`, `off`, or a browser target |
| `VDL_CONFIG` | `~/.config/vdl/yt-dlp.conf` | extra yt-dlp config file |
| `VDL_CONFIG_DIR` | `~/.config/vdl` | directory for vdl's own config file |
| `NO_COLOR` | unset | disable colored output |

```sh
# in ~/.profile or ~/.bashrc
export VDL_SAVE_DIR="$HOME/Downloads/vdl"
export VDL_BROWSER=firefox
export VDL_QUALITY=720
```

### vdl config file

`$VDL_CONFIG_DIR/config` (default `~/.config/vdl/config`) is a simple
`KEY=VALUE` file that sets defaults mirroring the `VDL_*` variables.
Command-line flags and exported environment variables take precedence.

```sh
# ~/.config/vdl/config
QUALITY=720
BROWSER=firefox
SAVE_DIR=~/Downloads/vdl
IMPERSONATE=chrome
TMP_KEEP_DAYS=7
```

### Extra yt-dlp options

`VDL_CONFIG` points to an ordinary yt-dlp config file (default
`~/.config/vdl/yt-dlp.conf`). It is loaded **in addition** to the defaults
baked into vdl, and CLI flags still win over both:

```
# ~/.config/vdl/yt-dlp.conf
--extractor-args "youtube:player_client=web_safari"
```

---

## Usage

```sh
vdl [options] <url> | <links.txt>
vdl [options]                          # no URL: takes the link from the clipboard
```

### Basic downloads

```sh
vdl "https://example.com/video"        # single URL
vdl "https://example.com/video" "https://example.com/file.zip"   # mixed input
vdl                                    # URL from the clipboard
vdl www.example.com/video              # "www." is normalized to https://
```

Any number of URLs can be given in one run. vdl classifies each one and uses
aria2c for direct files and yt-dlp for everything else, all in the same
invocation. Duplicate URLs are removed while preserving order.

### Batch files

```sh
vdl links.txt                          # one URL per line
vdl -i more.txt links.txt              # repeatable --batch-file
```

Only lines starting with `http://` or `https://` are used; blank lines and
comments are ignored.

### Quality and format

```sh
vdl -q 720 "https://example.com/video" # formats at or below 720p
vdl -q 2k  "https://example.com/video" # 1440p
vdl -q 4k  "https://example.com/video" # 2160p
```

The default is 1080p. If nothing matches, vdl falls back to the best
available stream instead of failing.

### Audio extraction

```sh
vdl -a "https://example.com/album"     # MP3 320k
```

Downloads the best audio and converts it to MP3 320k with metadata and
thumbnail embedding. Files land in `<save_dir>/audio`.

### Browser cookies

```sh
vdl -b firefox "https://example.com"
vdl -b firefox:work "https://example.com"   # specific profile
vdl -n "https://example.com/file.iso"       # no cookies at all
```

The browser is auto-detected when `-b` is not given. Supported browsers:
`vivaldi`, `firefox`, `brave`, `chromium`, `chrome`, `edge`, `opera`,
`safari`, `whale`, or `none`.

Cookies apply to yt-dlp requests. Direct aria2c downloads do not receive
browser cookies; use `--no-aria` for cookie-protected direct links.

### TLS impersonation

```sh
vdl --no-impersonate "https://example.com/video"   # disable
VDL_IMPERSONATE=chrome vdl "https://example.com"   # force a target
```

By default vdl probes `yt-dlp --list-impersonate-targets` and uses the first
supported target (`chrome`, `firefox`, or `safari`). If none is available it
continues without impersonation.

### Headers and proxy

```sh
vdl --referer "https://example.com/page" "https://example.com/file.iso"
vdl --user-agent "Mozilla/5.0 ..." "https://example.com/file.iso"
vdl --proxy "http://127.0.0.1:8080" "https://example.com/video"
```

These are forwarded to whichever engine handles the URL.

### Direct files and routing

| URL looks like | Engine |
|----------------|--------|
| archive/package/document (`zip`, `iso`, `pdf`, `deb`, ...) | aria2c, 16 connections |
| magnet links, `.torrent` files | aria2c, 16 connections |
| plain video file (`mp4`, `mkv`, `webm`, ...) | aria2c (yt-dlp in `-a` mode) |
| HLS/DASH (`m3u8`, `mpd`) | yt-dlp native, 8 fragments |
| pages, playlists, everything else | yt-dlp + aria2c (10 connections) |

Force everything through yt-dlp:

```sh
vdl --no-aria "https://example.com/file.iso"
```

Direct downloads resume interrupted transfers and use multiple connections
per file.

### Magnet links and torrents

```sh
vdl 'magnet:?xt=urn:btih:abc123'
vdl 'https://example.com/file.torrent'
```

Torrent payloads are only fetched by aria2c. If aria2c fails, magnet/torrent
downloads are reported as failed rather than retried with yt-dlp.

### Speed limits

```sh
vdl --max-speed 2M "https://example.com/file.iso"    # overall limit
vdl --limit-speed 500K "https://example.com/file.iso" # per-download limit
vdl --limit-speed 1.5M "https://example.com/video"   # decimals allowed
```

Rates accept a byte count with an optional case-insensitive `K`, `M`, or `G`
suffix (1024-based). A bare number means bytes per second, and `0` means
unlimited. Fractional values require a suffix. Invalid values are rejected
before any download starts.

- `--max-speed` maps to aria2c's overall limit and yt-dlp's `--limit-rate`.
- `--limit-speed` maps to aria2c's per-download limit.
- When both are set, yt-dlp (which has one limit) receives the stricter
  non-zero value.

### Save location

```sh
vdl --download-dir ~/tmp "https://example.com/file.zip"   # one-off override
VDL_SAVE_DIR=~/media vdl "https://example.com/video"      # or set the variable
```

Naming:

- Single videos land flat in the save directory as `<title> [<id>].<ext>`.
- Playlist and album entries get a folder named after the playlist/album.
- `-a` writes MP3 files to `<save_dir>/audio` with the same layout.

### yt-dlp passthrough options

Unknown options are forwarded to yt-dlp in their original order, with values
attached, so any yt-dlp option works:

```sh
vdl -F "https://example.com/video"                      # list formats
vdl --playlist-start 3 "https://example.com/playlist"
vdl --download-archive seen.txt "https://example.com/video"
vdl -f "bestvideo+bestaudio" --merge-output-format mkv \
    "https://example.com/video"
```

These options take effect on yt-dlp paths; a pure aria2c direct download does
not interpret yt-dlp-only flags.

### aria2c tuning

```sh
vdl --aria-opts "--max-connection-per-server=8" "https://example.com/file.iso"
vdl --aria-opts "--check-interval=30" "https://example.com/file.iso"
```

Extra options are forwarded to aria2c verbatim.

### Preview and quiet mode

```sh
vdl --dry-run "https://example.com/file.iso"   # print the plan, download nothing
vdl --quiet "https://example.com/video"        # no banner, status, or summary
```

`--dry-run` shows the resolved engine, mode, URLs, save directory, and
impersonation target without invoking any downloader.

### Automatic recovery

If aria2c exits with an error during direct downloads, vdl does not
re-download everything:

1. A file with an `.aria2` control file is treated as interrupted — the
   partial file and its control file are removed.
2. Missing files are retried.
3. Completed files are left untouched.

Only the incomplete HTTP(S) URLs are retried, via yt-dlp with the same save
directory, cookies, headers, proxy, impersonation, and passthrough options.
Magnet/torrent downloads are not retried this way. If nothing is retryable,
vdl exits with aria2c's status.

### Removing duplicate downloads

Some sites list the same video more than once per playlist, so yt-dlp
downloads identical files under different names. `--dedupe` cleans that up
after the run:

```sh
vdl --dedupe "https://www.erome.com/a/..."
```

After downloading, vdl compares the files created during that run — first by
size, then by full content hash — and removes duplicates, always keeping the
oldest copy. Files that existed before the run and files in `<save_dir>/.tmp`
are never touched. The flag is off by default, so other downloads are
unaffected.

### Terminal output

A normal run shows:

```
===============================================
  vdl 2.0.0  —  smart downloader
-----------------------------------------------
  Engine:   hybrid (aria2c + yt-dlp)
  Mode:     video (max 1080p, MP4 preferred)
  URLs:     3 (2 direct, 1 media)
  Save dir: ~/Downloads/vdl
===============================================

--- Direct downloads via aria2c ---
  • file.iso
  [ok]   file.iso

--- Summary ---
  Total:    1
  Direct:   1 ok, 0 failed
  Time:     4s
  Save dir: ~/Downloads/vdl
  [ok]   all downloads finished
```

yt-dlp downloads show a live bar that updates in place:

```
[#########-----------] 43.3% 149.63KiB/s | ETA 00:01
```

aria2c keeps its native per-file progress line. `NO_COLOR=1` or a non-TTY
disables colors; `--quiet` suppresses all of vdl's own output.

---

## Uninstallation

Use the same options you installed with:

```sh
./install.sh --uninstall               # user-level install
sudo ./install.sh --system --uninstall # system-wide install
```

This removes `vdl`, the man page, and the completions it placed. To clean up
leftovers:

```sh
rm -rf ~/.config/vdl                  # vdl config and yt-dlp.conf
```

If you previously used the old fish function version, remove it as well —
fish functions take precedence over binaries on `PATH`:

```sh
rm -f ~/.config/fish/functions/vdl.fish
```

If you installed the optional YouTube PO token provider, remove it with:

```sh
systemctl --user disable --now bgutil-pot-provider.service
rm -f ~/.config/systemd/user/bgutil-pot-provider.service
rm -rf ~/.local/share/bgutil-ytdlp-pot-provider
rm -rf ~/.config/yt-dlp/plugins/bgutil-ytdlp-pot-provider
```
