#!/usr/bin/env bash
# shellcheck shell=bash
# Smoke tests for vdl. Uses stub yt-dlp / aria2c / ffmpeg / wl-paste binaries,
# so it needs nothing but bash and coreutils.
#
# Run: bash test/smoke.sh

set -uo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

home=$tmp/home
fakebin=$tmp/fakebin
log=$tmp/calls.log
out=$tmp/out
err=$tmp/err
mkdir -p "$home" "$fakebin"

export HOME=$home
export VDL_SAVE_DIR=$tmp/dl
export FAKE_LOG=$log
export NO_COLOR=1
unset VDL_BROWSER VDL_QUALITY VDL_IMPERSONATE VDL_CONFIG WAYLAND_DISPLAY DISPLAY 2>/dev/null || true
unset XDG_CONFIG_HOME XDG_DATA_HOME XDG_DOWNLOAD_DIR 2>/dev/null || true

for cmd in yt-dlp aria2c ffmpeg wl-paste; do
    cat > "$fakebin/$cmd" <<'STUB'
#!/usr/bin/env bash
# Answer yt-dlp's capability probe without logging it as a download.
if [[ ${0##*/} == yt-dlp && " $* " == *" --list-impersonate-targets "* ]]; then
    printf '[info] Available impersonate targets\n'
    printf 'Client    OS   Source\n'
    printf -- '----------------------------\n'
    if [[ ${FAKE_IMPERSONATE:-} == yes ]]; then
        printf 'Chrome      -    curl_cffi\n'
    else
        printf 'Chrome      -    curl_cffi (unavailable)\n'
    fi
    exit 0
fi
printf 'CALL %s\n' "${0##*/}" >> "$FAKE_LOG"
for a in "$@"; do
    printf 'ARG %s\n' "$a" >> "$FAKE_LOG"
done
if [[ ${0##*/} == aria2c && ${FAKE_ARIA_FAIL:-} == yes ]]; then
    exit 1
fi
if [[ ${0##*/} == wl-paste ]]; then
    printf 'https://example.com/from-clipboard\n'
fi
exit 0
STUB
    chmod +x "$fakebin/$cmd"
done

pass=0
fail=0

ok() {
    pass=$((pass + 1))
}

bad() {
    fail=$((fail + 1))
    printf 'FAIL: %s\n' "$*" >&2
    [[ -f $log ]] && sed 's/^/    /' "$log" >&2
    [[ -f $err ]] && sed 's/^/    /' "$err" >&2
}

run() {
    : > "$log"
    : > "$out"
    : > "$err"
    PATH="$fakebin:/usr/bin:/bin" bash "$root/bin/vdl" "$@" >"$out" 2>"$err"
}

arg_is() { grep -qxF "ARG $1" "$log"; }
arg_has() { grep -qF -- "$1" "$log"; }
called() { grep -qxF "CALL $1" "$log"; }

# --- help and version -------------------------------------------------------
if run --help && grep -q 'Usage:' "$out"; then ok; else bad "vdl --help"; fi
if run --version && grep -q '^vdl ' "$out"; then ok; else bad "vdl --version"; fi

# --- media routing and quality cap -----------------------------------------
if run --no-impersonate -n -q 720 'https://example.com/watch?v=abc' \
    && called yt-dlp && arg_has 'height<=720' && ! called aria2c \
    && arg_is '--output-na-placeholder' && arg_is '.'; then
    ok
else
    bad "media URL should use yt-dlp with height<=720"
fi
if ! arg_has '--cookies-from-browser'; then ok; else bad "-n should disable cookies"; fi
if ! arg_has '--impersonate'; then ok; else bad "--no-impersonate should be honoured"; fi

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
if [[ $rc -eq 0 ]] && arg_is '--impersonate' && arg_is chrome; then
    ok
else
    bad "impersonation should be enabled when yt-dlp reports chrome available"
fi

# --- quality aliases -------------------------------------------------------
run -n -q 4k 'https://example.com/watch?v=abc'
if arg_has 'height<=2160'; then ok; else bad "4k should map to 2160"; fi
run -n -q 720p 'https://example.com/watch?v=abc'
if arg_has 'height<=720'; then ok; else bad "720p should map to 720"; fi

# --- direct file via aria2c ------------------------------------------------
if run -n 'https://example.com/file.iso' \
    && called aria2c && arg_is -x && arg_is 16; then
    ok
else
    bad "direct .iso should use aria2c"
fi

# --- direct file via yt-dlp when aria is disabled --------------------------
if run -n --no-aria 'https://example.com/file.iso' \
    && called yt-dlp && ! called aria2c \
    && arg_is file.iso; then
    ok
else
    bad "--no-aria should send direct files to yt-dlp with their real name"
fi

# --- header propagation ----------------------------------------------------
run -n --referer=https://ref.example --user-agent=UA --proxy=http://127.0.0.1:9 \
    'https://example.com/file.iso'
if arg_is '--referer=https://ref.example' && arg_is '--user-agent=UA' \
    && arg_is '--all-proxy=http://127.0.0.1:9'; then
    ok
else
    bad "headers/proxy should be forwarded to aria2c"
fi

# --- audio mode ------------------------------------------------------------
if run -n -a 'https://example.com/watch?v=abc' \
    && arg_has '--audio-format' && arg_is mp3 \
    && arg_has "$VDL_SAVE_DIR/audio"; then
    ok
else
    bad "audio mode should extract MP3 into <save>/audio"
fi

# --- batch file ------------------------------------------------------------
printf 'https://a.example/1\r\n\r\n# comment\r\nhttps://a.example/2\r\nhttps://a.example/1\r\n' \
    > "$home/links.txt"
run -n "$home/links.txt"
rc=$?
n1=$(grep -cxF 'ARG https://a.example/1' "$log")
n2=$(grep -cxF 'ARG https://a.example/2' "$log")
if [[ $rc -eq 0 && $n1 -eq 1 && $n2 -eq 1 ]] && ! grep -q $'\r' "$log"; then
    ok
else
    bad "batch file should deduplicate and strip CR (got $n1/$n2)"
fi

# --- unknown flag with a .txt value is not a batch file --------------------
: > "$home/archive.txt"
run -n --download-archive "$home/archive.txt" 'https://example.com/watch?v=x'
if arg_is '--download-archive' && arg_is "$home/archive.txt" \
    && ! grep -q 'Batch' "$out"; then
    ok
else
    bad "--download-archive value must pass through, not be read as a batch file"
fi

# --- forwarded option values keep their position ---------------------------
new_archive=$home/new-archive.txt
run -n --download-archive "$new_archive" 'https://example.com/watch?v=x' \
    --merge-output-format mkv
dl_next=$(awk '/^ARG --download-archive$/{getline; val=$0} END{print val}' "$log")
mof_next=$(awk '/^ARG --merge-output-format$/{getline; val=$0} END{print val}' "$log")
if [[ $dl_next == "ARG $new_archive" && $mof_next == 'ARG mkv' ]] \
    && arg_is 'https://example.com/watch?v=x'; then
    ok
else
    bad "forwarded options must stay adjacent to their values (archive=$dl_next, format=$mof_next)"
fi

# --- clipboard fallback ----------------------------------------------------
export WAYLAND_DISPLAY=wayland-0
run -n
rc=$?
unset WAYLAND_DISPLAY
if [[ $rc -eq 0 ]] && arg_is 'https://example.com/from-clipboard'; then
    ok
else
    bad "should read a URL from the clipboard"
fi

# --- validation ------------------------------------------------------------
run -q nope 'https://example.com/watch?v=x'
rc=$?
if (( rc == 2 )); then ok; else bad "invalid quality should exit 2"; fi
run -b netscape 'https://example.com/watch?v=x'
rc=$?
if (( rc == 2 )); then ok; else bad "unknown browser should exit 2"; fi

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
if grep -q -- '--- Summary ---' "$out" && grep -q '\[ok\]' "$out"; then
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
if grep -q '\[fail\]' "$out" && grep -q '\[ok\]' "$out"; then
    ok
else
    bad "UI should mark failed downloads separately from retried ones"
fi

# --- magnet link routing ---------------------------------------------------
if run -n 'magnet:?xt=urn:btih:abc' && called aria2c && ! called yt-dlp; then
    ok
else
    bad "magnet: links should route to aria2c"
fi

# --- .torrent routing ------------------------------------------------------
if run -n 'https://example.com/file.torrent' && called aria2c && ! called yt-dlp; then
    ok
else
    bad ".torrent URLs should route to aria2c"
fi

# --- download-dir override -------------------------------------------------
ddir=$tmp/customdir
if run -n --download-dir "$ddir" 'https://example.com/file.iso' \
    && arg_has "-d" && arg_has "$ddir"; then
    ok
else
    bad "--download-dir should be forwarded to aria2c as -d"
fi

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
    && [[ $(grep -cxF 'ARG https://example.com/good.iso' "$log") -eq 1 ]] \
    && [[ $(grep -cxF 'ARG https://example.com/missing.iso' "$log") -eq 2 ]]; then
    ok
else
    bad "aria2c fallback should remove partials and retry only failed direct files"
fi

# --- aria-opts forwarding --------------------------------------------------
run -n --aria-opts '--check-interval=30 --max-connection-per-server=4' \
    'https://example.com/file.iso'
if arg_is '--check-interval=30' && arg_is '--max-connection-per-server=4'; then
    ok
else
    bad "--aria-opts should be forwarded to aria2c verbatim"
fi

# --- config file -----------------------------------------------------------
confdir=$tmp/cfgtest/.config/vdl
mkdir -p "$confdir"
printf 'QUALITY=480\n' > "$confdir/config"
HOME=$tmp/cfgtest XDG_CONFIG_HOME="$tmp/cfgtest/.config" \
    run -n 'https://example.com/watch?v=abc'
if arg_has 'height<=480'; then
    ok
else
    bad "config file should set default quality"
fi
unset XDG_CONFIG_HOME

# --- 8k quality alias ------------------------------------------------------
run -n -q 8k 'https://example.com/watch?v=abc'
if arg_has 'height<=4320'; then ok; else bad "8k should map to 4320"; fi

# --- installer (now also installs man page) ----------------------------------
prefix=$tmp/prefix
if PATH="$fakebin:/usr/bin:/bin" bash "$root/install.sh" \
    --prefix "$prefix" --shells bash,fish >/dev/null 2>&1 \
    && [[ -x $prefix/bin/vdl ]] \
    && [[ -f "$prefix/share/man/man1/vdl.1" ]] \
    && [[ -f $home/.local/share/bash-completion/completions/vdl ]] \
    && [[ -f $home/.config/fish/completions/vdl.fish ]]; then
    ok
else
    bad "installer should place the command, completions and man page"
fi

if PATH="$fakebin:/usr/bin:/bin" bash "$root/install.sh" \
    --uninstall --prefix "$prefix" >/dev/null 2>&1 \
    && [[ ! -e $prefix/bin/vdl ]] \
    && [[ ! -e $home/.local/share/bash-completion/completions/vdl ]] \
    && [[ ! -e $home/.config/fish/completions/vdl.fish ]]; then
    ok
else
    bad "uninstaller should remove installed files"
fi

printf '\n%d passed, %d failed\n' "$pass" "$fail"
(( fail == 0 ))
