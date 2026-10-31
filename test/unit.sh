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

printf '\n%d passed, %d failed\n' "$pass" "$fail"
(( fail == 0 )) || exit 1
