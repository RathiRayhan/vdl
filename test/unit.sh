#!/usr/bin/env bash
# shellcheck shell=bash
# Unit tests for vdl's pure helper functions (lib/vdl/helpers.sh).
# No network, no stubs needed.
#
# Run: bash test/unit.sh

set -u

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
pass=0
fail=0

NO_COLOR=1
# shellcheck source=lib/vdl/ui.sh
source "$root/lib/vdl/ui.sh"
# shellcheck source=lib/vdl/helpers.sh
source "$root/lib/vdl/helpers.sh"

ok()  { pass=$((pass + 1)); }
bad() { fail=$((fail + 1)); printf 'FAIL: %s\n' "$*" >&2; }

expect_eq() { # label actual expected
    if [[ $2 == "$3" ]]; then
        ok
    else
        bad "$1: got '$2', want '$3'"
    fi
}

expect_fail_fn() { # label function args...
    local label=$1
    shift
    if "$@" >/dev/null 2>&1; then
        bad "$label: expected failure"
    else
        ok
    fi
}

audio=0

# --- normalize_speed --------------------------------------------------------
expect_eq "normalize 1M"    "$(normalize_speed 1M)"   1048576
expect_eq "normalize 500K"  "$(normalize_speed 500K)" 512000
expect_eq "normalize 1.5M"  "$(normalize_speed 1.5M)" 1572864
expect_eq "normalize 1G"    "$(normalize_speed 1G)"   1073741824
expect_eq "normalize 100"   "$(normalize_speed 100)"  100
expect_eq "normalize 0"     "$(normalize_speed 0)"    0
expect_fail_fn "normalize rejects bare fraction" normalize_speed 1.5
expect_fail_fn "normalize rejects T unit"        normalize_speed 1T
expect_fail_fn "normalize rejects garbage"       normalize_speed abc
expect_fail_fn "normalize rejects empty"         normalize_speed ''

# --- sanitize_title ---------------------------------------------------------
expect_eq "sanitize invalid chars" "$(sanitize_title 'a/b:c?d*e')" 'a⧸b：c？d＊e'
expect_eq "sanitize strips trailing" "$(sanitize_title 'x.. ')" 'x'
expect_eq "sanitize keeps plain"     "$(sanitize_title 'My Album')" 'My Album'

# --- normalize_quality ------------------------------------------------------
expect_eq "quality 2k"    "$(normalize_quality 2k)"    1440
expect_eq "quality 4k"    "$(normalize_quality 4k)"    2160
expect_eq "quality 8k"    "$(normalize_quality 8k)"    4320
expect_eq "quality 720"   "$(normalize_quality 720)"   720
expect_eq "quality 1080p" "$(normalize_quality 1080p)" 1080
expect_fail_fn "quality rejects 0"   normalize_quality 0
expect_fail_fn "quality rejects abc" normalize_quality abc

# --- url_filename -----------------------------------------------------------
expect_eq "filename strips query/hash" "$(url_filename 'https://h/p/x.jpg?q=1#f')" 'x.jpg'
expect_eq "filename plain"             "$(url_filename 'https://h/f.zip')" 'f.zip'
expect_fail_fn "filename none for bare host" url_filename 'https://h/'
expect_fail_fn "filename none for dot"       url_filename 'https://h/.'

# --- url_is_direct ----------------------------------------------------------
assert_direct() { # label url expected(0=direct, 1=media)
    local label=$1 url=$2 want=$3
    local got=1
    url_is_direct "$url" && got=0
    if (( got == want )); then
        ok
    else
        bad "$label"
    fi
}

assert_direct "tgz direct"    'https://h/f.tgz'      0
assert_direct "tar.gz direct" 'https://h/f.tar.gz'   0
assert_direct "zip direct"    'https://h/f.zip'      0
assert_direct "jpg direct"    'https://h/f.jpg'      0
assert_direct "torrent direct" 'https://h/f.torrent' 0
assert_direct "magnet direct" 'magnet:?xt=urn:btih:abc' 0

audio=0
assert_direct "mp4 direct in video mode" 'https://h/f.mp4' 0
audio=1
assert_direct "mp4 media in audio mode"  'https://h/f.mp4' 1

audio=0
assert_direct "bare page is media" 'https://h/page'   1
assert_direct "html is media"      'https://h/f.html' 1
assert_direct "txt is media"       'https://h/f.txt'  1

# --- ui_run_progress hides zero-progress phases ------------------------------
direct_ok=0 direct_fail=0 media_ok=0 media_fail=0 img_ok=0 img_fail=0
direct=() media=(u) img_urls=()
quiet=0
expect_eq "progress hides 0-done phases" "$(ui_run_progress)" ''
media_ok=1
expect_eq "progress prints after completed work" "$(ui_run_progress)" '  Run  1/1'
media_fail=1
expect_eq "progress appends failure count" "$(ui_run_progress)" '  Run  2/1 · 1 failed'

# --- yt_bar capitalizes yt-dlp's lowercase log tags --------------------------
expect_eq "yt_bar capitalizes download tag" \
    "$(printf '[download] Downloading item 3 of 30\n' | yt_bar)" \
    '[Download] Downloading item 3 of 30'
expect_eq "yt_bar capitalizes extractor tag" \
    "$(printf '[generic] JCaQ4iFwwlzFD: Downloading webpage\n' | yt_bar)" \
    '[Generic] JCaQ4iFwwlzFD: Downloading webpage'
expect_eq "yt_bar keeps capitalized tags" \
    "$(printf '[Metadata] Adding metadata to file\n' | yt_bar)" \
    '[Metadata] Adding metadata to file'
expect_eq "yt_bar capitalizes every line" \
    "$(printf '[download] x\n[info] y\n' | yt_bar)" \
    '[Download] x
[Info] y'

# --- impersonation target resolution -----------------------------------------
imp_list='Chrome-133    Macos-15  curl_cffi
Chrome-136    Macos-15  curl_cffi
Chrome-150    Macos-26  curl_cffi
Chrome-152    Windows-10 curl_cffi
Safari-17.2   Ios-17.2  curl_cffi'
expect_eq "imp: newest native chrome" "$(imp_resolve_target "$imp_list" chrome)" 'Chrome-136'
expect_eq "imp: safari family"        "$(imp_resolve_target "$imp_list" safari)" 'Safari-17.2'
expect_eq "imp: exact version"        "$(imp_resolve_target "$imp_list" chrome-133)" 'Chrome-133'
expect_eq "imp: exact newer version"  "$(imp_resolve_target "$imp_list" chrome-150)" 'Chrome-150'
expect_fail_fn "imp: unknown family"  imp_resolve_target "$imp_list" firefox
expect_fail_fn "imp: unavailable rows" \
    imp_resolve_target 'Chrome      -    curl_cffi (unavailable)' chrome
expect_eq "imp: bare target" \
    "$(imp_resolve_target 'Chrome      -    curl_cffi' chrome)" 'Chrome'
expect_fail_fn "imp: empty list"      imp_resolve_target '' chrome

printf '\n%d passed, %d failed\n' "$pass" "$fail"
(( fail == 0 )) || exit 1
