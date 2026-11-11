# shellcheck shell=bash
# shellcheck disable=SC2154

# aria2c fallback cleanup and deduplication.

# --- aria fallback removes incomplete partials -----------------------------
mkdir -p "$VDL_SAVE_DIR"
printf 'partial' > "$VDL_SAVE_DIR/bad.iso"
: > "$VDL_SAVE_DIR/bad.iso.aria2"
printf 'complete' > "$VDL_SAVE_DIR/good.iso"
export FAKE_ARIA_FAIL=yes
run -n 'https://example.com/good.iso' 'https://example.com/bad.iso' \
    'https://example.com/missing.iso'
rc=$?
unset FAKE_ARIA_FAIL
if [[ $rc -eq 0 ]] \
    && [[ ! -e $VDL_SAVE_DIR/bad.iso ]] \
    && [[ ! -e $VDL_SAVE_DIR/bad.iso.aria2 ]] \
    && [[ $(cat "$VDL_SAVE_DIR/good.iso") == complete ]] \
    && [[ $(grep -cxF 'ARG https://example.com/bad.iso' "$log") -eq 2 ]] \
    && [[ $(grep -cxF 'ARG https://example.com/good.iso' "$log") -eq 0 ]] \
    && [[ $(grep -cxF 'ARG https://example.com/missing.iso' "$log") -eq 2 ]] \
    && grep -q 'Direct.*: 2 OK, 0 Failed, 1 Skipped' "$out"; then
    ok
else
    bad "aria2c fallback should remove partials and retry only failed direct files"
fi

# --- dedupe removes identical files from this run ---------------------------
export FAKE_ARIA_DUP=yes
run -n --dedupe 'https://example.com/dup-a.iso' 'https://example.com/dup-b.iso'
unset FAKE_ARIA_DUP
if [[ ( -e $VDL_SAVE_DIR/dup-a.iso || -e $VDL_SAVE_DIR/dup-b.iso ) ]] \
    && [[ ! ( -e $VDL_SAVE_DIR/dup-a.iso && -e $VDL_SAVE_DIR/dup-b.iso ) ]] \
    && grep -q 'Removed duplicate' "$err"; then
    ok
else
    bad "--dedupe should keep one copy of identical files from this run"
fi

export FAKE_ARIA_DUP=yes
run -n 'https://example.com/dup-c.iso' 'https://example.com/dup-d.iso'
unset FAKE_ARIA_DUP
if [[ -e $VDL_SAVE_DIR/dup-c.iso && -e $VDL_SAVE_DIR/dup-d.iso ]]; then
    ok
else
    bad "without --dedupe both copies should remain"
fi

