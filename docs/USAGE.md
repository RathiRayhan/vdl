# vdl User Guide

`vdl` — Versatile Downloader for Linux — is a smart downloader. It routes
every URL to the right engine — aria2c for direct files, yt-dlp for pages,
playlists and streams, and optional gallery-dl for gallery/file hosts — and
layers resumable multi-connection downloads, browser cookies, speed limits,
custom names, and embedded album images on top.

This guide covers installation, setup, every feature with examples, and
uninstallation. See the [README](../README.md) for the project overview,
`man vdl` for the option reference, and [SPEC.md](SPEC.md) for the behavior
contract.

---

## Requirements

| Tool | Needed for | Package hint |
|------|------------|--------------|
| `bash` >= 4 | always | base system |
| `yt-dlp` | pages, playlists, streams | distro package, pipx, or the standalone binary |
| `aria2c` | fast direct-file downloads (optional) | `aria2` |
| `ffmpeg` | `-a` audio extraction, merging | `ffmpeg` |
| `gallery-dl` | gallery/album/file hosts (optional) | `pipx install gallery-dl` |
| `python-curl_cffi` | browser impersonation (optional, auto-detected) | `python-curl-cffi` |
| `curl` | embedded-image scanning (`--images`, optional) | `curl` |
| `wl-clipboard`, `xclip`, or `xsel` | clipboard URL pickup (optional) | `wl-clipboard`, `xclip`, `xsel` |

Everything optional is detected at run time: without `aria2c`, direct files
are downloaded with yt-dlp; without `curl_cffi`, impersonation is skipped;
without `gallery-dl`, known gallery hosts stay on yt-dlp.

---

## Installation

```sh
git clone https://github.com/RathiRayhan/vdl.git
cd vdl

./install.sh                     # ~/.local/bin + shell completions
./install.sh --shells bash,zsh   # limit completions to specific shells
./install.sh --no-completions    # command only
sudo ./install.sh --system       # /usr/local, system-wide
```

The installer places:

- `vdl` in `<prefix>/bin`
- its libraries in `<prefix>/lib/vdl`
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

Copy `bin/vdl` and its libraries to any directory on your `PATH`, keeping
the relative layout (`vdl` looks for its libraries in `../lib/vdl`):

```sh
install -Dm755 bin/vdl ~/.local/bin/vdl
install -d ~/.local/lib/vdl
install -Dm644 lib/vdl/*.sh -t ~/.local/lib/vdl/
install -Dm644 man/vdl.1 ~/.local/share/man/man1/vdl.1
```

---

## Setup

### Environment variables

| Variable | Default | Meaning |
|----------|---------|---------|
| `VDL_SAVE_DIR` | `$(xdg-user-dir DOWNLOAD)/vdl` | exact download directory |
| `VDL_BROWSER` | auto-detect | default cookie source |
| `VDL_QUALITY` | `1080` | default max video height |
| `VDL_TMP_KEEP_DAYS` | `7` | keep interrupted partials and failed-run scratch directories this long |
| `VDL_IMPERSONATE` | `auto` | `auto`, `off`, or a browser target |
| `VDL_IMAGES` | unset | `1`/`yes` to always scan album pages for images |
| `VDL_GALLERY` | unset | `1`/`yes` to enable `--gallery` mode by default |
| `VDL_CONFIG` | `~/.config/vdl/yt-dlp.conf` | extra yt-dlp config file |
| `VDL_CONFIG_DIR` | `~/.config/vdl` | directory for vdl's own config file |
| `NO_COLOR` | unset | disable colored output |

```sh
# in ~/.profile or ~/.bashrc
export VDL_SAVE_DIR="$HOME/Downloads/vdl"
export VDL_BROWSER=firefox
export VDL_QUALITY=720
```

Precedence everywhere: **command line > environment > config file >
defaults**.

### vdl config file

`$VDL_CONFIG_DIR/config` (default `~/.config/vdl/config`) is a `KEY=VALUE`
file that sets defaults mirroring the `VDL_*` variables.

```sh
# ~/.config/vdl/config
QUALITY=720
BROWSER=firefox
SAVE_DIR=~/Downloads/vdl
IMPERSONATE=chrome
IMAGES=1
GALLERY=1
TMP_KEEP_DAYS=7
```

### Extra yt-dlp options

`VDL_CONFIG` points to an ordinary yt-dlp config file (default
`~/.config/vdl/yt-dlp.conf`), loaded **in addition** to vdl's built-in
defaults:

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
vdl "https://example.com/video"                      # single URL
vdl "https://example.com/video" "https://example.com/file.zip"   # mixed input
vdl "https://example.com/a" "https://example.com/b"  # multiple URLs
vdl 'https://example.com/one
https://example.com/two'                             # pasted URL block
vdl                                                 # URL from the clipboard
vdl www.example.com/video                            # "www." normalized to https://
```

Any number of URLs can be given in one run — space-separated or pasted as a
single multi-line block. Blank lines and non-URL lines in a paste are
ignored. All flags apply to every URL in the run. vdl classifies each URL,
uses aria2c for direct files and yt-dlp for everything else, and removes
duplicate URLs while preserving order.

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

When cookies come from a browser, vdl also mirrors that browser's
User-Agent (probed from the installed binary, cached per browser version
in `~/.cache/vdl/`). Cloudflare's clearance cookie is bound to the
User-Agent that solved its challenge, so the match keeps the cookies
valid; the headless probe reruns only after the browser updates. An
explicit `--user-agent` always wins. A run that fails with a 403 suggests
opening the page in the browser once and rerunning, so the freshly solved
cookies can be reused.

### TLS impersonation

```sh
vdl --no-impersonate "https://example.com/video"   # disable
VDL_IMPERSONATE=chrome vdl "https://example.com"   # force a target
```

By default vdl probes `yt-dlp --list-impersonate-targets` and uses the
newest target of the first supported family (`chrome`, `firefox`, or
`safari`) that the installed curl_cffi can actually produce. If none is
available it continues without impersonation.

### Headers and proxy

```sh
vdl --referer "https://example.com/page" "https://example.com/file.iso"
vdl --user-agent "Mozilla/5.0 ..." "https://example.com/file.iso"
vdl --proxy "http://127.0.0.1:8080" "https://example.com/video"
```

These are forwarded to whichever engine handles the URL.

### Routing

| URL looks like | Engine |
|----------------|--------|
| archive/package/document (`zip`, `iso`, `pdf`, `deb`, ...) | aria2c, 16 connections |
| magnet links, `.torrent` files | aria2c, 16 connections |
| plain video file (`mp4`, `mkv`, `webm`, ...) | aria2c (yt-dlp in `-a` mode) |
| HLS/DASH (`m3u8`, `mpd`) | yt-dlp native, 8 fragments |
| known gallery/file hosts supported by gallery-dl | gallery-dl when installed |
| pages, playlists, everything else | yt-dlp + aria2c (10 connections) |

Routing checks the last path extension, so `.tar.gz`, `.zip.gz`, `.tgz`,
and friends are all direct. Force everything through yt-dlp with
`--no-aria`.

### Gallery and file hosts (`--gallery`)

```sh
vdl "https://example.com/gallery/123"            # auto-routed when supported
vdl --gallery "https://example.com/gallery/456"  # force gallery-dl
VDL_GALLERY=1 vdl "https://example.com/album/789"  # same as --gallery
```

Gallery-dl sites are now available to be downloaded: known album and file
hosts supported by gallery-dl are routed through it automatically only when
it is installed; otherwise they stay on yt-dlp (with a note).
`--gallery` sends every non-direct URL through gallery-dl and exits with an
install hint if the tool is missing; with only direct URLs it is a no-op.

gallery-dl keeps its own filenames, so `--name`/`--output` file naming is
ignored for gallery URLs (an `--output` folder or save directory still
applies). `--gallery` cannot be combined with `--audio`, because gallery-dl
does not convert to MP3. If a normal yt-dlp batch reports `Unsupported URL`
for a specific link, vdl retries only that link through gallery-dl when it
is available; network, authentication, and Cloudflare errors never trigger
the fallback.

### Magnet links and torrents

```sh
vdl 'magnet:?xt=urn:btih:abc123'
vdl 'https://example.com/file.torrent'
```

Torrent payloads are only fetched by aria2c. If aria2c fails, magnet/torrent
downloads are reported as failed rather than retried with yt-dlp.

### Speed limits

```sh
vdl --max-speed 2M "https://example.com/file.iso"     # overall limit
vdl --limit-speed 500K "https://example.com/file.iso" # per-download limit
vdl --limit-speed 1.5M "https://example.com/video"    # decimals allowed
```

Rates accept a byte count with an optional case-insensitive `K`, `M`, or `G`
suffix (1024-based). A bare number means bytes per second, `0` means
unlimited, and fractional values require a suffix. Invalid values are
rejected before any download starts. `--max-speed` maps to aria2c's overall
limit, `--limit-speed` to its per-download limit; yt-dlp (which has one
limit) receives the stricter non-zero value.

### Save location and naming

```sh
vdl --download-dir ~/tmp "https://example.com/file.zip"   # one-off override
vdl --download-dir custom-dir "https://example.com/video"  # inside the default vdl folder
VDL_SAVE_DIR=~/media vdl "https://example.com/video"      # or set the variable
```

Naming:

- Single videos land flat in the save directory as `<title> [<id>].<ext>`.
- Playlist and album entries get a folder named after the playlist/album.
- `-a` writes MP3 files to `<save_dir>/audio` with the same layout.

Existing destination handling for **direct files and embedded images** is
controlled by `--on-collision`:

```sh
vdl --on-collision skip URL...        # default: report existing files as skipped
vdl --on-collision rename URL...      # save as file.1.iso instead
vdl --on-collision fail URL...        # exit 2 before a direct download
vdl --on-collision overwrite URL...   # replace existing files (destructive)
```

Media filenames come from yt-dlp and gallery-dl and keep their own collision
behavior; `overwrite` still passes yt-dlp's force-overwrite flag.  Within a
single run, different direct URLs that share a basename are always given
distinct names under `skip`/`rename` so one input cannot silently replace
another.

### Custom filename (`--name`)

```sh
vdl --name my-rom "https://example.com/file.iso"        # -> my-rom.iso
vdl --name "episode 1" "https://example.com/video"      # -> episode 1.mp4
vdl --name custom.mp4 "https://example.com/video"       # used verbatim
vdl -a --name mytune "https://example.com/song"         # -> audio/mytune.mp3
```

The extension is appended automatically when the name has none (audio mode
always uses `.mp3`). For a **playlist URL**, `--name` names the folder
instead — items inside keep their own titles. `--name` requires exactly one
URL and must be a plain filename: path separators, `.`/`..`, and a leading
`-` are rejected with exit 2. Use `--output` when you need a path.

### Exact destination (`--output`)

```sh
vdl --output ~/Videos/movie.mp4 "https://example.com/video"  # exact file
vdl --output ~/Videos/season1 "https://example.com/playlist" # exact folder
```

A path whose last component has an extension is the exact file; otherwise it
is the exact folder (playlist items go directly inside it, with no
title-named subfolder). Directories are created automatically. `--output`
requires exactly one URL and cannot be combined with `--name`.

### yt-dlp passthrough options

Unknown options are forwarded to yt-dlp in their original order, with values
attached:

```sh
vdl -F "https://example.com/video"                      # list formats
vdl --playlist-start 3 "https://example.com/playlist"
vdl --download-archive seen.txt "https://example.com/video"
vdl -f "bestvideo+bestaudio" --merge-output-format mkv \
    "https://example.com/video"
```

These options take effect on yt-dlp paths; a pure aria2c direct download
does not interpret yt-dlp-only flags.

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
impersonation target without invoking any downloader.  Combine it with
`--json` for a machine-readable plan.

### Scripting output and diagnostics

```sh
vdl --json URL...                 # one JSON report on stdout
vdl --json-lines URL...           # one object per item plus a summary
vdl --doctor                      # environment check
vdl --doctor --json               # machine-readable environment check
```

`--json` suppresses the human UI so stdout contains only the report.  It
includes each URL's engine, status (`ok`, `failed`, or `skipped`), files,
error, run counts, archive, timestamps, and exit code.  Warnings and
downloader errors remain on stderr.

`--doctor` checks Bash, yt-dlp, the optional engines and tools, browser
cookie access, impersonation targets, clipboard support, config files,
save-directory writability, and free space.  Missing optional tools are
warnings; a missing yt-dlp or an unusable save directory is a failure and
returns a nonzero status.

### Automatic recovery

If aria2c exits with an error during direct downloads, vdl does not
re-download everything:

1. A file with an `.aria2` control file is treated as interrupted — the
   partial file and its control file are removed.
2. Missing files are retried.
3. Completed files are left untouched.

Only the incomplete HTTP(S) URLs are retried, via yt-dlp with the same save
directory, cookies, headers, proxy, impersonation, and passthrough options.
Magnet/torrent downloads are not retried. If nothing is retryable, vdl
exits with aria2c's status.

### Embedded images (`--images`)

Opt-in (`--images` or `VDL_IMAGES=1`), so plain links stay fast:

```sh
vdl --images "https://example.com/album/abc123"
```

Pages without a dedicated yt-dlp extractor (the `generic` and `html5`
extractors) are scanned for `<img>` sources (`.jpg`, `.jpeg`, `.png`,
`.webp`, `.gif`, both quote styles, `?v=...` cache-busters). The scan is
scoped to the album via the playlist's media URLs: same-directory images are
kept, video covers and sidebar thumbnails are skipped, and `/thumb/`
previews upgrade to the full-size image. Favicons, logos, avatars, and UI
icons are excluded. Photos download with aria2c (browser user-agent + the
album page as referer) into the album folder next to the videos — and the
page is only **scanned after the videos have finished**, so media always
comes first. A page with
images but no video formats is treated as an image-only album. Known-site
extractors (YouTube, ...) are not scanned, and `--dry-run` never touches the
network. Everyday uses: photo galleries, manga chapters, product photos,
and teardown guides — anywhere images live in plain HTML.

### Removing duplicate downloads (`--dedupe`)

Some sites list the same video more than once per playlist. `--dedupe`
cleans that up after the run:

```sh
vdl --dedupe "https://example.com/album/abc123"
```

vdl compares the files created during that run (tracked from downloader
completion events) — first by size, then by full content hash — and removes
duplicates, always keeping the oldest copy. Pre-existing files in the save
directory are never touched. Opt-in; off by default.

### Archiving to a zip (`--zip`)

After a multi-URL or batch run, pack everything downloaded in that run into
a single zip in the save directory:

```sh
vdl --zip url1 url2 url3                       # vdl-20261106-123456.zip
vdl --zip=my-batch.zip links.txt               # explicit name
```

The archive contains the run's files and playlist folders (relative to the
save directory); `.zip` is appended when the given name lacks it. Files from
earlier runs are never included, and `--dedupe` runs first so duplicates are
not archived. The archive is built under a temporary name and moved into
place only after `zip` succeeds, so a failure cannot delete an existing file.
An archive name that matches a file downloaded in the same run is refused.
The `zip` command is required; a missing or failing `zip` leaves the
downloads in place but makes the run exit nonzero with an "archive failed"
verdict.

### Interrupting a download

Press Ctrl+C any time. Items that finished are already in their final
folders; only the in-flight one stays in a stable partial directory. vdl
prints a hint and exits with status 130. Re-run the exact same command to
resume — completed files are skipped and the interrupted one continues.
Resume is byte-exact for both engines: aria2c restarts with a `Range`
request where it stopped, and yt-dlp prints `Resuming download at byte N`.

Download partials live under `$XDG_CACHE_HOME/vdl/partials/` and are reused
by the next invocation; per-run logs and manifests live under
`$XDG_CACHE_HOME/vdl/runs/`. Both older than `VDL_TMP_KEEP_DAYS` (default 7)
are cleaned automatically on exit, without touching unrelated files in your
save directory. If aria2c fails while yt-dlp is unavailable, the partial is
kept for a later resume instead of being deleted.

### Terminal output

A normal run shows a banner (engine, mode, URL counts, save dir), section
headers, per-URL status lines with `[ok]`/`[fail]`, and an end-of-run
summary with per-engine results and elapsed time. After each phase a
run-level progress line tracks the whole batch:

```
  [Run] 2/3 · 1 failed
```

Failed downloads are recapped in the summary with their reason:

```
Failed:
  [fail] https://example.com/video — yt-dlp exit 1
```

yt-dlp downloads render as a live bar whose width adapts to the terminal:

```
[#########-----------] 43.3% 405KiB/488KiB | 149KiB/s | ETA 00:01
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

This removes `vdl`, its libraries, the man page, and the completions. To
clean up leftovers:

```sh
rm -rf ~/.config/vdl                  # vdl config and yt-dlp.conf
```

If you previously used the old fish function version, remove it as well —
fish functions take precedence over binaries on `PATH`:

```sh
rm -f ~/.config/fish/functions/vdl.fish
```

---

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| `yt-dlp is required but was not found in PATH` | Install yt-dlp (distro package, pipx, or the standalone binary) |
| Direct files download slowly or fail with 403 | Some CDNs block plain clients; retry with `--no-aria` or `--user-agent` |
| `Invalid speed` / `Invalid quality` / `Unknown browser` | Check the value; exit code 2 means a usage error |
| `--images` finds nothing | Only `generic`/`html5` pages are scanned; images must be plain `<img>` tags in the page HTML |
| A page yields "Unsupported URL" | Try `--images` for photo-only albums, or install `gallery-dl` so unsupported links can fall back |
| `gallery-dl is required` | Install it with `pipx install gallery-dl`, or drop `--gallery` |
| Interrupted run left `.aria2` partials | Re-run the same command; `aria2c` resumes from where it stopped |

For more help, see the [README](../README.md), the [SPEC](SPEC.md), or open
an issue on GitHub.
