# shellcheck shell=bash
# shellcheck disable=SC2154

# Collision policy for direct files.

coll_dir=$tmp/collision_dl
mkdir -p "$coll_dir"
printf 'old-content\n' > "$coll_dir/file.iso"

# --- rename ----------------------------------------------------------------
export FAKE_YTDLP_CREATE=yes
run -n --no-aria --no-impersonate --on-collision rename \
    --download-dir "$coll_dir" 'https://example.com/file.iso'
rc=$?
unset FAKE_YTDLP_CREATE
if [[ $rc -eq 0 ]] \
    && [[ $(cat "$coll_dir/file.iso") == 'old-content' ]] \
    && [[ -f $coll_dir/file.1.iso ]] \
    && grep -q 'Direct.*: 1 OK, 0 Failed' "$out"; then
    ok
else
    bad "--on-collision rename should keep the old file and download file.1.iso"
fi

# --- fail ------------------------------------------------------------------
run -n --on-collision fail --download-dir "$coll_dir" 'https://example.com/file.iso'
rc=$?
if [[ $rc -eq 2 ]] && grep -q 'Destination already exists' "$err"; then
    ok
else
    bad "--on-collision fail should exit 2 before downloading an existing target"
fi

# --- overwrite via aria2c --------------------------------------------------
run -n --on-collision overwrite --download-dir "$coll_dir" 'https://example.com/file.iso'
rc=$?
if [[ $rc -eq 0 ]] \
    && arg_is '--allow-overwrite=true' \
    && arg_is '--auto-file-renaming=false'; then
    ok
else
    bad "--on-collision overwrite should pass overwrite flags to aria2c"
fi

# --- overwrite via yt-dlp --------------------------------------------------
run -n --no-aria --no-impersonate --on-collision overwrite \
    --download-dir "$coll_dir" 'https://example.com/file.iso'
rc=$?
if [[ $rc -eq 0 ]] && arg_is '--force-overwrites' && ! arg_is '--no-overwrites'; then
    ok
else
    bad "--on-collision overwrite should use yt-dlp --force-overwrites"
fi

# --- invalid policy --------------------------------------------------------
run -n --on-collision sometimes 'https://example.com/file.iso'
rc=$?
if [[ $rc -eq 2 ]] && grep -q 'Invalid collision policy' "$err"; then
    ok
else
    bad "an invalid --on-collision value should exit 2"
fi
