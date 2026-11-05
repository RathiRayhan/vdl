#!/usr/bin/env bash
# shellcheck shell=bash
# shellcheck disable=SC2154,SC2329  # globals live in bin/vdl; functions invoked from there
#
# vdl helpers: usage, value parsing/normalization, browser detection,
# clipboard, config file, and the URL classification rule.  Sourced by
# bin/vdl; every function here is pure (no side effects on vdl state).

usage() {
    cat <<'EOF'
vdl - smart downloader for Linux (yt-dlp + aria2c)

Usage:
  vdl [options] <url> | <links.txt>
  vdl [options]                    # no URL: takes the link from the clipboard

Options:
  -b, --browser NAME       Browser to take cookies from (default: auto-detect)
                           vivaldi firefox brave chromium chrome edge opera
                           safari whale none    (NAME:PROFILE also works)
  -n, --no-cookies         Do not read browser cookies
  -q, --quality HEIGHT     Max video height (default: 1080; 2k=1440, 4k=2160)
  -a, --audio              Audio only, converted to MP3 320k
  -i, --batch-file FILE    Read URLs from FILE (repeatable)
      --no-aria            Do not use aria2c (direct files go to yt-dlp too)
      --no-impersonate     Disable browser TLS impersonation
      --download-dir DIR   Override save directory for this run
      --dry-run            Show what would be done, then exit
      --dedupe             Remove duplicate files downloaded in this run
      --images             Also download images embedded in album pages
      --quiet              Suppress banner, status and progress output
      --aria-opts OPTS     Extra options for aria2c
      --max-speed RATE     Overall download speed limit (e.g. 1M, 500K)
      --limit-speed RATE   Per-download speed limit
      --name NAME          Save a single download under this filename
      --output PATH        Exact destination: file path (with extension) or
                           folder for a single URL
      --referer URL        Send this Referer header
      --user-agent UA      Send this User-Agent header
      --proxy URL          Route downloads through this proxy
  -h, --help               Show this help
  -V, --version            Show version

Any other option is passed straight through to yt-dlp. Flags that take a
value can always be written as --flag=value; that form is never mistaken
for a URL or a batch file.

Environment:
  VDL_SAVE_DIR        Download directory (default: XDG download dir + /vdl)
  VDL_BROWSER         Default browser, overridden by -b
  VDL_QUALITY         Default max height, overridden by -q
  VDL_TMP_KEEP_DAYS   Days to keep interrupted leftovers (default: 7)
  VDL_IMPERSONATE     auto | off | <target> (default: auto = chrome)
  VDL_IMAGES          1 | yes to always scan album pages for images
  VDL_CONFIG          Extra yt-dlp config file
                      (default: ~/.config/vdl/yt-dlp.conf)
  VDL_CONFIG_DIR      Directory for vdl's own config file
                      (default: ~/.config/vdl)
  NO_COLOR            Disable colored output

A vdl-specific config file ($VDL_CONFIG_DIR/config) provides KEY=VALUE
defaults mirroring the VDL_* variables.  Command-line flags and exported
environment variables take precedence over both.

Examples:
  vdl                                     # URL from clipboard
  vdl links.txt                           # every URL listed in links.txt
  vdl -q 720 links.txt
  vdl -a "https://example.com/album"
  vdl -n "https://example.com/file.iso"
  vdl --no-aria -F "https://example.com/video"
  vdl --dry-run "https://example.com/file.iso"
  vdl --download-dir ~/tmp "https://example.com/file.zip"
  vdl --name my-archive "https://example.com/file.zip"
  vdl --output ~/Videos/movie.mp4 "https://example.com/video"
  vdl --images "https://example.com/album/abc123"
  vdl magnet:?xt=urn:btih:abc123
EOF
}

need_value() {
    err "Option $1 requires a value"
    exit 2
}

detect_browser() {
    local name dir
    while IFS='|' read -r name dir; do
        if [[ -d $dir ]]; then
            printf '%s\n' "$name"
            return 0
        fi
    done <<EOF
vivaldi|$HOME/.config/vivaldi
firefox|$HOME/.mozilla/firefox
brave|$HOME/.config/BraveSoftware/Brave-Browser
chromium|$HOME/.config/chromium
chrome|$HOME/.config/google-chrome
edge|$HOME/.config/microsoft-edge
opera|$HOME/.config/opera
EOF
    printf 'none\n'
}

read_clipboard() {
    local out='' line=''

    if [[ -n ${WAYLAND_DISPLAY:-} ]] && have wl-paste; then
        out=$(wl-paste -n 2>/dev/null) || out=''
    elif [[ -n ${DISPLAY:-} ]] && have xclip; then
        out=$(xclip -o -selection clipboard 2>/dev/null) || out=''
    elif [[ -n ${DISPLAY:-} ]] && have xsel; then
        out=$(xsel --clipboard --output 2>/dev/null) || out=''
    elif have wl-paste; then
        out=$(wl-paste -n 2>/dev/null) || out=''
    fi

    [[ -n $out ]] || return 1

    IFS= read -r line <<< "$out" || true
    line=${line%$'\r'}
    line=${line#"${line%%[![:space:]]*}"}
    line=${line%"${line##*[![:space:]]}"}
    printf '%s\n' "$line"
}

normalize_quality() {
    local q=${1,,}
    q=${q%p}
    case $q in
        2k)   q=1440 ;;
        4k)   q=2160 ;;
        8k)   q=4320 ;;
    esac
    [[ $q =~ ^[1-9][0-9]*$ ]] || return 1
    printf '%s\n' "$q"
}

# yt-dlp's own capability list is authoritative: curl_cffi may be importable
# and still unusable (wrong version, different Python, missing libcurl). The
# table marks unavailable targets with "(unavailable)" and target names are
# listed in the first column.
imp_target_available() {
    local list=${1:-} target=${2:-}
    [[ -n $list && -n $target ]] || return 1
    printf '%s\n' "$list" | awk -v t="$target" '
        tolower($1) == tolower(t) && $0 !~ /\(unavailable\)/ { found = 1 }
        END { exit !found }
    '
}

# Convert a speed string like "1M", "500K", "1.5M" or "1G" to bytes/second.
# A plain integer works with both aria2c and yt-dlp and avoids their different
# handling of units and decimals.
normalize_speed() {
    local s=${1// /}
    local lower=${s,,}
    local num frac unit scale=1 denom=1 frac_val=0
    local int_val i

    # Accept digits, an optional fractional part, and an optional K/M/G unit.
    [[ $lower =~ ^([0-9]+)(\.([0-9]{1,6}))?([kmg])?$ ]] || return 1

    num=${BASH_REMATCH[1]}
    frac=${BASH_REMATCH[3]}
    unit=${BASH_REMATCH[4]}

    # A fractional byte count is meaningless; require a unit for decimals.
    if [[ -z $unit && -n $frac ]]; then
        return 1
    fi

    case $unit in
        k) scale=1024 ;;
        m) scale=$((1024 * 1024)) ;;
        g) scale=$((1024 * 1024 * 1024)) ;;
    esac

    int_val=$((10#$num))
    if [[ -n $frac ]]; then
        frac_val=$((10#$frac))
        for ((i = 0; i < ${#frac}; i++)); do
            denom=$((denom * 10))
        done
    fi

    printf '%s\n' "$((int_val * scale + frac_val * scale / denom))"
}

# Return the URL basename used for direct-file naming, or fail when the URL
# has no usable basename (the caller then falls back to a yt-dlp template).
url_filename() {
    local name=${1%%\?*}
    name=${name%%#*}
    name=${name##*/}
    case $name in
        ''|.|..) return 1 ;;
    esac
    printf '%s\n' "$name"
}

# Sanitize an album/page title the same way yt-dlp does for its playlist
# folders (invalid characters become their full-width lookalikes), so
# embedded images land in the same folder as the page's videos.
sanitize_title() {
    local t=$1
    t=${t//\//⧸}
    t=${t//\\/⧹}
    t=${t//:/：}
    t=${t//\?/？}
    t=${t//\*/＊}
    t=${t//\"/＂}
    t=${t//</＜}
    t=${t//>/＞}
    t=${t//|/丨}
    while [[ $t == *[[:space:].] ]]; do
        t=${t%[[:space:].]}
    done
    printf '%s\n' "$t"
}

# Read the vdl-specific config file ($XDG_CONFIG_HOME/vdl/config or
# ~/.config/vdl/config).  It is a simple KEY=VALUE file; lines starting with #
# are comments.  Environment variables and CLI flags take precedence, so this
# function only sets defaults that haven't already been provided.
read_vdl_config() {
    local conf="${VDL_CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/vdl/config}"
    [[ -f $conf ]] || return 0

    local key val
    while IFS='=' read -r key val || [[ -n $key ]]; do
        # strip CR and surrounding whitespace
        key=${key%$'\r'}
        key=${key#"${key%%[![:space:]]*}"}
        key=${key%"${key##*[![:space:]]}"}
        val=${val%$'\r'}
        val=${val#"${val%%[![:space:]]*}"}
        val=${val%"${val##*[![:space:]]}"}
        # skip comments and blank lines
        [[ -z $key || $key == \#* ]] && continue

        case $key in
            BROWSER)      [[ -z ${VDL_BROWSER:-} ]] && export VDL_BROWSER=$val ;;
            QUALITY)      [[ -z ${VDL_QUALITY:-} ]] && export VDL_QUALITY=$val ;;
            SAVE_DIR)     [[ -z ${VDL_SAVE_DIR:-} ]] && export VDL_SAVE_DIR=$val ;;
            IMPERSONATE)  [[ -z ${VDL_IMPERSONATE:-} ]] && export VDL_IMPERSONATE=$val ;;
            IMAGES)       [[ -z ${VDL_IMAGES:-} ]] && export VDL_IMAGES=$val ;;
            TMP_KEEP_DAYS) [[ -z ${VDL_TMP_KEEP_DAYS:-} ]] && export VDL_TMP_KEEP_DAYS=$val ;;
            CONFIG)       [[ -z ${VDL_CONFIG:-} ]] && export VDL_CONFIG=$val ;;
        esac
    done < "$conf"
}

# The single routing rule: does this URL look like a direct file?  Magnet
# links and .torrent files always do; archive/image extensions do; plain
# video files do unless we are in audio mode.  Everything else is a page,
# playlist or stream handled by yt-dlp.
url_is_direct() {
    local path=${1,,}
    path=${path%%\?*}
    path=${path%%#*}
    [[ $path == magnet:* ]] && return 0
    [[ $path =~ \.torrent$ ]] && return 0
    [[ $path =~ \.(zip|rar|7z|iso|exe|msi|dmg|pkg|deb|rpm|appimage|flatpak|tar|tgz|tbz2|tbz|txz|tlz|gz|xz|zst|bz2|pdf|epub|apk|bin|img|jpe?g|png|webp|gif)$ ]] && return 0
    (( ! audio )) && [[ $path =~ \.(mp4|mkv|webm|avi|mov|flv)$ ]] && return 0
    return 1
}
