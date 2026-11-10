# shellcheck shell=bash
# shellcheck disable=SC2154

# Download directory handling and normalization.

# --- download-dir override -------------------------------------------------
ddir=$tmp/customdir
if run -n --download-dir "$ddir" 'https://example.com/file.iso' \
    && arg_has "-d" && arg_has "$ddir"; then
    ok
else
    bad "--download-dir should be forwarded to aria2c as -d"
fi

# --- trailing slashes are normalized ----------------------------------------
run -n --download-dir "$ddir/" 'https://example.com/file.iso'
if arg_is -d && arg_is "$ddir" && ! arg_has "$ddir//" \
    && ! grep -qF "$ddir/" "$out"; then
    ok
else
    bad "a trailing slash in --download-dir should not survive into paths"
fi

run -n --no-impersonate --download-dir "$ddir/" 'https://example.com/watch?v=abc'
if arg_has "home:$ddir" && ! arg_has "home:$ddir/" \
    && ! grep -qF "$ddir/" "$out"; then
    ok
else
    bad "media downloads should use the normalized directory"
fi

# --- bare --download-dir names land in the default vdl folder ----------------
run -n --download-dir custom-dir/ 'https://example.com/file.iso'
if arg_is -d && arg_is "$home/Downloads/vdl/custom-dir"; then
    ok
else
    bad "a bare --download-dir should be created inside the default vdl folder"
fi

run -n --no-impersonate --download-dir custom-dir 'https://example.com/watch?v=abc'
if arg_has "home:$home/Downloads/vdl/custom-dir"; then
    ok
else
    bad "media downloads should use the bare --download-dir folder"
fi

run -n --download-dir ./cwd-dir 'https://example.com/file.iso'
if arg_is -d && arg_is './cwd-dir'; then
    ok
else
    bad "a ./ prefixed --download-dir should stay current-directory-relative"
fi

