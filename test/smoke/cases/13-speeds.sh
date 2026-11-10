# shellcheck shell=bash
# shellcheck disable=SC2154

# Speed limit conversion and forwarding.

# --- speed limits ----------------------------------------------------------
run -n --max-speed 1M 'https://example.com/file.iso'
if arg_is '--max-overall-download-limit=1048576' \
    && ! arg_has 'max-download-limit'; then
    ok
else
    bad "--max-speed should set aria2c's overall download limit in bytes"
fi

run -n --limit-speed 500K 'https://example.com/file.iso'
if arg_is '--max-download-limit=512000' \
    && ! arg_has 'max-overall-download-limit'; then
    ok
else
    bad "--limit-speed should set aria2c's per-download limit in bytes"
fi

run -n --max-speed 1.5M --limit-speed 1G 'https://example.com/file.iso'
if arg_is '--max-overall-download-limit=1572864' \
    && arg_is '--max-download-limit=1073741824'; then
    ok
else
    bad "decimal and G speed limits should be converted to bytes"
fi

run -n --no-aria --max-speed 2M 'https://example.com/watch?v=abc'
if arg_is '--limit-rate' && arg_is '2097152' \
    && ! arg_has '--throttled-rate'; then
    ok
else
    bad "--max-speed should use yt-dlp --limit-rate"
fi

run -n --max-speed 2M 'https://example.com/watch?v=abc'
if arg_is '--limit-rate' && arg_is '2097152' \
    && arg_has '--max-overall-download-limit=2097152'; then
    ok
else
    bad "media downloads should apply the overall limit to aria2c as well"
fi

run -n --no-aria --max-speed 2M --limit-speed 500K 'https://example.com/watch?v=abc'
if arg_is '--limit-rate' && arg_is '512000'; then
    ok
else
    bad "yt-dlp should use the stricter of the two speed limits"
fi

run -n --no-aria --max-speed nonsense 'https://example.com/watch?v=abc'
rc=$?
if [[ $rc -eq 2 ]] && grep -q 'Invalid speed' "$err"; then
    ok
else
    bad "invalid speed should exit 2 even on native-only paths"
fi

