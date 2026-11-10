# shellcheck shell=bash
# shellcheck disable=SC2154

# gallery-dl fallback and availability checks.

export FAKE_YTDLP_UNSUPPORTED=yes
run -n 'https://example.com/watch?v=abc'
rc=$?
unset FAKE_YTDLP_UNSUPPORTED
if [[ $rc -eq 0 ]] && called gallery-dl \
    && arg_is 'https://example.com/watch?v=abc' \
    && grep -q 'Fallback Downloads via gallery-dl' "$out"; then
    ok
else
    bad "yt-dlp Unsupported URL failures should fall back to gallery-dl"
fi

export FAKE_YTDLP_UNSUPPORTED=yes FAKE_GALLERY_FAIL=yes
run -n 'https://example.com/watch?v=abc'
rc=$?
unset FAKE_YTDLP_UNSUPPORTED FAKE_GALLERY_FAIL
if [[ $rc -ne 0 ]] && grep -q 'Gallery' "$out" && grep -q '1 Failed' "$out"; then
    ok
else
    bad "a failed gallery-dl fallback should be reported and fail the run"
fi

export FAKE_YTDLP_FAIL=forbidden
run -n 'https://example.com/watch?v=abc'
rc=$?
unset FAKE_YTDLP_FAIL
if [[ $rc -ne 0 ]] && ! called gallery-dl; then
    ok
else
    bad "network/auth failures must not trigger the gallery-dl fallback"
fi

run -n --gallery --audio 'https://example.com/watch?v=abc'
rc=$?
if [[ $rc -eq 2 ]] && grep -q 'cannot be combined' "$err" \
    && ! called gallery-dl; then
    ok
else
    bad "--gallery with --audio should exit 2 before downloading"
fi

mv "$fakebin/gallery-dl" "$tmp/gallery-dl.bak"
run -n 'https://gofile.io/d/abc123'
rc=$?
mv "$tmp/gallery-dl.bak" "$fakebin/gallery-dl"
if [[ $rc -eq 0 ]] && ! called gallery-dl && called yt-dlp \
    && grep -q 'gallery-dl not installed' "$err"; then
    ok
else
    bad "known gallery hosts should stay on yt-dlp when gallery-dl is absent"
fi

mv "$fakebin/gallery-dl" "$tmp/gallery-dl.bak"
run -n --gallery 'https://example.com/watch?v=abc'
rc=$?
mv "$tmp/gallery-dl.bak" "$fakebin/gallery-dl"
if [[ $rc -eq 1 ]] && grep -q 'gallery-dl is required' "$err"; then
    ok
else
    bad "--gallery without gallery-dl should exit 1 with an install hint"
fi

mv "$fakebin/gallery-dl" "$tmp/gallery-dl.bak"
run -n --gallery 'https://example.com/file.iso'
rc=$?
mv "$tmp/gallery-dl.bak" "$fakebin/gallery-dl"
if [[ $rc -eq 0 ]] && called aria2c && ! called gallery-dl; then
    ok
else
    bad "--gallery with only direct URLs should not require gallery-dl"
fi

run -n --gallery 'https://example.com/file.iso' 'https://example.com/watch?v=abc'
if called aria2c && called gallery-dl && ! called yt-dlp; then
    ok
else
    bad "--gallery should keep direct files on aria2c and route the rest to gallery-dl"
fi

run -n --dry-run --gallery 'https://example.com/watch?v=abc'
if grep -q 'dry-run' "$out" && ! called gallery-dl && ! called yt-dlp; then
    ok
else
    bad "--dry-run --gallery should not invoke downloaders"
fi

