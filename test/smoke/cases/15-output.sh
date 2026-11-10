# shellcheck shell=bash
# shellcheck disable=SC2154

# Custom names and exact output paths.

# --- custom filename --------------------------------------------------------
run -n --name myfile 'https://example.com/file.iso'
if called aria2c && arg_is -o && arg_is 'myfile.iso'; then
    ok
else
    bad "--name should rename a direct file (extension appended)"
fi

run -n --no-impersonate --name myvid 'https://example.com/watch?v=abc'
last_o=$(awk '/^ARG -o$/{getline; val=$0} END{print val}' "$log")
if [[ $last_o == 'ARG myvid.%(ext)s' ]]; then
    ok
else
    bad "--name should append a media output template (got $last_o)"
fi

run -n --name x 'https://example.com/a.iso' 'https://example.com/b.iso'
rc=$?
if [[ $rc -eq 2 ]] && grep -q 'single URL' "$err"; then
    ok
else
    bad "--name with multiple URLs should exit 2"
fi

export FAKE_PLAYLIST=yes
run -n --no-impersonate --name myalb 'https://example.com/watch?v=abc'
unset FAKE_PLAYLIST
last_o=$(awk '/^ARG -o$/{getline; val=$0} END{print val}' "$log")
if [[ $last_o == 'ARG myalb/%(playlist_index&{} - |)s%(title).80B [%(id)s].%(ext)s' ]]; then
    ok
else
    bad "--name on a playlist should name the folder (got $last_o)"
fi

# --- exact output path ------------------------------------------------------
outdir=$tmp/customout
run -n --output "$outdir/movie.mp4" 'https://example.com/file.iso'
if called aria2c && arg_is -d && arg_is "$outdir" && arg_is 'movie.mp4'; then
    ok
else
    bad "--output with an extension should name the exact file"
fi

run -n --no-impersonate --output "$outdir/vid.mp4" 'https://example.com/watch?v=abc'
last_o=$(awk '/^ARG -o$/{getline; val=$0} END{print val}' "$log")
if [[ $last_o == 'ARG vid.mp4' ]] && arg_has "$outdir"; then
    ok
else
    bad "--output with an extension should target the exact media file (got $last_o)"
fi

export FAKE_PLAYLIST=yes
run -n --no-impersonate --output "$outdir/myalb" 'https://example.com/watch?v=abc'
unset FAKE_PLAYLIST
last_o=$(awk '/^ARG -o$/{getline; val=$0} END{print val}' "$log")
if [[ $last_o == 'ARG %(playlist_index&{} - |)s%(title).80B [%(id)s].%(ext)s' ]] \
    && arg_has "$outdir/myalb"; then
    ok
else
    bad "--output folder should hold playlist items directly (got $last_o)"
fi

run -n --output x 'https://example.com/a.iso' 'https://example.com/b.iso'
rc=$?
if [[ $rc -eq 2 ]] && grep -q 'single URL' "$err"; then
    ok
else
    bad "--output with multiple URLs should exit 2"
fi

run -n --output "$outdir/" 'https://example.com/file.iso'
if arg_is -d && arg_is "$outdir" && ! arg_has "$outdir//"; then
    ok
else
    bad "a trailing slash on an --output folder should be normalized"
fi

run -n --output x.iso --name y 'https://example.com/a.iso'
rc=$?
if [[ $rc -eq 2 ]] && grep -q 'cannot be combined' "$err"; then
    ok
else
    bad "--output with --name should exit 2"
fi

