# vdl for Termux

[![CI](https://github.com/RathiRayhan/vdl/actions/workflows/ci.yml/badge.svg)](https://github.com/RathiRayhan/vdl/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Platform: Termux](https://img.shields.io/badge/platform-Termux-3DDC84)](https://termux.dev/)

A fast, resumable command-line downloader for Android, built for
[Termux](https://termux.dev/). `vdl` routes every URL to the right engine
automatically:

- **Direct files** — archives, disk images, documents, packages, plain video
  files, magnet links, and `.torrent` files — go through **aria2c** with
  multiple connections and resume support.
- **Media** — YouTube and other supported sites, playlists, HLS, and DASH —
  go through **yt-dlp** with quality limits, MP3 extraction, metadata, and MP4
  merging.
- **Mixed input** is handled in one command. Direct files and media URLs are
  split automatically and downloaded with their respective engines.

`vdl` is pure Bash. There is no compiled component to build, no daemon, and no
root requirement for normal use. Everything runs inside Termux and saves to
Android shared storage when it is available.

> This branch is dedicated to the Termux/Android experience. The Linux-focused
> documentation lives on the `main` branch.

---

## Contents

- [Why vdl on Termux](#why-vdl-on-termux)
- [Features](#features)
- [Requirements](#requirements)
- [Installation](#installation)
- [Quick start](#quick-start)
- [Storage and file visibility](#storage-and-file-visibility)
- [YouTube and JavaScript runtimes](#youtube-and-javascript-runtimes)
- [Cookies](#cookies)
- [Background downloads](#background-downloads)
- [TLS impersonation](#tls-impersonation)
- [Common options](#common-options)
- [Configuration](#configuration)
- [Advanced usage](#advanced-usage)
- [Troubleshooting](#troubleshooting)
- [Termux limitations](#termux-limitations)
- [Development](#development)
- [Uninstall](#uninstall)
- [License](#license)

---

## Why vdl on Termux

Android download managers are often limited to browser downloads, lack resume
support, or cannot handle playlists and streams. `vdl` gives Termux a desktop
class download pipeline:

- One command for direct files, torrents, videos, and audio.
- Multiple connections per direct file with automatic resume.
- yt-dlp for sites that require extractors, cookies, or stream handling.
- Decisions made per URL, so mixed link lists work in one run.
- Output that is usable in a terminal: a plan, per-URL status, a live progress
  bar, and a final summary.

Termux-specific setup is mostly shared storage plus, optionally, the
Termux:API app for a wake lock.

## Features

- **Smart routing** — aria2c for files and torrents, yt-dlp for pages,
  playlists, and streams; one invocation can use both.
- **Resumable transfers** — interrupted direct files continue from where they
  stopped; yt-dlp keeps its own partial state under `<save_dir>/.tmp`.  If
  yt-dlp is unavailable, aria2c partials are kept for a later resume and stale
  leftovers are swept after `VDL_TMP_KEEP_DAYS`.
- **Quality control** — default 1080p cap, with `720`, `2k`, `4k`, and `8k`
  aliases.
- **Audio extraction** — `-a` downloads the best audio and converts it to MP3
  320k under `<save_dir>/audio`.
- **Custom destinations** — `--name` names a single file/video or playlist
  folder; `--output` pins a single URL to an exact file path or folder.
- **Zip archiving** — `--zip[=NAME.zip]` packs everything downloaded in the
  run into one archive after dedupe.
- **Multi-line paste** — paste a block of URLs as one argument; vdl splits it
  into one URL per line and ignores blank/non-URL lines.
- **Playlist and album support** — entries are grouped into folders with
  predictable names.
- **Cookie support** — manual Netscape `cookies.txt` files with `--cookies`;
  root-only Firefox for Android import with `--root-cookies`.
- **TLS impersonation** — optional `curl_cffi` support for sites that reject
  normal clients; automatically skipped when unavailable.
- **Bandwidth controls** — overall and per-download limits with `K`/`M`/`G`
  suffixes.
- **Headers and proxies** — custom Referer, User-Agent, and proxy support.
- **Embedded images** — opt-in scanning of generic album pages with
  `--images`; a Python HTML parser handles multi-line tags, entities, and
  real-world gallery markup, with a regex fallback when python3 is absent.
- **Duplicate cleanup** — opt-in `--dedupe` keeps the oldest copy of
  byte-identical files from the same run.
- **Batch input** — read URLs from text files with `-i` or a bare `.txt`
  argument.
- **yt-dlp passthrough** — unknown options are forwarded in order with their
  values, so advanced yt-dlp flags still work.
- **Safe recovery** — a failed aria2c run retries only incomplete HTTP(S)
  files through yt-dlp.
- **Termux aware** — shared-storage defaults, automatic wake lock, and a
  dedicated installer mode.
- **Run progress and failure recap** — a `Run n/m` counter after each phase,
  `✓`/`✗` result glyphs, and a `Failed` summary with per-URL reasons.
- **Preview mode** — `--dry-run` shows the resolved plan without downloading.
- **Quiet mode** — `--quiet` suppresses banners, status lines, and progress.

## Requirements

### Core

| Component | Purpose | Termux package |
|---|---|---|
| Bash 4+ | runs vdl | `bash` |
| yt-dlp | pages, playlists, streams | `python-yt-dlp` |

### YouTube support

| Component | Purpose | Termux package |
|---|---|---|
| yt-dlp-ejs | YouTube JavaScript challenge scripts | `yt-dlp-ejs` |
| JavaScript runtime | solves YouTube challenges | `deno` (64-bit) or `nodejs` (32-bit) |

### Recommended

| Component | Purpose | Termux package |
|---|---|---|
| aria2c | fast direct downloads, torrents | `aria2` |
| ffmpeg | MP3 extraction, merging, metadata | `ffmpeg` |
| curl | embedded-image scanning | `curl` |
| python3 | HTML parser for `--images` (optional; regex fallback) | `python` |
| zip | `--zip` archiving | `zip` |
| Termux:API app | wake lock | `termux-api` + Termux:API app |
| Python pip | optional `curl_cffi` install | `python-pip` |

`vdl` checks available tools at run time:

- Without `aria2c`, direct files are downloaded by yt-dlp instead.
- Without `ffmpeg`, media downloads still work but audio extraction and merging
  do not.
- Without `curl_cffi`, TLS impersonation is skipped.
- Without the Termux:API app, the wake lock is skipped.

## Installation

### 1. Install Termux packages

Use Termux from [F-Droid](https://f-droid.org/packages/com.termux/) or the
official Termux GitHub releases. Install the core toolchain:

```sh
pkg update
pkg install git bash coreutils findutils gawk grep sed curl zip \
    aria2 python ffmpeg termux-api
```

Install yt-dlp and its YouTube challenge support:

```sh
pkg install python-yt-dlp yt-dlp-ejs
pkg install deno                 # 64-bit ARM/x86_64
# pkg install nodejs             # 32-bit devices instead of deno
```

Optional, for TLS impersonation on supported devices:

```sh
pkg install python-pip
pip install -U curl-cffi
```

Optional, for the wake lock and media scanning, install the **Termux:API**
app from F-Droid in addition to the `termux-api` package.

### 2. Grant storage access

```sh
termux-setup-storage
```

Approve the Android permission prompt. On Android 11 and newer, some devices
also require **All files access** for Termux in Android Settings.

### 3. Install vdl

```sh
git clone https://github.com/RathiRayhan/vdl.git
cd vdl
git checkout termux
./install.sh --termux
```

`--termux` installs the command, libraries, man page, and shell completions
under `$PREFIX` (normally `/data/data/com.termux/files/usr`). Running
`./install.sh` inside Termux also auto-detects the environment.

Verify:

```sh
vdl --version
vdl --help
```

The installer also places a man page. If `man` is not installed, use
Termux's mandoc package:

```sh
pkg install mandoc
man vdl
```

If the shell cannot find `vdl`, open a new Termux session or run:

```sh
hash -r
```

The command is installed in `$PREFIX/bin`, which is already on Termux's
`PATH`.

### 4. 32-bit devices

Deno is not available for 32-bit Termux. Use Node instead and tell vdl's
yt-dlp config about it:

```sh
pkg install nodejs
mkdir -p ~/.config/vdl
printf '%s\n' '--js-runtimes node' >> ~/.config/vdl/yt-dlp.conf
```

### Updating

```sh
cd vdl
git pull
./install.sh --termux
pkg upgrade
```

`pkg upgrade` keeps yt-dlp, aria2, ffmpeg, and the JavaScript runtime current.
If yt-dlp is installed outside Termux packages, update it with its own
installer.

## Quick start

```sh
# A video or page
vdl "https://youtu.be/VIDEO_ID"

# A direct file (ISO, ZIP, PDF, APK, ...)
vdl "https://example.com/file.iso"

# Audio only, MP3 320k
vdl -a "https://example.com/album"

# A playlist at 720p
vdl -q 720 "https://example.com/playlist"

# A text file with one URL per line
vdl links.txt

# A custom filename
vdl --name my-archive "https://example.com/file.zip"

# An exact destination (single URL)
vdl --output ~/storage/downloads/movies/movie.mp4 "https://example.com/video"

# Paste several URLs at once
vdl 'https://example.com/one
https://example.com/two'

# Archive this run's downloads
vdl --zip=my-batch.zip links.txt

# Preview routing and options without downloading
vdl --dry-run "https://example.com/file.iso"
```

By default, files are saved under:

```text
~/storage/downloads/vdl
```

If `termux-setup-storage` has not been run, vdl falls back to
`~/Downloads/vdl` inside Termux's private home and prints a setup hint.

## Storage and file visibility

Termux has two kinds of storage:

| Location | Visible to Android apps | Notes |
|---|---|---|
| `~/storage/downloads` | Yes | Shared Downloads folder; recommended |
| `~/Downloads` | No | Private to Termux; removed with the app |

`termux-setup-storage` creates `~/storage/downloads`, normally a link to
`/storage/emulated/0/Download`. vdl uses `~/storage/downloads/vdl` when that
directory exists.

Override the location for one run:

```sh
vdl --download-dir ~/storage/downloads/videos "https://example.com/video"
```

Or permanently:

```sh
# ~/.config/vdl/config
SAVE_DIR=~/storage/downloads/vdl
```

If a downloaded file does not appear in the gallery or file manager, install
the Termux:API app and run Android's media scanner:

```sh
termux-media-scan -r ~/storage/downloads/vdl
```

### External SD cards

FAT/exFAT SD cards cannot store files larger than 4 GB and reject some
filename characters. Use internal shared storage for large media. If a card
rejects a yt-dlp filename, pass:

```sh
vdl --windows-filenames "https://example.com/video"
```

## YouTube and JavaScript runtimes

Modern YouTube extraction requires a JavaScript runtime and yt-dlp's EJS
scripts. Install both:

```sh
pkg install yt-dlp-ejs deno
```

On 32-bit devices use Node:

```sh
pkg install yt-dlp-ejs nodejs
mkdir -p ~/.config/vdl
printf '%s\n' '--js-runtimes node' >> ~/.config/vdl/yt-dlp.conf
```

vdl runs yt-dlp with `--ignore-config`, so Termux's system-wide yt-dlp config
is intentionally ignored. vdl's own extra config is still loaded from
`~/.config/vdl/yt-dlp.conf`.

If YouTube offers only 360p:

1. Update packages: `pkg upgrade`.
2. Confirm `deno --version` (or `node --version`) works and that
   `yt-dlp-ejs` is installed.
3. Check available formats:

   ```sh
   vdl -F "https://youtu.be/VIDEO_ID"
   ```

4. Try a different YouTube client through passthrough:

   ```sh
   vdl --extractor-args "youtube:player_client=web_safari" "https://youtu.be/VIDEO_ID"
   ```

Some accounts and networks require a PO token provider. That is an external
yt-dlp component, not part of vdl; see the
[yt-dlp PO Token Guide](https://github.com/yt-dlp/yt-dlp/wiki/PO-Token-Guide).

## Cookies

Cookies apply to yt-dlp requests, including media pages and direct-file
fallback downloads. They do not apply to aria2c, so use `--no-aria` for a
cookie-protected direct link.

### Non-root: manual cookies.txt

Termux cannot read Android browser profiles because they are app-private.
Export a Netscape-format `cookies.txt` from a browser or another machine, then
pass it explicitly:

```sh
vdl --cookies ~/storage/downloads/cookies.txt "https://example.com/video"
```

Or configure it permanently:

```sh
# ~/.config/vdl/config
COOKIES=~/storage/downloads/cookies.txt
```

Environment variable:

```sh
export VDL_COOKIES=~/storage/downloads/cookies.txt
```

Disable cookies entirely with `-n` or `--no-cookies`.

### Root: Firefox for Android cookies

On a rooted device, vdl can import **Firefox for Android** cookies with `su`:

```sh
vdl --root-cookies "https://example.com/video"
```

This copies Firefox's plaintext `cookies.sqlite` into:

```text
~/.cache/vdl/root-cookies/firefox
```

The directory is owner-only. Close Firefox before running so the database is
not mid-write. Stable, beta, and nightly Firefox packages are supported.

On a secondary Android user:

```sh
VDL_TERMUX_FIREFOX_ROOT=/data/user/10 vdl --root-cookies "https://example.com/video"
```

### Why Chrome cookies are not supported with root

Chrome, Chromium, Brave, Edge, and other Chromium-based Android browsers
encrypt cookie values with a key held by the Android Keystore. Root can read
the database file, but yt-dlp cannot decrypt the values. Root therefore does
not make `-b chrome` work.

For those browsers, export `cookies.txt` and use `--cookies`.

### Explicit browser profile

If you copy a Firefox profile into Termux-accessible storage, you can point
yt-dlp at it directly:

```sh
vdl -b firefox:/path/to/profile "https://example.com/video"
```

Automatic browser detection is disabled on Termux, so `-b firefox` without a
profile path is not useful.

## Background downloads

Android may suspend or kill Termux when the screen turns off. When the
Termux:API app is installed, vdl automatically holds a wake lock for the run
and releases it on exit or Ctrl+C.

Disable it with:

```sh
VDL_WAKELOCK=0 vdl "https://example.com/video"
```

For long jobs:

- Disable battery optimization for Termux in Android Settings.
- Keep the device on a charger for large merges.
- Use `tmux` inside Termux so closing the terminal does not end the session.
- Reduce aria2c connections on weak or metered networks:

  ```sh
  vdl --aria-opts "-x 4 -s 4" "https://example.com/file.iso"
  ```

Android 12+ task killers and the phantom-process killer can still interrupt
long child processes even with a wake lock. If that happens, run the download
inside `tmux` and keep Termux exempt from battery optimization.

## TLS impersonation

Some sites reject clients based on TLS fingerprints. vdl can ask yt-dlp to
impersonate a browser when `curl_cffi` is available:

```sh
pkg install python-pip
pip install -U curl-cffi
yt-dlp --list-impersonate-targets
```

`curl_cffi` publishes Android arm64 wheels for current Python versions. On
64-bit ARM phones it may work out of the box; on 32-bit ARM and x86_64 Termux
there may be no compatible wheel. vdl silently skips impersonation when yt-dlp
reports no available target.

Control it with:

```sh
vdl --no-impersonate "https://example.com/video"
VDL_IMPERSONATE=chrome vdl "https://example.com/video"
VDL_IMPERSONATE=off vdl "https://example.com/video"
```

Impersonation applies to yt-dlp requests. aria2c media transfers do not
impersonate; retry with `--no-aria` if a host rejects aria2c.

## Common options

Run `vdl --help` for the complete list. The most useful options on Termux:

| Option | Meaning |
|---|---|
| `-q, --quality HEIGHT` | Maximum video height; `720`, `1080`, `2k`, `4k`, `8k` |
| `-a, --audio` | Best audio, converted to MP3 320k |
| `-n, --no-cookies` | Do not use cookies |
| `-i, --batch-file FILE` | Read URLs from a file |
| `-b, --browser NAME` | Browser cookie source or explicit profile |
| `--cookies FILE` | Netscape cookies.txt file |
| `--root-cookies` | Import Firefox Android cookies via root |
| `--download-dir DIR` | Override the save directory |
| `--name NAME` | Custom filename, or playlist folder name |
| `--output PATH` | Exact file path or folder for a single URL |
| `--zip[=NAME.zip]` | Archive this run's downloads |
| `--no-aria` | Send direct files through yt-dlp |
| `--no-impersonate` | Disable TLS impersonation |
| `--images` | Download images embedded in album pages |
| `--dedupe` | Remove duplicate files downloaded in this run |
| `--max-speed RATE` | Overall speed limit |
| `--limit-speed RATE` | Per-download speed limit |
| `--referer URL` | Custom Referer header |
| `--user-agent UA` | Custom User-Agent header |
| `--proxy URL` | Proxy for downloads |
| `--aria-opts OPTS` | Extra aria2c options |
| `--dry-run` | Show the plan without downloading |
| `--quiet` | Suppress vdl output |

Any unknown option is forwarded to yt-dlp with its value in order. This makes
advanced flags available without vdl reimplementing them:

```sh
vdl -F "https://example.com/video"
vdl --playlist-start 3 "https://example.com/playlist"
vdl --download-archive seen.txt "https://example.com/video"
vdl -f "bestvideo+bestaudio" --merge-output-format mkv "https://example.com/video"
```

## Configuration

### Environment variables

| Variable | Default | Meaning |
|---|---|---|
| `VDL_SAVE_DIR` | `~/storage/downloads/vdl` | download directory |
| `VDL_BROWSER` | auto-detect | default cookie source; auto-detection is disabled on Termux |
| `VDL_QUALITY` | `1080` | default maximum height |
| `VDL_COOKIES` | unset | Netscape cookies.txt file |
| `VDL_ROOT_COOKIES` | unset | `1` or `firefox` to import Firefox Android cookies via root |
| `VDL_WAKELOCK` | `1` | `0` disables the Termux wake lock |
| `VDL_IMPERSONATE` | `auto` | `auto`, `off`, or a target name |
| `VDL_IMAGES` | unset | `1` or `yes` scans album pages for images |
| `VDL_TMP_KEEP_DAYS` | `7` | days to keep interrupted leftovers |
| `VDL_CONFIG` | `~/.config/vdl/yt-dlp.conf` | extra yt-dlp config file |
| `VDL_CONFIG_DIR` | `~/.config/vdl` | vdl config directory |
| `NO_COLOR` | unset | disable colored output |

### vdl config file

`~/.config/vdl/config` is a simple `KEY=VALUE` file. Comments start with `#`.

```sh
# ~/.config/vdl/config
QUALITY=720
SAVE_DIR=~/storage/downloads/vdl
COOKIES=~/storage/downloads/cookies.txt
WAKELOCK=1
IMAGES=1
```

Command-line flags take precedence over exported environment variables, which
take precedence over this file.

### Extra yt-dlp options

`VDL_CONFIG` points to a regular yt-dlp config file:

```sh
# ~/.config/vdl/yt-dlp.conf
--js-runtimes node
--extractor-args "youtube:player_client=web_safari"
```

This file is loaded *in addition* to vdl's built-in defaults. yt-dlp's global
config is still ignored.

## Advanced usage

### Routing

| URL type | Engine |
|---|---|
| `magnet:`, `.torrent` | aria2c |
| `.zip`, `.iso`, `.pdf`, `.apk`, `.deb`, `.tar.gz`, images, ... | aria2c |
| Plain `.mp4`, `.mkv`, `.webm`, `.avi`, `.mov`, `.flv` | aria2c in video mode |
| HLS/DASH (`.m3u8`, `.mpd`) | yt-dlp native |
| Pages, playlists, streams, everything else | yt-dlp + aria2c where possible |

Use `--no-aria` to force all direct files through yt-dlp.

### Custom filenames

```sh
vdl --name my-rom "https://example.com/file.iso"       # -> my-rom.iso
vdl --name "episode 1" "https://example.com/video"     # -> episode 1.<ext>
vdl --name custom.mp4 "https://example.com/video"      # -> custom.mp4
```

For a playlist URL, the name becomes the folder:

```sh
vdl --name my-album "https://example.com/playlist"
```

`--name` requires exactly one input URL.

### Exact destination

`--output` pins a single URL to an exact file path or folder:

```sh
vdl --output ~/storage/downloads/movies/movie.mp4 "https://example.com/video"
vdl --output ~/storage/downloads/season1 "https://example.com/playlist"
```

A path whose final component has an extension is the exact file; anything
else is the exact folder. Playlist items go directly inside the folder with
no title-named subfolder. `--output` requires one URL and cannot be combined
with `--name`.

### Zip archive

After a multi-URL or batch run, pack everything downloaded in that run into
one zip:

```sh
vdl --zip url1 url2 url3            # -> vdl-YYYYMMDD-HHMMSS.zip
vdl --zip=my-batch.zip links.txt    # explicit name
```

`--zip` runs after `--dedupe`, includes playlist folders, and only includes
files downloaded in the current run. The `zip` package is required; without
it vdl warns and leaves the files in place.

### Multi-line paste

A pasted block of URLs can be passed as one argument:

```sh
vdl 'https://example.com/one
https://example.com/two'
```

URL lines become downloads, `.txt` lines that exist become batch files, and
blank or non-URL lines are ignored. Flags apply to every URL in the block.

### Audio

```sh
vdl -a "https://example.com/album"
```

Files go to `<save_dir>/audio` as MP3 320k with metadata and thumbnail
embedding. ffmpeg is required.

### Embedded images

```sh
vdl --images "https://example.com/album/123"
```

For generic or HTML5 album pages, vdl scans for `<img>` links and downloads
them into the album folder. Videos download first; the page scan and image
downloads run afterward, so media always finishes before photos. Known-site
extractors such as YouTube are not scanned. This is opt-in because it adds
page requests. It comes in handy for photo galleries, manga chapters,
product photos, and teardown guides — anywhere a site serves its images as
plain HTML.

### Duplicate cleanup

```sh
vdl --dedupe "https://example.com/album"
```

After the run, files created by that run are compared by size and SHA-256.
Identical copies are removed, keeping the oldest. Files that existed before
the run are never touched. Hashing large files over Android shared storage is
slow and uses battery.

### Torrents and magnets

```sh
vdl 'magnet:?xt=urn:btih:...'
vdl 'https://example.com/file.torrent'
```

Torrents require aria2c. They are not retried through yt-dlp. Background
seeding, incoming peers, and long-running torrents may be unreliable on
Android and mobile networks.

### Speed limits

```sh
vdl --max-speed 2M "https://example.com/file.iso"
vdl --limit-speed 500K "https://example.com/video"
```

Rates accept `K`, `M`, or `G` suffixes (1024-based). `0` means unlimited.
`--max-speed` maps to aria2c's overall limit; `--limit-speed` maps to
aria2c's per-download limit. yt-dlp has one rate limit, so it receives the
stricter non-zero value when both flags are set.

### Batch files

```sh
vdl links.txt
vdl -i more-links.txt links.txt
```

Only lines beginning with `http://` or `https://` are read. Blank lines and
comments are ignored.

### Share links from Android

Termux can receive links through Android's share sheet. Create a URL handler:

```sh
mkdir -p ~/.termux
cat > ~/.termux/termux-url-opener <<'EOF'
#!/data/data/com.termux/files/usr/bin/bash
exec vdl "$1"
EOF
chmod +x ~/.termux/termux-url-opener
```

After that, sharing a URL to Termux starts vdl in a new terminal session.

### Preview and quiet mode

```sh
vdl --dry-run "https://example.com/file.iso"
vdl --quiet "https://example.com/video"
```

`--dry-run` resolves routing, quality, cookies, and impersonation without
downloading.

### Run progress and output

After each phase, vdl prints a batch-level progress line:

```text
  Run  2/3 · 1 failed
```

Failed downloads are recapped in the summary with their reason:

```text
  Failed
  ✗  https://example.com/video — yt-dlp exit 1
```

The yt-dlp bar adapts to the terminal width; aria2c keeps its native
per-file progress line. `--quiet` suppresses all of vdl's own output.

### Interrupting and resuming

Press `Ctrl+C`. Completed files stay in place. An in-flight yt-dlp download
remains under `<save_dir>/.tmp`; aria2c keeps its partial file and `.aria2`
control file in the save directory. Run the same command again to resume.
Aria2c leftovers older than `VDL_TMP_KEEP_DAYS` are swept on exit; if yt-dlp
is unavailable, the partial is kept so a later aria2c run can resume it.

## Troubleshooting

### `vdl: command not found`

```sh
hash -r
# or open a new Termux session
command -v vdl
```

`vdl` installs to `$PREFIX/bin`, which is already on Termux's `PATH`. If you
installed with a custom `--prefix`, add that directory to `PATH`.

### Downloads are not visible in Gallery or Files

You are probably saving to private Termux storage. Run:

```sh
termux-setup-storage
ls -ld ~/storage/downloads
export VDL_SAVE_DIR=~/storage/downloads/vdl
```

Then trigger a media scan:

```sh
termux-media-scan -r ~/storage/downloads/vdl
```

### `Permission denied` when creating the save directory

Grant storage access again with `termux-setup-storage`, and on Android 11+
enable **All files access** for Termux in Android Settings. Also check free
space with `df -h ~/storage/downloads`.

### YouTube only shows 360p

Install `yt-dlp-ejs` and a JavaScript runtime:

```sh
pkg install yt-dlp-ejs deno
pkg upgrade
vdl -F "https://youtu.be/VIDEO_ID"
```

On 32-bit use Node and add `--js-runtimes node` to
`~/.config/vdl/yt-dlp.conf`. If formats are still missing, the site may
require a PO token provider; see the yt-dlp guide linked above.

### Cookies are rejected or ignored

- Confirm the file is in Netscape `cookies.txt` format.
- Check the file is readable: `head -n 3 cookies.txt`.
- Use `--cookies` explicitly.
- For a cookie-protected direct file, add `--no-aria`.
- Chrome/Chromium cookies cannot be imported with root; export them instead.

### `--root-cookies` fails

- Confirm the device is rooted and `su` works from Termux.
- Install Firefox for Android and close it before importing.
- Grant the root manager permission for Termux.
- Remember that Chrome, Chromium, Brave, and Edge are not supported.
- Check the error output; vdl never runs `su` unless you pass `--root-cookies`
  or set `VDL_ROOT_COOKIES`.

### `curl_cffi` will not install

`curl_cffi` Android wheels are architecture-specific and may not exist for
32-bit ARM or x86_64 Termux. vdl continues without impersonation. Do not force
a source build unless you know your device's toolchain supports it.

### Termux is killed during a long download

- Install the Termux:API app.
- Keep the wake lock enabled.
- Disable battery optimization for Termux.
- Use `tmux`.
- On Android 12+, check the phantom-process-killer settings.
- Reduce connections and run large jobs on a charger.

### Merge or MP3 conversion fails

Install ffmpeg:

```sh
pkg install ffmpeg
```

Large 4K merges are CPU-heavy and can take a long time on a phone. Use a
lower quality cap when possible:

```sh
vdl -q 1080 "https://example.com/video"
```

### External SD card errors

FAT/exFAT cards cannot store files larger than 4 GB and may reject characters
such as `:`, `?`, `*`, `<`, `>`, or `|`. Use internal storage, or pass
`--windows-filenames` for yt-dlp names.

### `--zip` says zip is missing

```sh
pkg install zip
```

### `--output` rejects the command

`--output` works with exactly one URL and cannot be combined with `--name`.
Use `--name` for a custom filename or `--download-dir` for a batch folder.

## Termux limitations

- **No Android GUI.** This is a terminal tool.
- **No clipboard integration.** Pass URLs as arguments or use a batch file.
- **No automatic browser cookie import.** Android browser profiles are
  app-private; use `--cookies` or root-only `--root-cookies` for Firefox.
- **No Chrome cookie import, even with root.** Android Keystore encryption is
  not supported by yt-dlp.
- **TLS impersonation is architecture-dependent.** Published Android wheels
  target arm64; other architectures may not support it.
- **Background execution is not guaranteed.** Android may kill long jobs;
  use a wake lock, battery exemption, and `tmux`.
- **Shared storage is slower than app-private storage.** Hashing, dedupe, and
  large merges are affected.
- **Torrent seeding is unreliable on mobile.** Downloading may work; seeding
  and incoming peers depend on the network and Android background policy.
- **`./install.sh --system` is not supported.** Termux uses `$PREFIX`, not
  `/usr/local`.
- **External SD cards have filesystem limits.** FAT/exFAT is not suitable for
  very large files.

## Development

The repository layout:

```text
bin/vdl               command entry point and orchestration
lib/vdl/              ui, helpers, args, settings, collect, paths,
                      classify, ytdlp, plan, images, downloads, scrape.py
install.sh            installer/uninstaller with --termux support
completions/          bash, zsh, and fish completions
man/vdl.1             man page
docs/USAGE.md         full user guide
docs/TERMUX.md        detailed Termux notes
docs/SPEC.md          behavior contract
test/smoke.sh         stub-based CLI tests, no network required
test/unit.sh          pure helper tests
test/integration.sh   real-tool integration suite, local fixture
test/fixtures/        real-world gallery HTML fixtures for scrape.py
```

Run the checks:

```sh
make test               # smoke + unit tests
make lint               # ShellCheck
make test-integration   # real yt-dlp/aria2c/ffmpeg, no internet needed
```

The smoke suite stubs the downloaders and needs no network access. The unit
suite covers URL classification, speed/quality normalization, filenames, and
Termux detection. The integration suite covers real downloads, playlists,
image ordering, fallback, naming/output, zip, pasted blocks, and the Python
image extractor.

Contributions are welcome; see [CONTRIBUTING.md](CONTRIBUTING.md) for the
workflow and ShellCheck requirements.

## Uninstall

Use the same prefix you installed with:

```sh
cd vdl
./install.sh --termux --uninstall
```

Remove configuration and the root-cookie cache if you no longer need them:

```sh
rm -rf ~/.config/vdl ~/.cache/vdl
```

Optionally remove packages that are no longer used:

```sh
pkg uninstall aria2 ffmpeg python-yt-dlp yt-dlp-ejs zip
# also remove your yt-dlp JavaScript runtime:
# pkg uninstall deno    # 64-bit
# pkg uninstall nodejs  # 32-bit
```

## License

MIT. See [LICENSE](LICENSE).

---

If you find a Termux-specific bug, include the output of `vdl --version`,
`termux-info`, `yt-dlp --version`, and the failing command in the issue.
