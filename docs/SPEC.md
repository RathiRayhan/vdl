# vdl — Behavior Contract (SPEC)

This file is the single source of truth for how vdl should behave. Keep it
in sync with the code when features change; use it as the contract when
editing, refactoring, or asking an AI to modify the project.

## File map

| Path | Role |
|------|------|
| `bin/vdl` | Orchestrator: sources the libraries and runs the pipeline in order |
| `lib/vdl/ui.sh` | Colors, `warn/err/note`, status lines, progress bar, banner/summary |
| `lib/vdl/helpers.sh` | Pure helpers: usage, speed/quality/title normalization, URL classification, config file, browser/clipboard detection, Termux detection and root Firefox cookie staging |
| `lib/vdl/images.sh` | Embedded-image scanning (`scrape_images`) and downloading (`download_images`) |
| `lib/vdl/gallery.sh` | gallery-dl host detection, downloads, and `Unsupported URL` fallback (`url_is_gallery_host`, `download_gallery`) |
| `lib/vdl/downloads.sh` | Direct/media download engines and `--dedupe` |
| `lib/vdl/args.sh` | Command-line parsing (`parse_args`) |
| `lib/vdl/settings.sh` | Browser/cookie/quality/speed resolution (`resolve_settings`, `build_cookie_args`) |
| `lib/vdl/collect.sh` | URL collection, dedupe, multi-line paste, root cookie staging, `--name`/`--output` validation (`collect_urls`) |
| `lib/vdl/paths.sh` | Save dir, temp dir, traps, Termux wake lock, `--output` repointing (`setup_paths`) |
| `lib/vdl/classify.sh` | Direct/media/gallery split, image scan, name resolution, tool checks (`classify_urls`) |
| `lib/vdl/ytdlp.sh` | yt-dlp defaults, cookies, and impersonation (`build_yt_common`) |
| `lib/vdl/plan.sh` | Engine/mode strings and the dry-run plan (`build_header`, `print_plan`) |
| `install.sh` | Installs `bin/vdl`, `lib/vdl/*.sh`, man page, completions; supports `--termux` |
| `test/smoke.sh` | Stub-based CLI test runner (no network); cases live in `test/smoke/cases/` |
| `test/unit.sh` | Unit tests for pure functions in `lib/vdl/helpers.sh` |
| `docs/USAGE.md` | User guide |
| `docs/TERMUX.md` | Detailed Termux setup, storage, cookie, and background guide |
| `docs/SPEC.md` | This file |

`bin/vdl` sources the libraries from `../lib/vdl` relative to the real
script path (symlinks are resolved), so the same relative layout works from
the repo and from any install prefix.

## Pipeline

1. **Parse arguments** — vdl flags are consumed; unknown options and their
   values are kept in order for yt-dlp; URL-shaped tokens and bare `.txt`
   batch files are extracted.  `--` ends vdl option parsing.
2. **Resolve settings** — precedence: command line > environment > vdl
   config file > defaults.  Browser, cookies file, quality, audio mode, and
   speed limits are validated here.  `-n` clears browser and file cookies.
3. **Collect URLs** — arguments (multi-line pasted blocks are split into
   one URL per line; blank and non-URL lines in a paste are ignored), batch
   files (lines starting with `http://`/`https://`), or the clipboard when
   none were given; duplicates removed, order preserved.  On Termux,
   `--root-cookies` is staged after URL validation, so a usage error never
   prompts for root.
4. **Set up paths** — save dir, run-isolated temp dir
   (`$XDG_CACHE_HOME/vdl/runs/<id>`), EXIT/INT traps (omitted in
   `--dry-run`), and the `--output` repointing.
5. **Classify** — `url_is_direct` implements the routing rule; known
   gallery/file hosts (and every non-direct URL under `--gallery`) go to the
   gallery queue; `--name`/`--output` are resolved; yt-dlp/gallery-dl/ffmpeg
   requirements are checked.  With `--images`, a light preflight probes each
   media page's extractor so image-only pages can be dropped from the media
   queue early.
6. **Build yt-dlp defaults** — `yt_common` (ignore-config, retries,
   progress template, rate limit, browser/file cookies) and impersonation
   probing.
7. **Plan** — engine/mode strings, banner, directories, `--dry-run` exit.
8. **Download** — direct files via aria2c (`-Z`, 16 connections, custom
   name without `-Z`) with yt-dlp fallback for failed files; media via a
   single yt-dlp invocation (aria2c for HTTP(S), native for HLS/DASH);
   gallery URLs via gallery-dl; **then**, with `--images`, the pages are
   scanned for images and the photos are downloaded, so videos always finish
   first.
9. **Finish** — temp cleanup, `--dedupe`, `--zip`, summary, exit.

## Routing rule (`url_is_direct`)

| URL | Engine |
|-----|--------|
| `magnet:*`, `.torrent` | direct (aria2c) |
| `.zip .rar .7z .iso .exe .msi .dmg .pkg .deb .rpm .appimage .flatpak .tar .tgz .tbz2 .tbz .txz .tlz .gz .xz .zst .bz2 .pdf .epub .apk .bin .img .jpg .jpeg .png .webp .gif` | direct |
| plain video `.mp4 .mkv .webm .avi .mov .flv` (video mode only) | direct |
| known gallery/file hosts, or any non-direct URL with `--gallery` | gallery-dl |
| everything else | media (yt-dlp) |

The check uses the **last** path extension, so stacked suffixes such as
`.tar.gz` or `.zip.gz` classify as direct.  Known-host routing only applies
when `gallery-dl` is installed; otherwise those URLs stay on yt-dlp with a
note.  `--gallery` forces gallery-dl for non-direct URLs and errors when the
tool is missing.

## Exit codes

| Code | Meaning |
|------|---------|
| 0 | all downloads finished (or nothing failed) |
| 1 | runtime failure (missing yt-dlp/gallery-dl/ffmpeg, downloads failed) |
| 2 | usage error (bad flag value, invalid speed/quality/browser/zip name, `--name`/`--output` with multiple URLs, `--gallery` with `--audio`) |
| 130 | interrupted by Ctrl+C |

Any nonzero failure counter (`direct_fail + media_fail + gallery_fail + img_fail > 0`) guarantees a nonzero exit code, even if another engine or retry succeeded in the same run.

## Key state (owned by bin/vdl, shared with libs)

- `urls`, `direct`, `media`, `gallery`, `img_urls` (+ `img_refs`, `img_dirs`): URL queues.
- `passthru`: unknown yt-dlp options in original order.
- Counters: `direct_ok/direct_fail`, `media_ok/media_fail`,
  `gallery_ok/gallery_fail`, `img_ok/img_fail`, `rc`.
- `save_dir`, `tmp_dir`, `out_dir`, `browser`, `quality`, `yt_common`,
  `custom_direct`, `custom_media`, `out_folder_strip`.
- `cookies_file`, `root_cookies`, `cookie_label`, `yt_cookie_args`,
  `termux_wakelock`.
- `scan_pages`, `scan_do`, `scan_title`, `failed_items`, `zip_created`,
  `zip_mode`, `zip_name`.

Libraries may read and update these globals.  Phase-local state belongs to
the library that owns it (for example, cookie state is built in
`lib/vdl/settings.sh`).

## Backend mappings

| vdl flag | aria2c | yt-dlp |
|----------|--------|--------|
| `--max-speed R` | `--max-overall-download-limit=R(bytes)` | `--limit-rate` |
| `--limit-speed R` | `--max-download-limit=R(bytes)` | `--limit-rate` |

Rates accept an integer with optional `K/M/G` suffix (1024-based); a decimal
fraction requires a suffix; `0` means unlimited.  yt-dlp receives the
stricter non-zero value when both flags are set.

- aria2c always runs with `-Z` (one download per URL; without it multiple
  URLs are treated as mirrors of one file), except with a custom name,
  where `-o` replaces `-Z` (single URL by contract).
- Direct files: 16 connections, resume, no preallocation.
- Embedded images: 4 connections, page URL as referer, browser UA.

## Multi-line paste contract

- A positional argument containing `\n` is split into one token per line;
  whitespace and `\r` are trimmed.
- URL-shaped lines become downloads; `.txt` lines that exist become batch
  files; **other lines are ignored** (never forwarded to yt-dlp).
- Values of unknown flags are never split.

## Custom filename (`--name NAME`)

- Single input URL only (exit 2 otherwise); cannot be combined with
  `--output`.
- Direct files: `NAME` with the URL's extension appended when NAME has
  none; a NAME containing an extension is used verbatim.
- Single media/audio item: appended as the last `-o` to yt-dlp (the last
  one wins); without an extension the template `NAME.%(ext)s` is used so
  the real container wins.  Audio mode always uses `.mp3`.
- Playlist URL: a `%(playlist_count)s` probe detects the playlist and
  `NAME` becomes the (sanitized) folder name — items keep their per-item
  title template.
- Embedded images keep their own names; on image-only pages `--name` is
  ignored with a note.
- gallery-dl keeps its own filenames; `--name`/`--output` file naming is
  ignored for gallery URLs with a note (`--output` folder/save-dir still
  applies).

## Exact destination (`--output PATH`)

- Single URL only; combining with `--name` is a usage error (exit 2).
- The save directory is repointed before classification and the image
  scanner, so every engine writes into PATH's directory.
- A PATH whose last component has an extension is the exact file: direct
  downloads use aria2c `-o`, media downloads append `-o` (last one wins).
  Playlist URLs are rejected (exit 2, detected via `%(playlist_count)s`).
- A PATH without an extension is the exact folder: the media item template
  drops the `%(playlist_title)s` prefix, so playlist items land directly
  inside PATH; audio mode also writes into PATH instead of `audio/`.

## Embedded-image contract (`--images` / `VDL_IMAGES=1`)

- A light preflight probes each media page's extractor before downloading:
  pages whose yt-dlp extractor is not `generic`/`html5` are never scanned,
  and pages with no video formats (image-only albums) are removed from the
  media queue so yt-dlp does not fail on them.  `--dry-run` never touches
  the network.
- The heavy scan runs **after the media downloads**: each queued page is
  fetched to a temp file and parsed only if it looks like HTML.
- Candidates come from `<img src/data-src>` (both quote styles, `?v=...`
  stripped).  Excluded by name: favicon, apple-touch, logo, `/icons/`,
  `icon-`, avatar, `/thumbs/`.
- Scoped to the album via the playlist's media URLs: same directory tree
  (host-insensitive, `/thumb/` normalized) is kept; thumbnails whose
  basename matches a media file (video covers) are skipped.
- `/thumb/` previews upgrade to the full-size image; a same-named `.jpg`
  sibling is probed for `.webp` previews.
- Images save into the sanitized album/playlist folder (`sanitize_title`,
  matching yt-dlp's folder sanitization), or the save dir when no title
  exists.
- The banner and `--dry-run` plan are printed before the scan, so they show
  only the input URLs; scanned images appear in the run and the summary.

## Gallery contract (`--gallery` / `VDL_GALLERY=1`)

- `url_is_gallery_host` recognizes known gallery/album/file hosts that
  gallery-dl handles better than yt-dlp. Recognition is host-based,
  case-insensitive, and path-scoped where the host also serves ordinary
  pages.
- Direct-file URLs are classified first, so a gallery host serving a `.zip`
  stays on aria2c.  Known hosts route to gallery-dl only when it is
  installed; otherwise they stay on yt-dlp with a note.  `--gallery` forces
  every non-direct URL through gallery-dl and exits 1 (with an install hint)
  when the tool is missing; with only direct URLs it is a no-op.
- `--gallery` refuses `--audio` with exit 2; gallery-dl does not convert to
  MP3.
- gallery-dl runs one URL per invocation with `-D "$save_dir"` so files land
  directly in vdl's save directory.  It inherits the browser cookies,
  User-Agent, proxy, quiet mode, and the stricter speed limit.
- A failed yt-dlp media batch is retried through gallery-dl only for URLs
  reported as `Unsupported URL:` in yt-dlp's log.  Network, authentication,
  and Cloudflare failures are never retried with a second engine.
- Gallery results are counted separately (`gallery_ok/gallery_fail`) and
  appear in the progress line, banner counts, summary, and final verdict.

## Dedupe contract (`--dedupe`)

- Uses an explicit run output manifest (`$tmp_dir/manifest.txt`) populated
  from downloader completion events (`aria2c --on-download-complete`,
  `yt-dlp --print-to-file after_move:filepath`,
  `gallery-dl --Print-to-file after:{_path}`), excluding `.aria2/.part/.ytdl/.temp`
  files and any file whose path/inode/size/timestamps match a pre-run
  snapshot of `save_dir`.
- Same byte size, then identical SHA-256, then delete all but the oldest
  copy.  Pre-existing untouched files can never be deleted.

## Cleanup contract

- `--dry-run` never creates directories, installs cleanup traps, probes
  browsers, or touches caches.
- Temporary files and internal scratch state (manifests, logs, page scrapes)
  live under `$XDG_CACHE_HOME/vdl/runs/<id>` — never inside `save_dir`.
- Clean exits remove the run directory; failed or interrupted runs remove
  internal scratch files and preserve any in-flight temp state until older
  than `VDL_TMP_KEEP_DAYS` (default 7), when expired run directories under
  `$XDG_CACHE_HOME/vdl/runs/` are swept.
- `vdl` never recursively sweeps `save_dir` for `*.aria2` files or `.tmp`
  directories.
- On an aria2c failure with yt-dlp available (direct or embedded images),
  the specific URL's partial and `.aria2` control file are removed before
  the retry; completed files without a `.aria2` sidecar are counted
  separately.  When yt-dlp is unavailable the partial is **kept** so a
  later run can resume it, and the failure is reported.

## Zip contract (`--zip[=NAME.zip]`)

- Runs after dedupe, using the same explicit run output manifest and
  pre-existing file protection (so `--mtime` downloads are included and
  pre-existing untouched files are excluded).
- With no name, the archive is `vdl-<YYYYMMDD-HHMMSS>.zip`; an explicit
  `--zip=NAME` must be a plain basename (empty names, `/`, `\`, `..`, `.`,
  and option-like `-*` names are rejected with exit 2).  `.zip` is appended
  when missing, and the archive is created inside `save_dir` with entries
  relative to it (playlist folders keep their structure).
- Requires the `zip` command; if missing, a warning is printed and the files
  are left in place (downloads still succeed).
- With no files downloaded in the run, a note is printed and no archive is
  created.

## Tests

- `test/smoke.sh` — end-to-end CLI behavior against stub binaries; every new
  flag or routing change needs a case in `test/smoke/cases/`.
- `test/unit.sh` — pure functions (`normalize_speed`, `normalize_quality`,
  `sanitize_title`, `url_filename`, `url_is_direct`,
  `url_is_gallery_host`); any new pure helper needs cases here.
- `test/integration.sh` — drives the REAL yt-dlp/aria2c/ffmpeg against a
  local HTTP fixture (multi-direct, playlists, `--images` ordering,
  image-only albums, fallback, `--name`/`--output`, `--zip`, pasted blocks,
  and the python image extractor).  No internet access required.
- `lib/vdl/scrape.py` — the HTML image extractor for `--images` (python3;
  the bash regex pipeline remains as a fallback when python3 is absent).
- `test/fixtures/` — anonymized real-world gallery HTML patterns; the
  integration suite asserts the extractor's exact output for each, so a
  parser change that breaks a supported site pattern fails CI.
- CI runs ShellCheck (Ubuntu-packaged version) on `bin/vdl`, `install.sh`,
  the test files, and every `lib/vdl/*.sh`, then all three suites.
