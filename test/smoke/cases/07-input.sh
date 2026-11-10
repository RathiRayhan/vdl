# shellcheck shell=bash
# shellcheck disable=SC2154

# Batch files, clipboard, forwarded option values, and multi-line input.

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

export WAYLAND_DISPLAY=wayland-0
export FAKE_CLIP=$'https://example.com/one\nhttps://example.com/two\nnot a url\n'
run -n
rc=$?
unset WAYLAND_DISPLAY FAKE_CLIP
if [[ $rc -eq 0 ]] && arg_is 'https://example.com/one' \
    && arg_is 'https://example.com/two' && ! arg_has 'not a url' \
    && grep -q 'Auto-grabbed 2 URL(s)' "$err"; then
    ok
else
    bad "a multi-line clipboard should queue every URL line"
fi


# --- multi-line URL paste ---------------------------------------------------
run -n $'https://example.com/a.iso\nhttps://example.com/b.iso\n\n'
if arg_is 'https://example.com/a.iso' && arg_is 'https://example.com/b.iso' \
    && called aria2c; then
    ok
else
    bad "a pasted multi-line argument should be split into URLs"
fi

run -n -q 720 $'https://example.com/watch?v=x\n# not a url\nhttps://example.com/watch?v=y'
if arg_is 'https://example.com/watch?v=x' && arg_is 'https://example.com/watch?v=y' \
    && arg_has 'height<=720' && ! arg_has '# not a url'; then
    ok
else
    bad "multi-line paste with flags should download every URL with the flags applied"
fi

