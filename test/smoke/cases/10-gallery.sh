# shellcheck shell=bash
# shellcheck disable=SC2154

# gallery-dl routing and output modes.

# --- gallery-dl routing -----------------------------------------------------
if run --help && grep -q -- '--gallery' "$out"; then
    ok
else
    bad "--help should document --gallery"
fi

run -n 'https://gofile.io/d/abc123'
if called gallery-dl && ! called yt-dlp && ! called aria2c \
    && arg_is '--no-colors' && arg_is '-D' && arg_is "$VDL_SAVE_DIR"; then
    ok
else
    bad "known gallery hosts should route to gallery-dl without invoking yt-dlp"
fi

export FAKE_GALLERY_NOISY=yes
run -n --gallery 'https://example.com/watch?v=abc'
unset FAKE_GALLERY_NOISY
if grep -q 'GALLERY OUTPUT' "$out" && grep -q 'GALLERY PROGRESS' "$err"; then
    ok
else
    bad "gallery-dl output should pass through in normal mode"
fi

export FAKE_GALLERY_NOISY=yes
run -n --quiet --gallery 'https://example.com/watch?v=abc'
unset FAKE_GALLERY_NOISY
if ! grep -q 'GALLERY OUTPUT' "$out" && grep -q 'GALLERY PROGRESS' "$err"; then
    ok
else
    bad "--quiet should silence gallery-dl stdout but keep stderr"
fi

run -n --gallery 'https://example.com/watch?v=abc'
if called gallery-dl && ! called yt-dlp \
    && arg_is 'https://example.com/watch?v=abc'; then
    ok
else
    bad "--gallery should send non-direct URLs to gallery-dl"
fi

export VDL_GALLERY=1
run -n 'https://example.com/watch?v=abc'
unset VDL_GALLERY
if called gallery-dl && ! called yt-dlp; then
    ok
else
    bad "VDL_GALLERY=1 should enable gallery mode"
fi

gconf=$tmp/gallerycfg
mkdir -p "$gconf"
printf 'GALLERY=1\n' > "$gconf/config"
export VDL_CONFIG_DIR=$gconf
run -n 'https://example.com/watch?v=abc'
unset VDL_CONFIG_DIR
if called gallery-dl && ! called yt-dlp; then
    ok
else
    bad "GALLERY=1 in the config file should enable gallery mode"
fi

