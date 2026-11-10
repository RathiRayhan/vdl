# shellcheck shell=bash
# shellcheck disable=SC2154

# Zip archiving.

# --- zip archive ------------------------------------------------------------
export FAKE_ARIA_DUP=yes
run -n --zip 'https://example.com/zip-a.iso'
unset FAKE_ARIA_DUP
if called zip && grep -q 'Archived' "$err" \
    && ls "$VDL_SAVE_DIR"/vdl-*.zip >/dev/null 2>&1; then
    ok
else
    bad "--zip should archive this run's files with an automatic name"
fi

export FAKE_ARIA_DUP=yes
run -n --zip=my-batch.zip 'https://example.com/zip-b.iso'
unset FAKE_ARIA_DUP
if called zip && [[ -f $VDL_SAVE_DIR/my-batch.zip ]] \
    && grep -q 'my-batch.zip' "$err"; then
    ok
else
    bad "--zip=NAME.zip should archive under the given name"
fi

rm -f "$VDL_SAVE_DIR"/*.iso "$VDL_SAVE_DIR"/*.zip
run -n --zip 'https://example.com/zip-c.iso'
if ! called zip && grep -q 'nothing to archive' "$err"; then
    ok
else
    bad "--zip with no downloaded files should skip with a note"
fi

