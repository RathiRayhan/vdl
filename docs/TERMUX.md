# vdl on Termux

`vdl` is a Bash script, so it runs on Android through
[Termux](https://termux.dev/) without a compiled port. Termux supplies both
download engines and the media tooling.

This guide covers setup, Android-specific behavior, cookies, and the few
features that do not translate directly.

## Requirements

Install the packages from Termux:

```sh
pkg update
pkg install git bash coreutils findutils gawk grep sed curl \
    aria2 python ffmpeg termux-api
pkg install python-yt-dlp yt-dlp-ejs
```

Choose a JavaScript runtime for yt-dlp's YouTube challenge solver:

```sh
pkg install deno       # recommended on 64-bit ARM/x86_64
# pkg install nodejs   # use on 32-bit devices, then see below
```

On 32-bit devices, add the runtime to vdl's yt-dlp config because vdl calls
yt-dlp with `--ignore-config`:

```sh
mkdir -p ~/.config/vdl
printf '%s\n' '--js-runtimes node' >> ~/.config/vdl/yt-dlp.conf
```

Optional server-side TLS impersonation support:

```sh
pkg install python-pip
pip install -U curl-cffi
yt-dlp --list-impersonate-targets
```

`curl_cffi` currently publishes Android **arm64** wheels. On 32-bit ARM or
x86_64 Termux it may fail to install; vdl simply runs without impersonation
when yt-dlp reports no available target.

`termux-api` is the command-line package. Also install the **Termux:API** app
(F-Droid) if you want the automatic wake lock.

## Install

```sh
termux-setup-storage
git clone https://github.com/rathi/vdl.git
cd vdl
./install.sh --termux
```

`--termux` installs the script, libraries, man page, and completions under
`$PREFIX` (for example `/data/data/com.termux/files/usr`). Running
`./install.sh` inside Termux detects the environment and does the same.
Do not use `--system`: Android does not have a useful `/usr/local`.

## Storage

Termux's `$HOME` is private to the app. Files there work, but Android's file
manager, gallery, and other apps cannot see them, and they disappear if Termux
is uninstalled.

`termux-setup-storage` creates `~/storage/downloads`, usually a link to
`/storage/emulated/0/Download`. When that directory exists, vdl defaults to:

```
~/storage/downloads/vdl
```

Override it for a single run or permanently:

```sh
vdl --download-dir ~/storage/downloads/videos "https://example.com/video"
export VDL_SAVE_DIR=~/storage/downloads/videos
```

On Android 11+, grant Termux storage access when prompted by
`termux-setup-storage`; some OEM firmware also requires "All files access" in
Android settings. If a new file does not appear in the gallery or file manager
immediately, trigger Android's media scanner:

```sh
termux-media-scan -r ~/storage/downloads/vdl
```

External SD cards formatted as FAT/exFAT cannot store files larger than 4 GB
and reject some filename characters. Use internal shared storage for large
media, or pass yt-dlp's `--windows-filenames` through vdl when a filename
contains characters the card rejects.

## Cookies

### Non-root: manual cookies.txt

Termux cannot read Android Chrome/Firefox app-private profiles, so automatic
browser detection is disabled. Export a Netscape-format `cookies.txt` from a
browser (on Android or another machine) and pass it with `--cookies`:

```sh
vdl --cookies ~/storage/downloads/cookies.txt "https://example.com/video"
```

The same value can be set permanently:

```sh
# ~/.config/vdl/config
COOKIES=~/storage/downloads/cookies.txt
```

or in the environment:

```sh
export VDL_COOKIES=~/storage/downloads/cookies.txt
```

Cookies still apply only to yt-dlp paths. Use `--no-aria` for a
cookie-protected direct file so yt-dlp, not aria2c, downloads it.

### Root: Firefox Android cookies

On a rooted device, vdl can copy **Firefox for Android**'s plaintext cookie
database out of app-private storage and hand it to yt-dlp:

```sh
vdl --root-cookies "https://example.com/video"
```

This invokes `su`, so the root manager may ask for permission. It supports the
stable, beta, and nightly Firefox Android packages. Close Firefox before
running so the SQLite database is not mid-write. The copied database is staged
under `~/.cache/vdl/root-cookies/firefox` with owner-only permissions.
On a secondary Android user, point it at the right data root:

```sh
VDL_TERMUX_FIREFOX_ROOT=/data/user/10 vdl --root-cookies "https://example.com/video"
```

Why only Firefox?

- Firefox stores cookies in a plaintext SQLite database, which root can copy.
- Chrome, Chromium, Brave, Edge, and other Chromium-based Android browsers
  encrypt cookie values with a key held by the Android Keystore. Root can read
  the database file, but yt-dlp cannot decrypt the values. Export a
  `cookies.txt` file for those browsers instead.

Root does not make the normal `-b chrome` / `-b firefox` auto-detection work:
Termux runs as its own UID and yt-dlp's browser paths are desktop paths. Use
`--root-cookies` for the supported Firefox case, a copied Firefox profile with
`-b firefox:/path/to/profile`, or `--cookies` for everything else.

Cookies only apply to yt-dlp paths. For a cookie-protected direct link, add
`--no-aria` so yt-dlp downloads the file instead of aria2c.

## Background downloads

Android may suspend or kill Termux when the screen turns off. If the
Termux:API app is installed, vdl automatically holds a wake lock for the run
and releases it on exit or Ctrl+C. Disable this with:

```sh
VDL_WAKELOCK=0 vdl "https://example.com/video"
```

For long downloads, also:

- Disable battery optimization for Termux in Android settings.
- Keep the device on a charger for large merges.
- Consider `tmux` inside Termux so closing the terminal does not end the
  session.
- On Android 12+, OEM task killers and the phantom-process killer can still
  interrupt long child processes.

## Media and impersonation

- `ffmpeg` in Termux includes libmp3lame, so `-a` produces MP3 320k and
  `--merge-output-format mp4` works. Merging is CPU-bound; 4K jobs can take a
  while and heat the phone.
- `aria2c` supports HTTP(S), FTP, BitTorrent, and Metalink in Termux. Magnet
  and `.torrent` downloads work, but background reliability and seeding are
  limited by Android and mobile networks.
- 16 connections per direct file is a desktop default. On metered mobile data
  or a weak connection, reduce it:
  ```sh
  vdl --aria-opts "-x 4 -s 4" "https://example.com/file.iso"
  ```
- TLS impersonation works only when `curl_cffi` can load. On arm64 with a
  current Android wheel it usually does; otherwise vdl silently continues
  without it.
- yt-dlp may need `yt-dlp-ejs` plus Deno/Node for YouTube. Install both and,
  on 32-bit, select Node in `~/.config/vdl/yt-dlp.conf` as shown above.

## Clipboard and sharing

vdl on Termux does not integrate with the Android clipboard. Pass URLs as
arguments, use a batch file, or wire the Android share sheet to Termux:

```sh
mkdir -p ~/.termux
cat > ~/.termux/termux-url-opener <<'EOF'
#!/data/data/com.termux/files/usr/bin/bash
exec vdl "$1"
EOF
chmod +x ~/.termux/termux-url-opener
```

Sharing a URL to Termux then starts the download in a new terminal session.

## Known limitations

- Automatic `-b` browser cookie extraction is unavailable on Termux; even with
  root, only Firefox can be imported, and only via `--root-cookies`.
- Desktop clipboard tools (`wl-paste`, `xclip`, `xsel`) do not exist.
- `--system` installation and `/usr/local` are not applicable.
- Downloads to private Termux storage are invisible to Android apps.
- Android background restrictions can interrupt long downloads and torrents.
- `--dedupe` works, but hashing large files over Android's FUSE shared storage
  is slower and uses more battery.
- TLS impersonation is architecture-dependent (arm64 only for the published
  Android wheels).
- A graphical Android app would be a separate project; this is a terminal tool.

## Uninstall

```sh
./install.sh --termux --uninstall
rm -rf ~/.config/vdl ~/.cache/vdl
```
