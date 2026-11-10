# shellcheck shell=bash
# shellcheck disable=SC2154

# yt-dlp impersonation target selection.

# --- impersonation must follow yt-dlp's capability list ---------------------
if run -n 'https://example.com/watch?v=abc' && ! arg_has '--impersonate'; then
    ok
else
    bad "--impersonate must not be used when yt-dlp reports no available target"
fi

export VDL_IMPERSONATE=chrome
run -n 'https://example.com/watch?v=abc'
rc=$?
unset VDL_IMPERSONATE
if [[ $rc -eq 0 ]] && ! arg_has '--impersonate' \
    && grep -q "yt-dlp cannot impersonate 'chrome'" "$err"; then
    ok
else
    bad "explicit --impersonate target should be skipped with a warning"
fi

export FAKE_IMPERSONATE=yes
run -n 'https://example.com/watch?v=abc'
rc=$?
unset FAKE_IMPERSONATE
if [[ $rc -eq 0 ]] && arg_is '--impersonate' && arg_is Chrome; then
    ok
else
    bad "impersonation should be enabled when yt-dlp reports chrome available"
fi

export FAKE_IMPERSONATE=versioned
run -n 'https://example.com/watch?v=abc'
rc=$?
unset FAKE_IMPERSONATE
if [[ $rc -eq 0 ]] && arg_is '--impersonate' && arg_is 'Chrome-136' \
    && ! arg_has 'Chrome-133' && ! arg_has 'Chrome-150' && ! arg_has 'Chrome-152'; then
    ok
else
    bad "auto impersonation should pick the newest native versioned target"
fi

