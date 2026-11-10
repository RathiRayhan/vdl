# shellcheck shell=bash
# shellcheck disable=SC2154

# URL routing: media vs direct files, quality caps, headers, magnet/torrent/tarball.

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


# --- quality aliases -------------------------------------------------------
run -n -q 4k 'https://example.com/watch?v=abc'
if arg_has 'height<=2160'; then ok; else bad "4k should map to 2160"; fi
run -n -q 720p 'https://example.com/watch?v=abc'
if arg_has 'height<=720'; then ok; else bad "720p should map to 720"; fi


# --- direct file via aria2c ------------------------------------------------
if run -n 'https://example.com/file.iso' \
    && called aria2c && arg_is -x && arg_is 16 && arg_is -Z; then
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


# --- magnet link routing ---------------------------------------------------
if run -n 'magnet:?xt=urn:btih:abc' && called aria2c && ! called yt-dlp; then
    ok
else
    bad "magnet: links should route to aria2c"
fi

# --- compressed tarballs with short suffixes are direct ---------------------
if run -n 'https://example.com/file.tgz' \
    && called aria2c && ! called yt-dlp; then
    ok
else
    bad ".tgz files should route to aria2c as direct downloads"
fi

# --- .torrent routing ------------------------------------------------------
if run -n 'https://example.com/file.torrent' && called aria2c && ! called yt-dlp; then
    ok
else
    bad ".torrent URLs should route to aria2c"
fi


# --- 8k quality alias ------------------------------------------------------
run -n -q 8k 'https://example.com/watch?v=abc'
if arg_has 'height<=4320'; then ok; else bad "8k should map to 4320"; fi

