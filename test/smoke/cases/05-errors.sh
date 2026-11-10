# shellcheck shell=bash
# shellcheck disable=SC2154

# Cloudflare / 403 browser-session hints.

# --- Cloudflare challenge hint -----------------------------------------------
export FAKE_YTDLP_FAIL=cloudflare
run -n 'https://example.com/watch?v=abc'
rc=$?
unset FAKE_YTDLP_FAIL
if [[ $rc -ne 0 ]] && grep -qi 'cloudflare' "$err" && grep -q 'open the page' "$err"; then
    ok
else
    bad "a Cloudflare challenge should produce the browser-session hint"
fi

export FAKE_YTDLP_FAIL=forbidden
run -n 'https://example.com/watch?v=abc'
rc=$?
unset FAKE_YTDLP_FAIL
if [[ $rc -ne 0 ]] && grep -q 'open the page' "$err"; then
    ok
else
    bad "a plain 403 Forbidden should also produce the browser-session hint"
fi

