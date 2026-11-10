# shellcheck shell=bash
# shellcheck disable=SC2154

# Browser cookie and User-Agent handling.

# --- browser UA matching -----------------------------------------------------
mkdir -p "$home/.config/vivaldi"
run 'https://example.com/watch?v=abc'
vivaldi_ua='Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/152.0.0.0 Safari/537.36'
if arg_is '--cookies-from-browser' && arg_is '--user-agent' \
    && arg_is "$vivaldi_ua" \
    && ls "$home/.cache/vdl"/ua-vivaldi-* >/dev/null 2>&1; then
    ok
else
    bad "browser cookies should reuse the browser's exact User-Agent"
fi

run --user-agent 'MyBot/1.0' 'https://example.com/watch?v=abc'
if arg_is '--user-agent' && arg_is 'MyBot/1.0' && ! arg_has 'Chrome/152.0.0.0'; then
    ok
else
    bad "an explicit --user-agent should override the browser UA"
fi

run 'https://example.com/watch?v=abc'
if arg_is '--user-agent' && arg_is "$vivaldi_ua" \
    && grep -qxF 'VIVALDI --version' "$log" \
    && ! grep -q 'VIVALDI --headless' "$log"; then
    ok
else
    bad "a cached browser UA should skip the headless probe on later runs"
fi

