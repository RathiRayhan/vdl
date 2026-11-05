# vdl — Behavior Contract (SPEC)

This file is the single source of truth for how vdl should behave.  Keep it
in sync with the code when features change; use it as the contract when
editing, refactoring, or asking an AI to modify the project.

## File map

| Path | Role |
|------|------|
| `bin/vdl` | Orchestrator: sources the libraries and runs the pipeline in order |
| `lib/vdl/ui.sh` | Colors, `warn/err/note`, status lines, progress bar, banner/summary |
| `lib/vdl/helpers.sh` | Pure helpers: usage, speed/quality/title normalization, URL classification, config file, browser/clipboard detection |
| `lib/vdl/images.sh` | Embedded-image scanning (`scrape_images`) and downloading (`download_images`) |
| `lib/vdl/downloads.sh` | Direct/media download engines and `--dedupe` |
| `lib/vdl/args.sh` | Command-line parsing (`parse_args`) |
| `lib/vdl/settings.sh` | Browser/quality/speed resolution (`resolve_settings`) |
| `lib/vdl/collect.sh` | URL collection, dedupe, `--name`/`--output` validation (`collect_urls`) |
| `lib/vdl/paths.sh` | Save dir, temp dir, traps, `--output` repointing (`setup_paths`) |
| `lib/vdl/classify.sh` | Direct/media split, image scan, name resolution, tool checks (`classify_urls`) |
| `lib/vdl/ytdlp.sh` | yt-dlp defaults and impersonation (`build_yt_common`) |
| `lib/vdl/plan.sh` | Engine/mode strings and the dry-run plan (`build_header`, `print_plan`) |
| `install.sh` | Installs `bin/vdl`, `lib/vdl/*.sh`, man page, completions |
| `test/smoke.sh` | Stub-based CLI tests (no network) |
| `test/unit.sh` | Unit tests for pure functions in `lib/vdl/helpers.sh` |
| `docs/USAGE.md` | User guide |
| `docs/SPEC.md` | This file |

`bin/vdl` sources the libraries from `../lib/vdl` relative to the script, so
the same relative layout works from the repo and from any install prefix.

## Pipeline

1. **Parse arguments** — vdl flags are consumed; unknown options and their
   values are kept in order for yt-dlp; URL-shaped tokens and bare `.txt`
   batch files are extracted.  `--` ends vdl option parsing.
2. **Resolve settings** — precedence: command line > environment > vdl config
   file > defaults.  Browser, quality, audio mode, and speed limits are
   validated here.
3. **Collect URLs** — arguments (including multi-line pasted blocks, split
   one URL per line; blank and non-URL lines in a paste are ignored), batch
   files (lines starting with `http://`/`https://`), or the clipboard when
   none were given; duplicates removed, order preserved.
4. **Classify** — `url_is_direct` (helpers.sh) implements the single routing
   rule.  See the routing table below.
5. **Scan for images (opt-in)** — only with `--images`/`VDL_IMAGES=1` and
   only for media URLs; see the image contract below.
6. **Plan** — engine/mode strings, `need_ytdlp`, ffmpeg requirement, banner,
   `--dry-run` exit.
7. **Download** — direct files via aria2c (`-Z`, 16 connections) with yt-dlp
   fallback for failed files; embedded images via aria2c per source page
   (referer + browser UA) with yt-dlp fallback; media via a single yt-dlp
   invocation (aria2c for http(s), native for HLS/DASH).
8. **Finish** — temp cleanup, `--dedupe`, summary, exit.

## Routing table (`url_is_direct`)

| URL | Engine |
|-----|--------|
| `magnet:*`, `.torrent` | direct (aria2c) |
| `.zip .rar .7z .iso .exe .msi .dmg .pkg .deb .rpm .appimage .flatpak .tar .tgz .tbz2 .tbz .txz .tlz .gz .xz .zst .bz2 .pdf .epub .apk .bin .img .jpg .jpeg .png .webp .gif` | direct |
| plain video `.mp4 .mkv .webm .avi .mov .flv` (video mode only) | direct |
| everything else | media (yt-dlp) |

The check uses the **last** path extension, so stacked suffixes such as
`.tar.gz` or `.zip.gz` classify as direct.

## Exit codes

| Code | Meaning |
|------|---------|
| 0 | all downloads finished (or nothing failed) |
| 1 | runtime failure (missing yt-dlp/ffmpeg, downloads failed) |
| 2 | usage error (bad flag value, invalid speed/quality/browser) |
| 130 | interrupted by Ctrl+C |

## Key state (owned by bin/vdl, shared with libs)

- `urls`, `direct`, `media`, `img_urls` (+ `img_refs`, `img_dirs`): URL queues.
- `passthru`: unknown yt-dlp options in original order.
- Counters: `direct_ok/direct_fail`, `media_ok/media_fail`, `img_ok/img_fail`, `rc`.
- `save_dir`, `tmp_dir`, `out_dir`, `browser`, `quality`, `yt_common`.

Libraries may read and update these globals but must not introduce new
persistent state that bin/vdl does not know about.

## Backend mappings

| vdl flag | aria2c | yt-dlp |
|----------|--------|--------|
| `--max-speed R` | `--max-overall-download-limit=R(bytes)` | `--limit-rate` |
| `--limit-speed R` | `--max-download-limit=R(bytes)` | `--limit-rate` |

Rates accept an integer with optional `K/M/G` suffix (1024-based); a decimal
fraction requires a suffix; `0` means unlimited.  yt-dlp receives the
stricter non-zero value when both flags are set.

- aria2c always runs with `-Z` (one download per URL; without it multiple
  URLs are treated as mirrors of one file).
- Direct files: 16 connections, resume, no preallocation.
- Embedded images: 4 connections, page URL as referer, browser UA.

## Embedded-image contract (`--images` / `VDL_IMAGES=1`)

- Only pages whose yt-dlp extractor is `generic` or `html5` are scanned;
  known-site extractors are skipped.  `--dry-run` never touches the network.
- The page is fetched to a temp file and parsed only if it looks like HTML.
- Candidates come from `<img src/data-src>` (both quote styles, `?v=...`
  stripped).  Excluded by name: favicon, apple-touch, logo, `/icons/`,
  `icon-`, avatar, `/thumbs/`.
- Scoped to the album via the playlist's media URLs: same directory tree
  (host-insensitive, `/thumb/` normalized) is kept; thumbnails whose basename
  matches a media file (video covers) are skipped.
- `/thumb/` previews upgrade to the full-size image; a same-named `.jpg`
  sibling is probed for `.webp` previews.
- Images save into the sanitized album/playlist folder (`sanitize_title`,
  matching yt-dlp's folder sanitization), or the save dir when no title
  exists.
- A page with images but no video formats is an image-only album: the page is
  removed from the media queue so yt-dlp does not fail on it.

## Dedupe contract (`--dedupe`)

- Only files created during the current run (`mtime >=` run start), excluding
  the temp dir and `.aria2/.part/.ytdl/.temp` files.
- Same byte size, then identical SHA-256, then delete all but the oldest
  copy.  Pre-existing files can never be deleted.

## Custom filename (`--name NAME`)

- Applies to a single input URL only; more than one URL is a usage error
  (exit 2).
- Direct files: `NAME` with the URL's extension appended when NAME has none;
  a NAME containing an extension is used verbatim.
- Single media/audio item: appended as the last `-o` to yt-dlp (the last one
  wins); without an extension the template `NAME.%(ext)s` is used so the
  real container wins.  Audio mode always uses `.mp3`.
- Playlist URL: a light `%(playlist_count)s` probe detects the playlist and
  `NAME` becomes the (sanitized) folder name — items inside keep their
  per-item title template.
- Embedded images keep their own names; on image-only pages `--name` is
  ignored with a note.

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

## Tests

- `test/smoke.sh` — end-to-end CLI behavior against stub binaries; every new
  flag or routing change needs a case here.
- `test/unit.sh` — pure functions (`normalize_speed`, `sanitize_title`,
  `url_filename`, `url_is_direct`); any new pure helper needs cases here.
- CI runs ShellCheck on `bin/vdl install.sh test/smoke.sh test/unit.sh` and
  every `lib/vdl/*.sh`, then both test suites.
