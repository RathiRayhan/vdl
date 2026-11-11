# shellcheck shell=bash
# shellcheck disable=SC2154

# Safety regressions (Phase 1): temp isolation, dry-run side-effect freedom,
# explicit run manifest, zip confinement, image partials, and exit-code invariants.

# --- 1. Unrelated .tmp and *.aria2 files in save_dir are never deleted -------
safety_dir=$tmp/safety_dl
mkdir -p "$safety_dir/.tmp"
printf 'user notes\n' > "$safety_dir/.tmp/notes.txt"
printf 'partial' > "$safety_dir/other.bin"
: > "$safety_dir/other.bin.aria2"
touch -d '30 days ago' "$safety_dir/.tmp/notes.txt" "$safety_dir/other.bin" "$safety_dir/other.bin.aria2"

run -n --download-dir "$safety_dir" --dry-run 'https://example.com/new.iso'
rc=$?
if [[ $rc -eq 0 ]] \
    && [[ -f $safety_dir/.tmp/notes.txt ]] \
    && [[ -f $safety_dir/other.bin ]] \
    && [[ -f $safety_dir/other.bin.aria2 ]]; then
    ok
else
    bad "--dry-run must never delete unrelated .tmp or .aria2 files"
fi

run -n --download-dir "$safety_dir" 'https://example.com/new.iso'
rc=$?
if [[ $rc -eq 0 ]] \
    && [[ -f $safety_dir/.tmp/notes.txt ]] \
    && [[ -f $safety_dir/other.bin ]] \
    && [[ -f $safety_dir/other.bin.aria2 ]]; then
    ok
else
    bad "normal runs must never delete unrelated .tmp or .aria2 files in save_dir"
fi

# --- 2. --dry-run is completely side-effect free -----------------------------
dry_target=$tmp/dry_never_created/sub/movie.mp4
dry_cache=$tmp/dry_cache
mkdir -p "$home/.config/vivaldi"
XDG_CACHE_HOME=$dry_cache run --output "$dry_target" --dry-run 'https://example.com/watch?v=x'
rc=$?
if [[ $rc -eq 0 ]] \
    && [[ ! -e $tmp/dry_never_created ]] \
    && [[ ! -e $dry_cache/vdl ]] \
    && ! grep -q 'VIVALDI' "$log"; then
    ok
else
    bad "--dry-run must not create destination dirs, cache dirs, or probe browsers"
fi
rm -rf "$home/.config/vivaldi"

# --- 3. Manifest handles --mtime downloads and protects pre-existing files ---
rm -f "$VDL_SAVE_DIR"/*.iso "$VDL_SAVE_DIR"/*.zip "$VDL_SAVE_DIR"/*.mp4
export FAKE_YTDLP_CREATE=yes FAKE_YTDLP_MTIME='2020-01-01 00:00:00'
run -n --no-aria --no-impersonate --mtime --zip=mtime-run.zip 'https://example.com/watch?v=old'
rc=$?
unset FAKE_YTDLP_CREATE FAKE_YTDLP_MTIME
if [[ $rc -eq 0 ]] && called zip && [[ -f $VDL_SAVE_DIR/mtime-run.zip ]] \
    && ! grep -q 'nothing to archive' "$err"; then
    ok
else
    bad "--zip must archive files downloaded with remote mtimes (--mtime)"
fi

rm -f "$VDL_SAVE_DIR"/*.iso "$VDL_SAVE_DIR"/*.zip "$VDL_SAVE_DIR"/*.mp4
printf 'same-content\n' > "$VDL_SAVE_DIR/preexisting.iso"
printf 'concurrent\n' > "$VDL_SAVE_DIR/unrelated.txt"
export FAKE_ARIA_DUP=yes
run -n --dedupe --zip=scoped.zip 'https://example.com/new1.iso' 'https://example.com/new2.iso'
rc=$?
unset FAKE_ARIA_DUP
if [[ $rc -eq 0 ]] \
    && [[ -f $VDL_SAVE_DIR/preexisting.iso ]] \
    && [[ -f $VDL_SAVE_DIR/unrelated.txt ]] \
    && [[ ( -e $VDL_SAVE_DIR/new1.iso || -e $VDL_SAVE_DIR/new2.iso ) ]] \
    && [[ ! ( -e $VDL_SAVE_DIR/new1.iso && -e $VDL_SAVE_DIR/new2.iso ) ]] \
    && [[ -f $VDL_SAVE_DIR/scoped.zip ]] \
    && ! grep -q 'preexisting.iso' "$err"; then
    ok
else
    bad "--dedupe must only touch files created in this run and never delete pre-existing files"
fi

# --- 4. --zip refuses path traversal and unsafe archive names ----------------
victim=$tmp/victim.zip
printf 'keep-me\n' > "$victim"
for bad_zip in '../victim.zip' 'sub/out.zip' 'sub\out.zip' '..' '.' '-r' ''; do
    run -n --zip="$bad_zip" 'https://example.com/a.iso'
    rc=$?
    if [[ $rc -ne 2 ]]; then
        bad "--zip=$bad_zip should exit 2 (got $rc)"
    fi
done
if [[ $(cat "$victim") == 'keep-me' ]]; then
    ok
else
    bad "--zip path traversal must never modify files outside save_dir"
fi

# --- 5. Image partial handling: partials with .aria2 are retried, not OK -----
img_dl=$tmp/img_partial_dl
rm -rf "$img_dl"
export FAKE_GENERIC_PAGE=yes FAKE_ARIA_PARTIAL=yes FAKE_YTDLP_CREATE=yes
run -n --no-impersonate --download-dir "$img_dl" --images 'https://example.com/watch?v=abc'
rc=$?
unset FAKE_GENERIC_PAGE FAKE_ARIA_PARTIAL FAKE_YTDLP_CREATE
if [[ $rc -eq 0 ]] \
    && called yt-dlp \
    && [[ ! -e $img_dl/Test\ Album/pic1.jpg.aria2 ]] \
    && [[ ! -e $img_dl/Test\ Album/pic2.png.aria2 ]] \
    && grep -q 'Images.*: 2 OK, 0 Failed' "$out"; then
    ok
else
    bad "incomplete image partials with .aria2 sidecars must be cleaned and retried via yt-dlp"
fi

# When aria2c leaves a partial + .aria2 and yt-dlp retry fails, the old
# partial/.aria2 must have been removed and exit status must be nonzero.
rm -rf "$img_dl"
export FAKE_ARIA_PARTIAL=yes FAKE_YTDLP_FAIL=forbidden
run -n --download-dir "$img_dl" 'https://example.com/part.iso'
rc=$?
unset FAKE_ARIA_PARTIAL FAKE_YTDLP_FAIL
if [[ $rc -ne 0 ]] \
    && grep -q '403: Forbidden' "$out" \
    && [[ ! -e $img_dl/part.iso ]] \
    && [[ ! -e $img_dl/part.iso.aria2 ]]; then
    ok
else
    bad "aria2c partial with yt-dlp failure should clean partial, retry, and exit nonzero"
fi

# --- 6. Mixed image batch: 1 completed + 1 partial -> 2 OK, both counted -----
rm -rf "$img_dl"
mkdir -p "$img_dl/Test Album"
printf 'complete-bytes' > "$img_dl/Test Album/pic1.jpg"
# Custom aria2c wrapper: fails after leaving pic2.png partial + .aria2, keeping pic1.jpg
cat > "$fakebin/aria2c" <<'EOF'
#!/usr/bin/env bash
printf 'CALL aria2c\n' >> "$FAKE_LOG"
for a in "$@"; do printf 'ARG %s\n' "$a" >> "$FAKE_LOG"; done
dir='' prev=''
for a in "$@"; do
    [[ $prev == -d ]] && dir=$a
    prev=$a
done
if [[ $dir == */Test* ]]; then
    printf 'trunc' > "$dir/pic2.png"
    : > "$dir/pic2.png.aria2"
    exit 1
fi
exit 0
EOF
chmod +x "$fakebin/aria2c"
export FAKE_GENERIC_PAGE=yes FAKE_YTDLP_CREATE=yes
run -n --no-impersonate --download-dir "$img_dl" --images 'https://example.com/watch?v=abc'
rc=$?
unset FAKE_GENERIC_PAGE FAKE_YTDLP_CREATE
cp "$smoke_dir/stub.sh" "$fakebin/aria2c"
chmod +x "$fakebin/aria2c"
if [[ $rc -eq 0 ]] \
    && [[ $(cat "$img_dl/Test Album/pic1.jpg") == 'complete-bytes' ]] \
    && [[ ! -e $img_dl/Test\ Album/pic2.png.aria2 ]] \
    && grep -q 'Images.*: 1 OK, 0 Failed, 1 Skipped' "$out" \
    && grep -q '^  #  pic1.jpg$' "$out" \
    && [[ $(grep -cxF 'ARG https://cdn.example.com/album/pic2.png' "$log") -eq 2 ]] \
    && [[ $(grep -cxF 'ARG https://cdn.example.com/album/pic1.jpg' "$log") -eq 0 ]]; then
    ok
else
    bad "mixed image batch must skip pre-existing images and retry only incomplete ones"
fi

# --- 7. Permanent failure + HTTP retry success must still exit nonzero -------
export FAKE_ARIA_FAIL=yes
run -n 'magnet:?xt=urn:btih:abc' 'https://example.com/file.iso'
rc=$?
unset FAKE_ARIA_FAIL
if [[ $rc -ne 0 ]] && grep -q '1 OK, 1 Failed' "$out"; then
    ok
else
    bad "magnet failure followed by successful HTTP retry must still exit nonzero (got rc=$rc)"
fi
