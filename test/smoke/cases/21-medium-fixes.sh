# shellcheck shell=bash
# shellcheck disable=SC2154

# Regression tests for the medium findings: destination accounting,
# duplicate basenames, --name confinement, and zip collision safety.

# --- duplicate direct basenames get distinct destinations -------------------
dup_dir=$tmp/medium_dup
export FAKE_YTDLP_CREATE=yes
run -n --no-aria --no-impersonate --download-dir "$dup_dir" \
    'https://example.com/one/same.iso' 'https://example.com/two/same.iso'
rc=$?
unset FAKE_YTDLP_CREATE
if [[ $rc -eq 0 ]] \
    && [[ -f $dup_dir/same.iso ]] \
    && [[ -f $dup_dir/same.1.iso ]] \
    && grep -q 'Direct.*: 2 OK, 0 Failed' "$out"; then
    ok
else
    bad "duplicate direct basenames should be disambiguated, not skipped"
fi

# --- a pre-existing destination is reported as skipped, not OK --------------
skip_dir=$tmp/medium_skip
mkdir -p "$skip_dir"
printf 'old-content\n' > "$skip_dir/pre.iso"
export FAKE_YTDLP_SKIP=yes
run -n --no-aria --no-impersonate --download-dir "$skip_dir" \
    'https://example.com/pre.iso'
rc=$?
unset FAKE_YTDLP_SKIP
if [[ $rc -eq 0 ]] \
    && [[ $(cat "$skip_dir/pre.iso") == 'old-content' ]] \
    && grep -q 'Direct.*: 0 OK, 0 Failed, 1 Skipped' "$out" \
    && grep -q '^  #  pre.iso$' "$out"; then
    ok
else
    bad "a pre-existing destination must be reported as skipped, not a success"
fi

# --- --name rejects path traversal and option-like names --------------------
for bad_name in '../escaped.iso' '/tmp/escaped.iso' 'sub/file.iso' '..' '.' '-x'; do
    run -n --name "$bad_name" 'https://example.com/file.iso'
    rc=$?
    if [[ $rc -ne 2 ]] || called aria2c || called yt-dlp; then
        bad "--name $bad_name should exit 2 without downloading (got $rc)"
    fi
done
if [[ ! -e $tmp/escaped.iso ]]; then
    ok
else
    bad "--name must not write outside the save directory"
fi

# --- --zip refuses to overwrite a file downloaded in the same run -----------
zip_dup=$tmp/medium_zip_dup
export FAKE_ARIA_DUP=yes
run -n --no-impersonate --download-dir "$zip_dup" --zip=run.zip \
    'https://example.com/run.zip'
rc=$?
unset FAKE_ARIA_DUP
if [[ $rc -ne 0 ]] \
    && [[ $(cat "$zip_dup/run.zip") == 'same-content' ]] \
    && ! called zip \
    && grep -q 'Archive.*: failed' "$out"; then
    ok
else
    bad "--zip must refuse to overwrite a downloaded file with the same name"
fi

# --- a failed zip does not delete the download or an existing target --------
zip_fail=$tmp/medium_zip_fail
mkdir -p "$zip_fail"
printf 'OLD-ARCHIVE\n' > "$zip_fail/out.zip"
export FAKE_ARIA_DUP=yes FAKE_ZIP_FAIL=yes
run -n --no-impersonate --download-dir "$zip_fail" --zip=out.zip \
    'https://example.com/file.iso'
rc=$?
unset FAKE_ARIA_DUP FAKE_ZIP_FAIL
if [[ $rc -ne 0 ]] \
    && [[ -f $zip_fail/file.iso ]] \
    && [[ $(cat "$zip_fail/out.zip") == 'OLD-ARCHIVE' ]] \
    && grep -q 'Archive.*: failed' "$out"; then
    ok
else
    bad "a failed zip must leave the downloads and an existing archive intact"
fi
