# shellcheck shell=bash
# shellcheck disable=SC2154

# Dry-run, quiet mode, per-URL status and summary output.

# --- dry-run ---------------------------------------------------------------
if run -n --dry-run 'https://example.com/file.iso' 'https://example.com/watch?v=x' \
    && grep -q 'dry-run' "$out" \
    && ! called aria2c && ! called yt-dlp; then
    ok
else
    bad "--dry-run should print a plan and not invoke downloaders"
fi

# --- quiet mode ------------------------------------------------------------
run -n --quiet --dry-run 'https://example.com/watch?v=x'
if ! grep -q '== vdl' "$out" && grep -q 'dry-run' "$out"; then
    ok
else
    bad "--quiet should suppress the banner but keep dry-run details"
fi

# --- UI output: status lines and summary ------------------------------------
run -n 'https://example.com/file.iso'
if grep -q -- '--- Summary ---' "$out" && grep -q '✓' "$out"; then
    ok
else
    bad "non-quiet runs should print per-URL status and a summary"
fi

run -n --quiet 'https://example.com/file.iso'
if [[ ! -s $out ]]; then
    ok
else
    bad "--quiet should print nothing to stdout"
fi

export FAKE_ARIA_FAIL=yes
run -n 'magnet:?xt=urn:btih:abc' 'https://example.com/file.iso'
unset FAKE_ARIA_FAIL
if grep -q '✗' "$out" && grep -q '✓' "$out" \
    && grep -q 'Failed' "$out" && grep -q 'aria2c failed' "$out"; then
    ok
else
    bad "UI should mark failed downloads separately and recap them in the summary"
fi

run -n 'https://example.com/a.iso' 'https://example.com/b.iso'
if grep -q 'Run  2/2' "$out"; then
    ok
else
    bad "a run-level progress line should appear after the phases"
fi

run -n 'https://example.com/watch?v=abc'
if grep -q 'Run  1/1' "$out" && ! grep -q 'Run  0/' "$out"; then
    ok
else
    bad "phases with no downloads yet should not print a zero progress line"
fi

