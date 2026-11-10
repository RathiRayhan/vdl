# shellcheck shell=bash
# shellcheck disable=SC2154

# Help, version, and argument validation.

# --- help and version -------------------------------------------------------
if run --help && grep -q 'Usage:' "$out"; then ok; else bad "vdl --help"; fi
if run --version && grep -q '^vdl ' "$out"; then ok; else bad "vdl --version"; fi


# --- validation ------------------------------------------------------------
run -q nope 'https://example.com/watch?v=x'
rc=$?
if (( rc == 2 )); then ok; else bad "invalid quality should exit 2"; fi
run -b netscape 'https://example.com/watch?v=x'
rc=$?
if (( rc == 2 )); then ok; else bad "unknown browser should exit 2"; fi

