#!/usr/bin/env bash
# shellcheck shell=bash
# Integration tests for vdl against the REAL yt-dlp/aria2c/ffmpeg, served
# from a local HTTP fixture (no internet access needed).
#
# Run: bash test/integration.sh
# Requirements: bash, python3, yt-dlp, aria2c, ffmpeg, curl; zip optional.

set -u

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
tmp=$(mktemp -d)
trap 'kill ${srv:-0} 2>/dev/null || true; rm -rf "$tmp"' EXIT

pass=0
fail=0

ok()  { pass=$((pass + 1)); }
bad() { fail=$((fail + 1)); printf 'FAIL: %s\n' "$*" >&2; }

check() { # label condition...
    local label=$1
    shift
    if "$@"; then ok; else bad "$label"; fi
}

# --- fixture ----------------------------------------------------------------
mkdir -p "$tmp/srv/srv" "$tmp/home" "$tmp/fakebin"
for f in a b; do head -c 40000 /dev/urandom > "$tmp/srv/$f.iso"; done
head -c 262144 /dev/urandom > "$tmp/srv/big.iso"
head -c 30000 /dev/urandom > "$tmp/srv/srv/pic.webp"
for f in v a b; do
    ffmpeg -loglevel error -f lavfi -i testsrc=duration=1:size=128x128:rate=10 \
        -pix_fmt yuv420p "$tmp/srv/srv/$f.mp4"
done
cat > "$tmp/srv/list.html" <<'EOF'
<html><head><title>My List</title></head>
<body><video src="srv/a.mp4"></video><video src="srv/b.mp4"></video></body></html>
EOF
cat > "$tmp/srv/alb.html" <<'EOF'
<html><head><title>My Album</title></head>
<body><video src="srv/v.mp4"></video><img src='srv/thumb/pic.webp'></body></html>
EOF
cat > "$tmp/srv/photos.html" <<'EOF'
<html><head><title>Photos</title></head><body><img src='srv/thumb/pic.webp'></body></html>
EOF
cat > "$tmp/fakebin/aria2c" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
chmod +x "$tmp/fakebin/aria2c"

# zip shim when the real zip command is missing
if ! command -v zip >/dev/null 2>&1; then
    cat > "$tmp/fakebin/zip" <<'EOF'
#!/usr/bin/env bash
seen=0; declare -a rest=()
for a in "$@"; do
    if [[ $seen == 1 ]]; then rest+=("$a"); elif [[ $a == -- ]]; then seen=1; fi
done
python3 -m zipfile -c "${rest[0]}" "${rest[@]:1}"
EOF
    chmod +x "$tmp/fakebin/zip"
fi

# random free port so parallel/leftover servers cannot collide
port=$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1]); s.close()')
python3 -m http.server "$port" --bind 127.0.0.1 --directory "$tmp/srv" >/dev/null 2>&1 &
srv=$!
sleep 0.5

export HOME="$tmp/home" NO_COLOR=1
B="http://127.0.0.1:$port"
REAL="/usr/bin:/bin"
DL="$tmp/home/Downloads/vdl"

run_vdl() { PATH="$REAL" bash "$root/bin/vdl" "$@" >/dev/null 2>&1; }

# --- 1. multiple direct files ----------------------------------------------
run_vdl -n --no-impersonate "$B/a.iso" "$B/b.iso"; rc=$?
check "multi-direct rc"  test $rc -eq 0
check "a.iso exists"     test -f "$DL/a.iso"
check "b.iso exists"     test -f "$DL/b.iso"

# --- 2. playlist into a titled folder ---------------------------------------
run_vdl -n --no-impersonate "$B/list.html"; rc=$?
check "playlist rc"      test $rc -eq 0
check "item 1 in folder" test -f "$DL/My List/1 - My List (1) [list-1].mp4"
check "item 2 in folder" test -f "$DL/My List/2 - My List (2) [list-2].mp4"

# --- 3. --images: video finishes before the page scan -----------------------
rm -rf "$DL"
PATH="$REAL" bash "$root/bin/vdl" -n --no-impersonate --images "$B/alb.html" >"$tmp/images.log" 2>&1; rc=$?
check "images rc" test $rc -eq 0
vline=$(grep -an '\[ok\].*alb.html' "$tmp/images.log" | head -1 | cut -d: -f1)
sline=$(grep -an 'Scanning page' "$tmp/images.log" | head -1 | cut -d: -f1)
check "video before scan" test -n "$vline" -a -n "$sline" -a "$vline" -lt "$sline"
check "photo in album folder" test -f "$DL/My Album/pic.webp"

# --- 4. image-only page -----------------------------------------------------
rm -rf "$DL"
run_vdl -n --no-impersonate --images "$B/photos.html"; rc=$?
check "image-only rc" test $rc -eq 0
check "image-only photo" test -f "$DL/Photos/pic.webp"

# --- 5. aria2c failure falls back to real yt-dlp -----------------------------
rm -rf "$DL"
PATH="$tmp/fakebin:$REAL" bash "$root/bin/vdl" -n --no-impersonate "$B/big.iso" >/dev/null 2>&1; rc=$?
size=$(stat -c %s "$DL/big.iso" 2>/dev/null || printf '0')
check "fallback rc" test $rc -eq 0
check "fallback size" test "$size" -eq 262144

# --- 6. --name and --output -------------------------------------------------
rm -rf "$DL"
run_vdl -n --no-impersonate --name myvid "$B/srv/v.mp4"; rc=$?
check "name rc"   test $rc -eq 0
check "name file" test -f "$DL/myvid.mp4"
run_vdl -n --no-impersonate --output "$tmp/exact/movie.iso" "$B/a.iso"; rc=$?
check "output rc"   test $rc -eq 0
check "output file" test -f "$tmp/exact/movie.iso"

# --- 7. --zip ---------------------------------------------------------------
rm -rf "$DL"
PATH="$tmp/fakebin:$REAL" bash "$root/bin/vdl" -n --zip=run.zip "$B/a.iso" >/dev/null 2>&1; rc=$?
check "zip rc"    test $rc -eq 0
check "zip file"  test -f "$DL/run.zip"
check "zip content" sh -c "python3 -m zipfile -l '$DL/run.zip' 2>/dev/null | grep -q a.iso"

# --- 8. multi-line paste ----------------------------------------------------
rm -rf "$DL"
paste_block="http://127.0.0.1:$port/a.iso
# noise
http://127.0.0.1:$port/b.iso"
PATH="$REAL" bash "$root/bin/vdl" -n "$paste_block" >/dev/null 2>&1; rc=$?
check "paste rc" test $rc -eq 0
check "paste a"  test -f "$DL/a.iso"
check "paste b"  test -f "$DL/b.iso"

# --- 9. HTML image extraction (python parser) --------------------------------
cat > "$tmp/parser.html" <<'EOF'
<html><body>
<img src="https://c.example/a.jpg?v=1">
<img data-src='//c.example/b.png'>
<img data-rotate-src="https://c.example/thumbs/x.jpg">
<img src="data:image/png;base64,AAAA">
<img
  data-src="https://c.example/multi.jpg">
<img src="https://c.example/n&amp;m.webp">
</body></html>
EOF
python3 "$root/lib/vdl/scrape.py" "$tmp/parser.html" > "$tmp/parser.out"
check "parser a.jpg"     grep -qxF 'https://c.example/a.jpg?v=1' "$tmp/parser.out"
check "parser b.png"     grep -qxF '//c.example/b.png' "$tmp/parser.out"
check "parser no thumb"  sh -c "! grep -q 'thumbs' '$tmp/parser.out'"
check "parser no data"   sh -c "! grep -q 'base64' '$tmp/parser.out'"
check "parser multiline" grep -qxF 'https://c.example/multi.jpg' "$tmp/parser.out"
check "parser entity"    grep -qxF 'https://c.example/n&m.webp' "$tmp/parser.out"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
(( fail == 0 )) || exit 1
