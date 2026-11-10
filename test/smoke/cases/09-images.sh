# shellcheck shell=bash
# shellcheck disable=SC2154

# Embedded image scanning on generic pages.

# --- embedded images on generic pages --------------------------------------
export FAKE_GENERIC_PAGE=yes
run -n --no-impersonate --images 'https://example.com/watch?v=abc'
unset FAKE_GENERIC_PAGE
if arg_is 'https://cdn.example.com/album/pic1.jpg' \
    && arg_is 'https://cdn.example.com/album/pic2.png' \
    && ! arg_has 'favicon' && ! arg_has 'logo' \
    && ! arg_has 'avatar' && ! arg_has 'grid1' \
    && ! arg_has 'video1' && ! arg_has 'side' \
    && arg_is '-Z' && arg_is "$VDL_SAVE_DIR/Test Album" \
    && grep -q 'Scanning page' "$err" \
    && called aria2c; then
    ok
else
    bad "generic pages should queue album images but skip favicons/logos/covers/sidebar"
fi

run -n --no-impersonate 'https://example.com/watch?v=abc'
if ! called curl && ! called aria2c; then
    ok
else
    bad "image scanning should be off unless --images is given"
fi

