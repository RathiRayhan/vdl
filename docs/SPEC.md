# vdl — Behavior Contract (SPEC)

This file is the single source of truth for how vdl should behave. Keep it
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
| `lib/vdl/collect.sh` | URL collection, dedupe, multi-line paste, `--name`/`--output` validation (`collect_urls`) |
| `lib/vdl/paths.sh` | Save dir, temp dir, traps, `--output` repointing (`setup_paths`) |
| `lib/vdl/classify.sh` | Direct/media split, image scan, name resolution, tool checks (`classify_urls`) |
| `lib/vdl/ytdlp.sh` | yt-dlp defaults and impersonation (`build_yt_common`) |
| `lib/vdl/plan.sh` | Engine/mode strings and the dry-run plan (`build_header`, `print_plan`) |
| `install.sh` | Installs `bin/vdl`, `lib/vdl/*.sh`, man page, completions |
| `test/smoke.sh` | Stub-based CLI tests (no network) |
| `test/unit.sh` | Unit tests for pure functions in `lib/vdl/helpers.sh` |
| `docs/USAGE.md` | User guide |
| `docs/SPEC.md` | This file |

`bin/vdl` sources the libraries from `../lib/vdl` relative to the real
script path (symlinks are resolved), so the same relative layout works from
the repo and from any install prefix.

## Pipeline

1. **Parse arguments** — vdl flags are consumed; unknown options and their
   values are kept in order for yt-dlp; URL-shaped tokens and bare `.txt`
   batch files are extracted.  `--` ends vdl option parsing.
2. **Resolve settings** — precedence: command line > environment > vdl
   config file > defaults.  Browser, quality, audio mode, and speed limits
   are validated here.
3. **Collect URLs** — arguments (multi-line pasted blocks are split into
   one URL per line; blank and non-URL lines in a paste are ignored), batch
   files (lines starting with `http://`/`https://`), or the clipboard when
   none were given; duplicates removed, order preserved.
4. **Set up paths** — save dir, temp dir (`<save_dir>/.tmp`), EXIT/INT
   traps, and the `--output` repointing.
5. **Classify** — `url_is_direct` implements the routing rule; media URLs
   may be scanned for images (`--images`); `--name`/`--output` are resolved;
   yt-dlp/ffmpeg requirements are checked.
6. **Build yt-dlp defaults** — `yt_common` (ignore-config, retries,
   progress template, rate limit) and impersonation probing.
7. **Plan** — engine/mode strings, banner, directories, `--dry-run` exit.
8. **Download** — direct files via aria2c (`-Z`, 16 connections, custom
   name without `-Z`) with yt-dlp fallback for failed files; media via a
   single yt-dlp invocation (aria2c for HTTP(S), native for HLS/DASH);
   embedded images last, via aria2c per source page (referer + browser UA)
   with yt-dlp fallback, so videos are always downloaded first.
9. **Finish** — temp cleanup, `--dedupe`, summary, exit.

## Routing rule (`url_is_direct`)

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
| 2 | usage error (bad flag value, invalid speed/quality/browser, `--name`/`--output` with multiple URLs) |
| 130 | interrupted by Ctrl+C |

## Key state (owned by bin/vdl, shared with libs)

- `urls`, `direct`, `media`, `img_urls` (+ `img_refs`, `img_dirs`): URL queues.
- `passthru`: unknown yt-dlp options in original order.
- Counters: `direct_ok/direct_fail`, `media_ok/media_fail`, `img_ok/img_fail`, `rc`.
- `save_dir`, `tmp_dir`, `out_dir`, `browser`, `quality`, `yt_common`,
  `custom_direct`, `custom_media`, `out_folder_strip`.

Libraries may read and update these globals but must not introduce new
persistent state that `bin/vdl` does not declare.

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

- Only pages whose yt-dlp extractor is `generic` or `html5` are scanned;
  known-site extractors are skipped.  `--dry-run` never touches the network.
- The page is fetched to a temp file and parsed only if it looks like HTML.
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
- A page with images but no video formats is an image-only album: the page
  is removed from the media queue so yt-dlp does not fail on it.

## Dedupe contract (`--dedupe`)

- Only files created during the current run (`mtime >=` run start), excluding
  the temp dir and `.aria2/.part/.ytdl/.temp` files.
- Same byte size, then identical SHA-256, then delete all but the oldest
  copy.  Pre-existing files can never be deleted.

## Zip contract (`--zip[=NAME.zip]`)

- Runs after dedupe, using the same run window (files with `mtime >=` run
  start, temp dir and partials excluded).
- With no name, the archive is `vdl-<YYYYMMDD-HHMMSS>.zip`; an explicit name
  gets `.zip` appended when missing.  The archive is created in the save
  directory, with entries relative to it (playlist folders keep their
  structure).
- Requires the `zip` command; if missing, a warning is printed and the files
  are left in place (downloads still succeed).
- With no files downloaded in the run, a note is printed and no archive is
  created.

## Tests

- `test/smoke.sh` — end-to-end CLI behavior against stub binaries; every new
  flag or routing change needs a case here.
- `test/unit.sh` — pure functions (`normalize_speed`, `normalize_quality`,
  `sanitize_title`, `url_filename`, `url_is_direct`); any new pure helper
  needs cases here.
- CI runs ShellCheck (Ubuntu-packaged version) on `bin/vdl`, `install.sh`,
  both test files, and every `lib/vdl/*.sh`, then both suites.
