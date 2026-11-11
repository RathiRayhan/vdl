# vdl

[![CI](https://github.com/RathiRayhan/vdl/actions/workflows/ci.yml/badge.svg)](https://github.com/RathiRayhan/vdl/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/RathiRayhan/vdl?label=release)](https://github.com/RathiRayhan/vdl/releases/latest)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Platform: Linux](https://img.shields.io/badge/platform-Linux-3DDC84)](https://www.linux.org/)

**vdl — Versatile Downloader for Linux.** A fast, resumable command-line
downloader: routes every URL to the right engine automatically:

- **Direct files** — archives, disk images, documents, packages, plain video
  files, magnet links, and `.torrent` files — go through **aria2c** with
  multiple connections and resume support.
- **Media** — YouTube and other supported sites, playlists, HLS, and DASH —
  go through **yt-dlp** with quality limits, MP3 extraction, metadata, and
  MP4 merging.
- **Gallery / file hosts** — sites supported by **gallery-dl** can now be
  downloaded through it when it is installed; `--gallery` forces that engine
  for any non-direct URL.
- **Mixed input** is handled in one command. Direct files, media URLs, and
  gallery links are split automatically and downloaded with their respective
  engines.

`vdl` is pure Bash. There is no compiled component to build, no daemon, and
no root requirement. Everything runs in your terminal and saves to your
downloads folder.

> A Termux/Android edition lives on the `termux` branch; this README is the
> Linux reference.

---

## Contents

- [Why vdl](#why-vdl)
- [Features](#features)
- [Requirements](#requirements)
- [Installation](#installation)
- [Updating](#updating)
- [Quick start](#quick-start)
- [Advanced usage](#advanced-usage)
- [Common options](#common-options)
- [Configuration](#configuration)
- [Troubleshooting](#troubleshooting)
- [Development](#development)
- [Uninstall](#uninstall)
- [License](#license)

---

## Why vdl

Browsers and standalone download managers each do half the job. `vdl` gives
one command the desktop-class pipeline:

- One command for direct files, torrents, videos, and audio.
- Multiple connections per direct file with automatic resume.
- yt-dlp for sites that require extractors, cookies, or stream handling.
- Decisions made per URL, so mixed link lists work in one run.
- Output that is usable in a terminal: a plan, per-URL status, a run-level
  `[Run] n/m` counter, a live progress bar, a failure recap, and a final
  summary.

## Features

- **Smart routing** — aria2c for files and torrents, yt-dlp for pages,
  playlists, and streams; one invocation can use both.
- **Resumable transfers** — interrupted direct files continue from where
  they stopped; yt-dlp partials live in stable per-output directories under
  `$XDG_CACHE_HOME/vdl/partials/` and are reused on the next run.
- **Quality control** — default 1080p cap, with `720`, `2k`, `4k`, and `8k`
  aliases.
- **Audio extraction** — `-a` downloads the best audio and converts it to
  MP3 320k under `<save_dir>/audio`.
- **Custom destinations** — `--name` renames a single file/video or names a
  playlist folder; `--output` pins a URL to an exact file path or folder.
- **Playlist and album support** — entries are grouped into folders with
  predictable names.
- **Browser cookies** — auto-detected from installed browsers, with
  explicit `NAME:PROFILE` support and `-n` to disable.
- **TLS impersonation** — optional `curl_cffi` support for sites that reject
  normal clients; automatically skipped when unavailable.
- **Bandwidth controls** — overall and per-download limits with `K`/`M`/`G`
  suffixes.
- **Headers and proxies** — custom Referer, User-Agent, and proxy support.
- **Embedded images** — opt-in scanning of generic album pages with
  `--images`.
- **Gallery hosts** — optional `gallery-dl` routing for album and file
  hosts that yt-dlp does not support, plus `--gallery` to force it.
- **Collision policy** — `--on-collision skip|rename|fail|overwrite` decides
  what happens when a direct file or embedded image already exists.
- **Duplicate cleanup** — opt-in `--dedupe` keeps the oldest copy of
  byte-identical files from the same run.
- **Zip archiving** — opt-in `--zip[=NAME.zip]` packs a run's downloads into
  a single archive in the save directory.
- **Batch input** — read URLs from text files with `-i` or a bare `.txt`
  argument, or paste a multi-line block of URLs directly.
- **yt-dlp passthrough** — unknown options are forwarded in order with
  their values, so advanced yt-dlp flags still work.
- **Safe recovery** — a failed aria2c run retries only incomplete HTTP(S)
  files through yt-dlp.
- **Preview mode** — `--dry-run` shows the resolved plan without
  downloading.
- **Machine-readable output** — `--json` and `--json-lines` report per-URL
  engines, statuses, files, errors, and run counts for scripting.
- **Environment doctor** — `vdl --doctor` checks tools, browser cookies,
  config, save-directory writability, and free space.
- **Quiet mode** — `--quiet` suppresses banners, status lines, and progress.

## Requirements

### Core

| Component | Purpose | Package hint |
|---|---|---|
| Bash 4+ | runs vdl | base system |
| yt-dlp | pages, playlists, streams | distro package, `pipx install yt-dlp`, or the standalone binary |

### Recommended

| Component | Purpose | Package hint |
|---|---|---|
| aria2c | fast direct downloads, torrents | `aria2` |
| ffmpeg | MP3 extraction, merging, metadata | `ffmpeg` |
| gallery-dl | gallery/album/file hosts | `pipx install gallery-dl` |
| curl | embedded-image scanning | `curl` |
| python-curl_cffi | optional TLS impersonation | `python3-curl_cffi` |
| wl-clipboard / xclip / xsel | clipboard URL pickup | `wl-clipboard`, `xclip`, `xsel` |

`vdl` checks available tools at run time:

- Without `aria2c`, direct files are downloaded by yt-dlp instead.
- Without `ffmpeg`, media downloads still work but audio extraction and
  merging do not.
- Without `gallery-dl`, known gallery hosts stay on yt-dlp (and may fail);
  `--gallery` exits with an install hint.
- Without `curl_cffi`, TLS impersonation is skipped.
- Without a clipboard tool, paste a URL or use a batch file.

## Installation

### 1. Install the toolchain

Install yt-dlp and the optional tools from your distribution, for example:

```sh
sudo apt install yt-dlp aria2 ffmpeg curl xclip
```

yt-dlp moves quickly; if your distro's package is old, prefer `pipx install
yt-dlp` or the standalone binary from the yt-dlp releases.

Optional, for TLS impersonation:

```sh
pip install -U curl-cffi
```

Optional, for gallery and file hosts:

```sh
pipx install gallery-dl
```

`--gallery` and known gallery hosts use `gallery-dl` when it is installed.
Without it, those URLs stay on yt-dlp and `--gallery` prints an install
hint.

### 2. Install vdl

```sh
git clone https://github.com/RathiRayhan/vdl.git
cd vdl
./install.sh
```

The installer places `vdl` in `~/.local/bin`, its libraries in
`~/.local/lib/vdl`, the man page in `~/.local/share/man/man1`, and
completions for the shells it detects. For a system-wide install:

```sh
sudo ./install.sh --system
```

Verify:

```sh
vdl --version
vdl --help
man vdl
```

If the shell cannot find `vdl`, add `~/.local/bin` to your `PATH` (the
installer prints the line to add) or open a new shell.

## Updating

```sh
cd vdl
git pull
./install.sh
```

Keep yt-dlp, aria2, and ffmpeg current with your package manager or their own
installers.

## Quick start

```sh
# A video or page
vdl "https://youtu.be/VIDEO_ID"

# A direct file (ISO, ZIP, PDF, ...)
vdl "https://example.com/file.iso"

# Audio only, MP3 320k
vdl -a "https://example.com/album"

# A playlist at 720p
vdl -q 720 "https://example.com/playlist"

# A text file with one URL per line
vdl links.txt

# Several URLs, or a pasted block
vdl "https://example.com/a" "https://example.com/b"
vdl 'https://example.com/one
https://example.com/two'

# A custom filename
vdl --name my-archive "https://example.com/file.zip"

# Preview routing and options without downloading
vdl --dry-run "https://example.com/file.iso"

# A gallery/album page supported by gallery-dl
vdl "https://example.com/gallery/123"
```

By default, files are saved under:

```text
~/Downloads/vdl
```

## Advanced usage

### Routing

| URL type | Engine |
|---|---|
| `magnet:`, `.torrent` | aria2c |
| `.zip`, `.iso`, `.pdf`, `.deb`, `.tar.gz`, images, ... | aria2c |
| Plain `.mp4`, `.mkv`, `.webm`, `.avi`, `.mov`, `.flv` | aria2c in video mode |
| HLS/DASH (`.m3u8`, `.mpd`) | yt-dlp native |
| Known gallery/file hosts supported by gallery-dl | gallery-dl when installed |
| Pages, playlists, streams, everything else | yt-dlp + aria2c where possible |

Routing checks the last path extension, so `.tar.gz`, `.tgz`, and friends
are all direct. Use `--no-aria` to force all direct files through yt-dlp.

### Gallery and file hosts

```sh
vdl "https://example.com/gallery/123"            # auto-routed when supported
vdl --gallery "https://example.com/gallery/456"  # force gallery-dl
VDL_GALLERY=1 vdl "https://example.com/album/789"  # same as --gallery
```

Gallery-dl sites are now available to be downloaded: known album and file
hosts supported by gallery-dl are routed through it only when it is
installed; otherwise they stay on yt-dlp. `--gallery` sends every non-direct
URL through gallery-dl and exits with an install hint when the tool is
missing. gallery-dl keeps its own filenames, so `--name`/`--output` file
naming is ignored for gallery URLs (`--output` folder/save-dir still
applies), and `--gallery` cannot be combined with `--audio`.

If a normal yt-dlp batch fails with `Unsupported URL` for a specific link,
vdl retries only that link through gallery-dl when it is available. Network,
authentication, and Cloudflare failures never trigger the fallback.

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

`--name` requires exactly one input URL and must be a plain filename:
path separators, `.`/`..`, and a leading `-` are rejected with exit 2. Use
`--output` for an exact path.

### Exact destination

```sh
vdl --output ~/Videos/movie.mp4 "https://example.com/video"   # exact file
vdl --output ~/Videos/season1 "https://example.com/playlist"  # exact folder
```

A path ending in an extension is the exact file; otherwise it is the exact
folder (playlist items land directly inside it). Directories are created
automatically. `--output` requires exactly one URL and cannot be combined
with `--name`.

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
them into the album folder, upgrading `/thumb/` previews to full-size
images. Favicons, logos, avatars, video covers, and sidebar thumbnails are
skipped. Known-site extractors such as YouTube are not scanned. This is
opt-in because it adds page requests; images are downloaded after the
videos. It comes in handy for photo galleries, manga chapters, product
photos, and teardown guides — anywhere a site serves its images as plain
HTML.

### Duplicate cleanup

```sh
vdl --dedupe "https://example.com/album"
```

After the run, files created by that run are compared by size and SHA-256.
Identical copies are removed, keeping the oldest. Files that existed before
the run are never touched.

### Zip archiving

```sh
vdl --zip url1 url2 url3                   # vdl-<timestamp>.zip
vdl --zip=my-batch.zip links.txt           # explicit name
```

Packs everything downloaded in the run into one zip in the save directory
(playlist folders keep their structure). Runs after `--dedupe`; requires the
`zip` command. The archive is built under a temporary name and moved into
place only after `zip` succeeds, and a name that collides with a downloaded
file is refused. A failed archive leaves the downloads in place but exits
nonzero.

### Torrents and magnets

```sh
vdl 'magnet:?xt=urn:btih:...'
vdl 'https://example.com/file.torrent'
```

Torrents require aria2c. They are not retried through yt-dlp.

### Speed limits

```sh
vdl --max-speed 2M "https://example.com/file.iso"
vdl --limit-speed 500K "https://example.com/video"
```

Rates accept `K`, `M`, or `G` suffixes (1024-based); decimals need a suffix.
`0` means unlimited. `--max-speed` maps to aria2c's overall limit;
`--limit-speed` maps to aria2c's per-download limit. yt-dlp has one rate
limit, so it receives the stricter non-zero value when both flags are set.

### Batch files and pasted blocks

```sh
vdl links.txt
vdl -i more-links.txt links.txt
vdl 'https://example.com/one
https://example.com/two'
```

Only lines beginning with `http://` or `https://` are read from files;
blank lines and comments are ignored. In a pasted block, non-URL lines are
ignored too.

### Headers and proxies

```sh
vdl --referer "https://example.com/page" "https://example.com/file.iso"
vdl --user-agent "Mozilla/5.0 ..." "https://example.com/file.iso"
vdl --proxy "http://127.0.0.1:8080" "https://example.com/video"
```

### Cookies

```sh
vdl -b firefox "https://example.com/video"
vdl -b firefox:work "https://example.com/video"   # specific profile
vdl -n "https://example.com/file.iso"             # no cookies
```

The browser is auto-detected when `-b` is not given. Cookies apply to
yt-dlp requests. aria2c direct downloads do not receive browser cookies; use
`--no-aria` for a cookie-protected direct link.

### TLS impersonation

Some sites reject clients based on TLS fingerprints. vdl asks yt-dlp to
impersonate a browser when `curl_cffi` is available; it silently skips
impersonation when yt-dlp reports no usable target.

```sh
vdl --no-impersonate "https://example.com/video"
VDL_IMPERSONATE=chrome vdl "https://example.com/video"
VDL_IMPERSONATE=off vdl "https://example.com/video"
```

Impersonation applies to yt-dlp requests. aria2c media transfers do not
impersonate; retry with `--no-aria` if a host rejects aria2c.

### Preview and quiet mode

```sh
vdl --dry-run "https://example.com/file.iso"
vdl --quiet "https://example.com/video"
```

`--dry-run` resolves routing, quality, cookies, and impersonation without
downloading.

### Interrupting and resuming

Press `Ctrl+C`. Completed files stay in place. An in-flight yt-dlp partial
remains in a stable directory under `$XDG_CACHE_HOME/vdl/partials/`;
aria2c keeps its partial file and `.aria2` control file in the save
directory. Run the same command again to resume. Per-run logs and manifests
live separately under `$XDG_CACHE_HOME/vdl/runs/`.

## Common options

Run `vdl --help` for the complete list. The most useful options:

| Option | Meaning |
|---|---|
| `-q, --quality HEIGHT` | Maximum video height; `720`, `1080`, `2k`, `4k`, `8k` |
| `-a, --audio` | Best audio, converted to MP3 320k |
| `-n, --no-cookies` | Do not use cookies |
| `-i, --batch-file FILE` | Read URLs from a file |
| `-b, --browser NAME` | Browser cookie source or explicit profile |
| `--download-dir DIR` | Save under DIR; a bare name (`custom-dir`) is created inside the default vdl folder |
| `--name NAME` | Custom filename, or playlist folder name |
| `--output PATH` | Exact destination: file or folder for a single URL |
| `--zip[=NAME.zip]` | Archive this run's downloads into a zip |
| `--on-collision MODE` | Existing-file policy: `skip` (default), `rename`, `fail`, `overwrite` |
| `--json` | Machine-readable run report on stdout |
| `--json-lines` | One JSON object per item, then a summary |
| `--doctor` | Check tools, config, browser, and paths |
| `--no-aria` | Send direct files through yt-dlp |
| `--no-impersonate` | Disable TLS impersonation |
| `--images` | Download images embedded in album pages |
| `--gallery` | Use gallery-dl for gallery/file hosts (and all non-direct URLs) |
| `--dedupe` | Remove duplicate files downloaded in this run |
| `--max-speed RATE` | Overall speed limit |
| `--limit-speed RATE` | Per-download speed limit |
| `--referer URL` | Custom Referer header |
| `--user-agent UA` | Custom User-Agent header |
| `--proxy URL` | Proxy for downloads |
| `--aria-opts OPTS` | Extra aria2c options |
| `--dry-run` | Show the plan without downloading |
| `--quiet` | Suppress vdl output |

Any unknown option is forwarded to yt-dlp with its value in order. This
makes advanced flags available without vdl reimplementing them:

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
| `VDL_SAVE_DIR` | `~/Downloads/vdl` | download directory |
| `VDL_BROWSER` | auto-detect | default cookie source |
| `VDL_QUALITY` | `1080` | default maximum height |
| `VDL_IMPERSONATE` | `auto` | `auto`, `off`, or a target name |
| `VDL_IMAGES` | unset | `1` or `yes` scans album pages for images |
| `VDL_GALLERY` | unset | `1` or `yes` enables `--gallery` mode by default |
| `VDL_TMP_KEEP_DAYS` | `7` | days to keep interrupted partials and failed-run scratch directories |
| `VDL_CONFIG` | `~/.config/vdl/yt-dlp.conf` | extra yt-dlp config file |
| `VDL_CONFIG_DIR` | `~/.config/vdl` | vdl config directory |
| `NO_COLOR` | unset | disable colored output |

### vdl config file

`~/.config/vdl/config` is a simple `KEY=VALUE` file. Comments start with
`#`.

```sh
# ~/.config/vdl/config
QUALITY=720
BROWSER=firefox
SAVE_DIR=~/Downloads/vdl
IMPERSONATE=chrome
IMAGES=1
GALLERY=1
```

Command-line flags take precedence over exported environment variables,
which take precedence over this file.

### Extra yt-dlp options

`VDL_CONFIG` points to a regular yt-dlp config file:

```sh
# ~/.config/vdl/yt-dlp.conf
--extractor-args "youtube:player_client=web_safari"
```

This file is loaded *in addition* to vdl's built-in defaults. yt-dlp's
global config is still ignored.

## Troubleshooting

### `vdl: command not found`

```sh
hash -r
command -v vdl
```

`vdl` installs to `~/.local/bin`. If that directory is not on your `PATH`,
add it (the installer prints the line) or install system-wide with
`sudo ./install.sh --system`.

### `Permission denied` when creating the save directory

Use `--download-dir` for a writable location, or fix the permissions:

```sh
vdl --download-dir ~/Downloads "https://example.com/video"
```

### `yt-dlp is required but was not found in PATH`

Install yt-dlp (distro package, `pipx install yt-dlp`, or the standalone
binary) and re-run.

### `gallery-dl is required`

Install it with `pipx install gallery-dl` and re-run, or drop `--gallery`.
Without gallery-dl, known gallery hosts are still tried with yt-dlp.

### Direct files fail with 403 or an anti-bot page

Some CDNs reject plain download clients. Try:

```sh
vdl --no-aria "https://example.com/file.iso"
vdl --user-agent "Mozilla/5.0 ..." "https://example.com/file.iso"
```

### YouTube only shows 360p

Update yt-dlp first. If formats are still missing, the client or account may
require a PO token provider — see the
[yt-dlp PO Token Guide](https://github.com/yt-dlp/yt-dlp/wiki/PO-Token-Guide).

### Merge or MP3 conversion fails

Install ffmpeg:

```sh
sudo apt install ffmpeg
```

Large 4K merges are CPU-heavy; use a lower quality cap when possible:

```sh
vdl -q 1080 "https://example.com/video"
```

### `curl_cffi` will not install

Impersonation is optional. vdl continues without it; only sites that reject
non-impersonated clients are affected.

### Interrupted downloads

Nothing is lost. Completed files are in their final folders; re-run the same
command to resume the rest.

## Development

The repository layout:

```text
bin/vdl               command entry point and orchestration
lib/vdl/              ui, helpers, images, gallery, and download engines,
                      plus args, settings, collect, paths, classify, ytdlp,
                      plan, report, and doctor
install.sh            installer/uninstaller
completions/          bash, zsh, and fish completions
man/vdl.1             man page
docs/USAGE.md         full user guide
docs/SPEC.md          behavior contract
test/smoke.sh         stub-based CLI test runner, no network required
test/smoke/cases/     individual smoke-test cases (run in filename order)
test/unit.sh          pure helper tests
```

Run the checks:

```sh
make test                # smoke + unit suites
make test-integration    # real yt-dlp/aria2c/ffmpeg, local fixture, no internet
make lint                # shellcheck all scripts
```

The smoke suite stubs the downloaders and needs no network access. The
integration suite serves a local fixture and drives the real downloaders
end to end. CI runs ShellCheck, smoke, unit, and integration on every push
to `main`. Contributions are welcome; see [CONTRIBUTING.md](CONTRIBUTING.md)
for the workflow and style
rules.

## Uninstall

Use the same prefix you installed with:

```sh
cd vdl
./install.sh --uninstall
```

Remove configuration if you no longer need it:

```sh
rm -rf ~/.config/vdl
```

## License

MIT. See [LICENSE](LICENSE).

---

If you find a bug, include the output of `vdl --version`, `yt-dlp --version`,
and the failing command in the issue.
