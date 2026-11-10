# shellcheck shell=bash
# shellcheck disable=SC2154,SC2329

# Shared smoke-test environment. The runner sources this once before any
# case file, so every case sees the same temp dirs, stubs and helpers.

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
unset VDL_BROWSER VDL_QUALITY VDL_IMPERSONATE VDL_GALLERY VDL_CONFIG WAYLAND_DISPLAY DISPLAY 2>/dev/null || true
unset XDG_CONFIG_HOME XDG_DATA_HOME XDG_DOWNLOAD_DIR XDG_CACHE_HOME 2>/dev/null || true

# Every stubbed command is the same dispatcher; it decides what to do from
# the name it was invoked as (${0##*/}).
for cmd in yt-dlp aria2c ffmpeg wl-paste curl zip vivaldi gallery-dl; do
    cp "$smoke_dir/stub.sh" "$fakebin/$cmd"
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
