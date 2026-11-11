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
trap 'kill ${srv:-0} ${rsrv:-0} 2>/dev/null || true; [[ -n ${VDL_INT_KEEP:-} ]] || rm -rf "$tmp"' EXIT

pass=0
fail=0

ok()  { pass=$((pass + 1)); }
bad() { fail=$((fail + 1)); printf 'FAIL: %s\n' "$*" >&2; tail -n 30 "$LOG" 2>/dev/null | sed 's/^/    /' >&2; }

check() { # label condition...
    local label=$1
    shift
    if "$@"; then ok; else bad "$label"; fi
}

LOG="$tmp/last.log"

# --- fixture ----------------------------------------------------------------
mkdir -p "$tmp/srv/srv" "$tmp/home" "$tmp/fakebin"
for f in a b; do head -c 40000 /dev/urandom > "$tmp/srv/$f.iso"; done
head -c 262144 /dev/urandom > "$tmp/srv/big.iso"
head -c 30000 /dev/urandom > "$tmp/srv/srv/pic.webp"
for f in v a b; do
    ffmpeg -loglevel error -f lavfi -i testsrc=duration=1:size=128x128:rate=10 \
        -pix_fmt yuv420p "$tmp/srv/srv/$f.mp4"
done
touch -d '2020-01-01 00:00:00' "$tmp/srv/srv/v.mp4"
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
cat > "$tmp/srv/one.html" <<'EOF'
<html><head><title>One</title></head><body><video src="srv/a.mp4"></video></body></html>
EOF
cat > "$tmp/srv/two.html" <<'EOF'
<html><head><title>Two</title></head><body><video src="srv/b.mp4"></video></body></html>
EOF
mkdir -p "$tmp/srv/one" "$tmp/srv/two"
printf 'ONE\n' > "$tmp/srv/one/same.iso"
printf 'TWO\n' > "$tmp/srv/two/same.iso"
printf 'NEW\n' > "$tmp/srv/pre.iso"
printf 'ORIGINAL-ZIP\n' > "$tmp/srv/run.zip"
head -c 2097152 /dev/urandom > "$tmp/srv/resume.iso"
cat > "$tmp/fakebin/aria2c" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
chmod +x "$tmp/fakebin/aria2c"

# zip shim when the real zip command is missing
mkdir -p "$tmp/zipbin"
if ! command -v zip >/dev/null 2>&1; then
    cat > "$tmp/zipbin/zip" <<'EOF'
#!/usr/bin/env bash
# vdl runs: zip -q -r TARGET files...
declare -a rest=()
target=''
for a in "$@"; do
    if [[ $a != -* ]]; then
        if [[ -z $target ]]; then target=$a; else rest+=("$a"); fi
    fi
done
python3 -m zipfile -c "$target" "${rest[@]}"
EOF
    chmod +x "$tmp/zipbin/zip"
fi

# random free port so parallel/leftover servers cannot collide
port=$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1]); s.close()')
python3 -m http.server "$port" --bind 127.0.0.1 --directory "$tmp/srv" >/dev/null 2>&1 &
srv=$!

# A tiny Range-capable server for the resume test.  Python's stdlib server
# ignores Range, and a real resume test needs 206 responses.
cat > "$tmp/range_server.py" <<'PY'
import http.server, os, re, sys, time

root = sys.argv[1]
port = int(sys.argv[2])


class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def _target(self):
        path = self.path.split("?", 1)[0].lstrip("/")
        full = os.path.normpath(os.path.join(root, path))
        if not full.startswith(os.path.abspath(root) + os.sep):
            return None
        return full

    def _headers(self, size, start, end, partial):
        self.send_response(206 if partial else 200)
        if partial:
            self.send_header("Content-Range", f"bytes {start}-{end}/{size}")
        self.send_header("Content-Type", "application/octet-stream")
        self.send_header("Content-Length", str(end - start + 1))
        self.send_header("Accept-Ranges", "bytes")
        self.end_headers()

    def do_GET(self):
        target = self._target()
        if not target or not os.path.isfile(target):
            self.send_error(404)
            return
        size = os.path.getsize(target)
        start, end, partial = 0, size - 1, False
        match = re.match(r"bytes=(\d+)-(\d*)$", self.headers.get("Range", ""))
        if match:
            start = int(match.group(1))
            end = int(match.group(2)) if match.group(2) else end
            if start >= size:
                self.send_error(416)
                return
            partial = True
        self._headers(size, start, end, partial)
        with open(target, "rb") as fh:
            fh.seek(start)
            left = end - start + 1
            while left > 0:
                chunk = fh.read(min(65536, left))
                if not chunk:
                    break
                try:
                    self.wfile.write(chunk)
                except BrokenPipeError:
                    return
                left -= len(chunk)
                time.sleep(0.02)


class Server(http.server.ThreadingHTTPServer):
    allow_reuse_address = True


Server(("127.0.0.1", port), Handler).serve_forever()
PY
rport=$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1]); s.close()')
python3 "$tmp/range_server.py" "$tmp/srv" "$rport" >/dev/null 2>&1 &
rsrv=$!
sleep 0.5

export HOME="$tmp/home" NO_COLOR=1
B="http://127.0.0.1:$port"
REAL="/usr/bin:/bin"
# vdl runs with PATH limited to REAL, so include the directories yt-dlp and
# ffmpeg actually live in (apt puts them in /usr/bin, pip in ~/.local/bin,
# a venv or a static build somewhere else entirely).
for tool in yt-dlp ffmpeg; do
    if tb=$(command -v "$tool" 2>/dev/null) && [[ $tb != /usr/bin/* ]]; then
        REAL="$(dirname -- "$tb"):$REAL"
    fi
done
DL="$tmp/home/Downloads/vdl"

run_vdl() { PATH="$REAL" bash "$root/bin/vdl" "$@" >"$LOG" 2>&1; }

# --- 1. multiple direct files ----------------------------------------------
run_vdl -n --no-impersonate "$B/a.iso" "$B/b.iso"; rc=$?
check "multi-direct rc"  test $rc -eq 0
check "a.iso exists"     test -f "$DL/a.iso"
check "b.iso exists"     test -f "$DL/b.iso"

# --- 1b. duplicate direct basenames are distinct under --no-aria -----------
rm -rf "$DL"
run_vdl -n --no-aria --no-impersonate "$B/one/same.iso" "$B/two/same.iso"; rc=$?
check "duplicate direct rc" test $rc -eq 0
check "duplicate direct first" sh -c "grep -qx ONE '$DL/same.iso'"
check "duplicate direct second" sh -c "grep -qx TWO '$DL/same.1.iso'"

# --- 1c. a pre-existing destination is skipped, not overwritten -------------
rm -rf "$DL"
mkdir -p "$DL"
printf 'OLD\n' > "$DL/pre.iso"
run_vdl -n --no-aria --no-impersonate "$B/pre.iso"; rc=$?
check "pre-existing rc" test $rc -eq 0
check "pre-existing preserved" sh -c "grep -qx OLD '$DL/pre.iso'"
check "pre-existing skipped" grep -q 'Direct.*: 0 OK, 0 Failed, 1 Skipped' "$LOG"

# --- 1d. --on-collision rename keeps the old file and downloads a new one ---
rm -rf "$DL"
mkdir -p "$DL"
printf 'OLD\n' > "$DL/a.iso"
run_vdl -n --no-impersonate --on-collision rename "$B/a.iso"; rc=$?
check "rename collision rc" test $rc -eq 0
check "rename collision old kept" sh -c "grep -qx OLD '$DL/a.iso'"
check "rename collision new file" cmp "$tmp/srv/a.iso" "$DL/a.1.iso"

# --- 2. playlist into a titled folder ---------------------------------------
run_vdl -n --no-impersonate "$B/list.html"; rc=$?
check "playlist rc"      test $rc -eq 0
check "item 1 in folder" test -f "$DL/My List/1 - My List (1) [list-1].mp4"
check "item 2 in folder" test -f "$DL/My List/2 - My List (2) [list-2].mp4"

# --- 2b. partially failing media batch keeps per-URL outcomes ---------------
rm -rf "$DL"
run_vdl -n --no-impersonate "$B/one.html" "$B/two.html" "$B/missing.html"; rc=$?
check "mixed media rc" test $rc -ne 0
check "mixed media two files" sh -c "test \$(find '$DL' -type f -name '*.mp4' | wc -l) -eq 2"
check "mixed media summary" grep -q 'Media.*: 2 OK, 1 Failed' "$LOG"
check "mixed media success line" grep -q '✓.*one.html' "$LOG"
check "mixed media failure line" grep -q '✗.*missing.html' "$LOG"

# --- 3. --images: video finishes before the page scan -----------------------
rm -rf "$DL"
PATH="$REAL" bash "$root/bin/vdl" -n --no-impersonate --images "$B/alb.html" >"$LOG" 2>&1; rc=$?
check "images rc" test $rc -eq 0
vline=$(grep -an '✓.*alb.html' "$LOG" | head -1 | cut -d: -f1)
sline=$(grep -an "Scanning page" "$LOG" | head -1 | cut -d: -f1)
if [[ -n $vline && -n $sline ]] && [ "$vline" -lt "$sline" ]; then
    ok
else
    bad "video before scan (v=$vline s=$sline)"
fi
check "photo in album folder" test -f "$DL/My Album/pic.webp"

# --- 4. image-only page -----------------------------------------------------
rm -rf "$DL"
run_vdl -n --no-impersonate --images "$B/photos.html"; rc=$?
check "image-only rc" test $rc -eq 0
check "image-only photo" test -f "$DL/Photos/pic.webp"

# --- 5. aria2c failure falls back to real yt-dlp -----------------------------
rm -rf "$DL"
PATH="$tmp/fakebin:$REAL" bash "$root/bin/vdl" -n --no-impersonate "$B/big.iso" >"$LOG" 2>&1; rc=$?
size=$(stat -c %s "$DL/big.iso" 2>/dev/null || printf "0")
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
PATH="$tmp/zipbin:$REAL" bash "$root/bin/vdl" -n --zip=run.zip "$B/a.iso" >"$LOG" 2>&1; rc=$?
check "zip rc"    test $rc -eq 0
check "zip file"  test -f "$DL/run.zip"
check "zip content" sh -c "python3 -m zipfile -l '$DL/run.zip' 2>/dev/null | grep -q a.iso"

# --- 7b. --zip cannot overwrite a file downloaded in the same run -----------
rm -rf "$DL"
run_vdl -n --no-impersonate --zip=run.zip "$B/run.zip"; rc=$?
check "zip collision rc" test $rc -ne 0
check "zip collision download kept" sh -c "grep -qx ORIGINAL-ZIP '$DL/run.zip'"
check "zip collision reported" grep -q 'Archive.*: failed' "$LOG"

# --- 8. multi-line paste ----------------------------------------------------
rm -rf "$DL"
paste_block="http://127.0.0.1:$port/a.iso
# noise
http://127.0.0.1:$port/b.iso"
PATH="$REAL" bash "$root/bin/vdl" -n "$paste_block" >"$LOG" 2>&1; rc=$?
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

# --- 10. real-gallery fixtures through the python parser ----------------------
# The parser's contract: <img> src/data-src only, data-rotate-src and data:
# URIs ignored, entities and query strings preserved.  The bash-side album
# scoping (cover skip, directory match, name filters) is exercised end to
# end by section 3 above.
cat > "$tmp/grid.expected" <<'EOF'
https://cdn.example.com/uploads/2026/01/02/abc123def456/one.jpg?v=1793165468
https://cdn.example.com/uploads/2026/01/02/abc123def456/three.jpg
https://cdn.example.com/uploads/2026/01/02/abc123def456/two.jpg?v=1793165470
EOF
python3 "$root/lib/vdl/scrape.py" "$root/test/fixtures/album-grid.html" | sort > "$tmp/grid.actual"
check "grid fixture output" diff -u "$tmp/grid.expected" "$tmp/grid.actual"

cat > "$tmp/thumbs.expected" <<'EOF'
https://example.com/avatar/36x36/user.jpeg
https://example.com/logo.png
https://example.com/uploads/2026/02/03/7b91aedc6bfef2cac/thumb/0-first.webp?v=1
https://example.com/uploads/2026/02/03/7b91aedc6bfef2cac/thumb/1-second.webp
https://example.com/uploads/2026/02/03/7b91aedc6bfef2cac/thumb/2-third.webp?v=9
https://example.com/uploads/2026/02/03/7b91aedc6bfef2cac/thumb/8-video.webp
https://example.com/uploads/2026/02/04/111111111111111/thumb/0-other.webp
EOF
python3 "$root/lib/vdl/scrape.py" "$root/test/fixtures/album-thumbs.html" | sort > "$tmp/thumbs.actual"
check "thumbs fixture output" diff -u "$tmp/thumbs.expected" "$tmp/thumbs.actual"

# --- 11. unrelated files in save_dir are untouched; expired cache runs swept -
mkdir -p "$DL/.tmp" "$tmp/cache/vdl/runs/old-run"
printf 'notes\n' > "$DL/.tmp/notes.txt"
printf 'partial' > "$DL/stale.iso"
: > "$DL/stale.iso.aria2"
printf 'stale-cache\n' > "$tmp/cache/vdl/runs/old-run/temp.part"
touch -d '8 days ago' "$DL/.tmp/notes.txt" "$DL/stale.iso" "$DL/stale.iso.aria2" \
    "$tmp/cache/vdl/runs/old-run" "$tmp/cache/vdl/runs/old-run/temp.part"
XDG_CACHE_HOME="$tmp/cache" PATH="$REAL" bash "$root/bin/vdl" -n --no-impersonate "$B/a.iso" >"$LOG" 2>&1; rc=$?
check "safe cleanup rc" test $rc -eq 0
check "unrelated .tmp kept" test -f "$DL/.tmp/notes.txt"
check "unrelated aria2 kept" test -f "$DL/stale.iso" -a -f "$DL/stale.iso.aria2"
check "expired cache run swept" test ! -e "$tmp/cache/vdl/runs/old-run"

# --- 12. --dry-run creates no directories or cache files ---------------------
rm -rf "$tmp/dry_cache" "$tmp/dry_out"
XDG_CACHE_HOME="$tmp/dry_cache" PATH="$REAL" bash "$root/bin/vdl" -n --no-impersonate \
    --output "$tmp/dry_out/sub/movie.iso" --dry-run "$B/a.iso" >"$LOG" 2>&1; rc=$?
check "dry-run rc" test $rc -eq 0
check "dry-run no dest dir" test ! -e "$tmp/dry_out"
check "dry-run no cache dir" test ! -e "$tmp/dry_cache/vdl"

# --- 13. --no-aria --mtime --zip archives file with old remote timestamp -----
rm -rf "$DL"
PATH="$tmp/zipbin:$REAL" bash "$root/bin/vdl" -n --no-aria --no-impersonate --mtime --zip=mtime.zip "$B/srv/v.mp4" >"$LOG" 2>&1; rc=$?
check "mtime zip rc" test $rc -eq 0
check "mtime zip exists" test -f "$DL/mtime.zip"
check "mtime zip content" sh -c "python3 -m zipfile -l '$DL/mtime.zip' 2>/dev/null | grep -q 'v\\.mp4'"

# --- 14. --dedupe and --zip never delete or grab pre-existing files ----------
rm -rf "$DL"
mkdir -p "$DL"
cp "$tmp/srv/a.iso" "$DL/preexisting.iso"
touch -d '2025-01-01 00:00:00' "$DL/preexisting.iso"
cat > "$tmp/srv/a-copy.iso" < "$tmp/srv/a.iso"
PATH="$tmp/zipbin:$REAL" bash "$root/bin/vdl" -n --dedupe --zip=deduped.zip "$B/a.iso" "$B/a-copy.iso" >"$LOG" 2>&1; rc=$?
check "dedupe+zip rc" test $rc -eq 0
check "preexisting kept" test -f "$DL/preexisting.iso"
check "only one new copy kept" sh -c "test -f '$DL/a.iso' -a ! -f '$DL/a-copy.iso' || test ! -f '$DL/a.iso' -a -f '$DL/a-copy.iso'"
check "deduped zip exists" test -f "$DL/deduped.zip"
check "zip excludes preexisting" sh -c "! (python3 -m zipfile -l '$DL/deduped.zip' 2>/dev/null | grep -q preexisting.iso)"

# --- 15. --zip rejects traversal outside save_dir ----------------------------
printf 'victim\n' > "$tmp/victim.zip"
PATH="$tmp/zipbin:$REAL" bash "$root/bin/vdl" -n --download-dir "$DL" --zip=../victim.zip "$B/a.iso" >"$LOG" 2>&1; rc=$?
check "zip traversal rc=2" test $rc -eq 2
check "victim untouched" sh -c "test \"\$(cat '$tmp/victim.zip')\" = victim"

# --- 16. image partial with .aria2 is cleaned and retried via real yt-dlp ----
rm -rf "$DL"
mkdir -p "$DL/Photos"
printf 'trunc' > "$DL/Photos/pic.webp"
: > "$DL/Photos/pic.webp.aria2"
PATH="$tmp/fakebin:$REAL" bash "$root/bin/vdl" -n --no-impersonate --images "$B/photos.html" >"$LOG" 2>&1; rc=$?
size=$(stat -c %s "$DL/Photos/pic.webp" 2>/dev/null || printf "0")
check "image partial retry rc" test $rc -eq 0
check "image partial ctrl gone" test ! -e "$DL/Photos/pic.webp.aria2"
check "image partial full size" test "$size" -eq 30000

# --- 17. interrupted yt-dlp download resumes from the stable partial --------
rm -rf "$DL" "$tmp/cache/vdl/partials"
resume_url="http://127.0.0.1:$rport/resume.iso"
XDG_CACHE_HOME="$tmp/cache" PATH="$REAL" timeout -s INT 3 \
    bash "$root/bin/vdl" -n --no-aria --no-impersonate --limit-speed 500K \
    --download-dir "$DL" "$resume_url" >"$LOG" 2>&1 || true
partial=$(find "$tmp/cache/vdl/partials" -type f -name '*.part' 2>/dev/null | head -1)
check "resume partial exists" test -n "$partial"
XDG_CACHE_HOME="$tmp/cache" PATH="$REAL" bash "$root/bin/vdl" -n --no-aria \
    --no-impersonate --limit-speed 500K --download-dir "$DL" "$resume_url" >"$LOG" 2>&1
rc=$?
check "resume rc" test $rc -eq 0
check "resume size" test "$(stat -c %s "$DL/resume.iso" 2>/dev/null || echo 0)" -eq 2097152
check "resume log" grep -q 'Resuming download at byte' "$LOG"

if (( fail )); then
    printf '\n--- debug: last vdl log ---\n'
    sed 's/^/    /' "$LOG" | tail -n 40
fi
printf '\n%d passed, %d failed\n' "$pass" "$fail"
(( fail == 0 )) || exit 1
