#!/usr/bin/env bash
# shellcheck shell=bash
# shellcheck disable=SC2154
# Answer yt-dlp's capability probe without logging it as a download.
if [[ ${0##*/} == yt-dlp && " $* " == *" --list-impersonate-targets "* ]]; then
    printf '[info] Available impersonate targets\n'
    printf 'Client    OS   Source\n'
    printf -- '----------------------------\n'
    if [[ ${FAKE_IMPERSONATE:-} == versioned ]]; then
        printf 'Chrome-133    Macos-15    curl_cffi\n'
        printf 'Chrome-136    Macos-15    curl_cffi\n'
        printf 'Chrome-150    Macos-26    curl_cffi\n'
        printf 'Chrome-152    Windows-10  curl_cffi\n'
        printf 'Safari-17.2   Ios-17.2    curl_cffi\n'
    elif [[ ${FAKE_IMPERSONATE:-} == yes ]]; then
        printf 'Chrome      -    curl_cffi\n'
    else
        printf 'Chrome      -    curl_cffi (unavailable)\n'
    fi
    exit 0
fi
if [[ ${0##*/} == yt-dlp && " $* " == *" --print "* ]]; then
    if [[ " $* " == *"playlist_count"* ]]; then
        # --name probe: answer with the playlist item count (NA = single)
        if [[ ${FAKE_PLAYLIST:-} == yes ]]; then
            printf '3\n'
        else
            printf 'NA\n'
        fi
        exit 0
    fi
    if [[ " $* " == *" -I 1 "* ]]; then
        # vdl's embedded-image probe: answer with the page's extractor name.
        if [[ ${FAKE_GENERIC_PAGE:-} == yes ]]; then
            printf 'generic|\n'
        else
            printf 'youtube|\n'
        fi
    else
        # playlist URL listing used to scope embedded images
        printf 'https://cdn.example.com/album/video1.mp4\nhttps://cdn.example.com/album/video2.mp4\n'
    fi
    exit 0
fi
if [[ ${0##*/} == yt-dlp && ${FAKE_YTDLP_UNSUPPORTED:-} == yes ]]; then
    last=''
    for a in "$@"; do
        case $a in
            http://*|https://*) last=$a ;;
        esac
    done
    printf 'ERROR: Unsupported URL: %s\n' "$last" >&2
    exit 1
fi
if [[ ${0##*/} == gallery-dl && ${FAKE_GALLERY_NOISY:-} == yes ]]; then
    printf 'GALLERY OUTPUT\n'
    printf 'GALLERY PROGRESS\n' >&2
fi
if [[ ${0##*/} == gallery-dl && ${FAKE_GALLERY_FAIL:-} == yes ]]; then
    exit 1
fi
if [[ ${0##*/} == yt-dlp && ${FAKE_YTDLP_FAIL:-} == cloudflare ]]; then
    printf 'ERROR: [generic] Got HTTP Error 403 caused by Cloudflare anti-bot challenge\n' >&2
    exit 1
fi
if [[ ${0##*/} == yt-dlp && ${FAKE_YTDLP_FAIL:-} == forbidden ]]; then
    printf 'ERROR: [generic] Unable to download webpage: HTTP Error 403: Forbidden\n' >&2
    exit 1
fi
if [[ ${0##*/} == vivaldi ]]; then
    printf 'VIVALDI %s\n' "${1:-}" >> "$FAKE_LOG"
    if [[ ${1:-} == --version ]]; then
        printf 'Vivaldi 8.2.4133.96 stable\n'
    fi
    exit 0
fi
printf 'CALL %s\n' "${0##*/}" >> "$FAKE_LOG"
for a in "$@"; do
    printf 'ARG %s\n' "$a" >> "$FAKE_LOG"
done
if [[ ${0##*/} == aria2c && ${FAKE_ARIA_PARTIAL:-} == yes ]]; then
    dir='' prev=''
    for a in "$@"; do
        [[ $prev == -d ]] && dir=$a
        prev=$a
    done
    mkdir -p "$dir"
    for a in "$@"; do
        case $a in
            http://*|https://*)
                name=${a##*/}
                name=${name%%\?*}
                if [[ -n $name ]]; then
                    printf 'partial' > "$dir/$name"
                    : > "$dir/$name.aria2"
                fi
                ;;
        esac
    done
    exit 1
fi
if [[ ${0##*/} == aria2c && ${FAKE_ARIA_FAIL:-} == yes ]]; then
    exit 1
fi
if [[ ${0##*/} == aria2c && ${FAKE_ARIA_DUP:-} == yes ]]; then
    dir='' hook='' prev=''
    for a in "$@"; do
        [[ $prev == -d ]] && dir=$a
        [[ $a == --on-download-complete=* ]] && hook=${a#--on-download-complete=}
        prev=$a
    done
    mkdir -p "$dir"
    for a in "$@"; do
        case $a in
            http://*|https://*)
                name=${a##*/}
                name=${name%%\?*}
                if [[ -n $name ]]; then
                    printf 'same-content\n' > "$dir/$name"
                    [[ -n $hook && -x $hook ]] && "$hook" 1 1 "$dir/$name"
                fi
                ;;
        esac
    done
fi
if [[ ${0##*/} == yt-dlp && ${FAKE_YTDLP_CREATE:-} == yes ]]; then
    home_dir='' out_tmpl='' mf='' prev='' prev2=''
    for a in "$@"; do
        [[ $prev == -P && $a == home:* ]] && home_dir=${a#home:}
        [[ $prev == -o ]] && out_tmpl=$a
        [[ $prev2 == --print-to-file ]] && mf=$a
        prev2=$prev
        prev=$a
    done
    if [[ -n $home_dir ]]; then
        mkdir -p "$home_dir"
        fname=${out_tmpl//%/}
        [[ -z $fname || $fname == *'('* ]] && fname=video.mp4
        fpath=$home_dir/$fname
        printf 'yt-content\n' > "$fpath"
        [[ -n ${FAKE_YTDLP_MTIME:-} ]] && touch -d "$FAKE_YTDLP_MTIME" "$fpath"
        if [[ -n $mf ]]; then
            mf=${mf//%%/%}
            printf '%s\n' "$fpath" >> "$mf"
        fi
    fi
fi
if [[ ${0##*/} == zip ]]; then
    # vdl runs: zip -q -r TARGET files... — create the archive file.
    for a in "$@"; do
        if [[ $a != -* ]]; then
            printf 'PK\003\004' > "$a"
            break
        fi
    done
    exit 0
fi
if [[ ${0##*/} == curl ]]; then
    if [[ " $* " == *'/json/version'* ]]; then
        printf '{\n   "User-Agent": "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) HeadlessChrome/152.0.0.0 Safari/537.36"\n}\n'
        exit 0
    fi
    outfile=''
    prev=''
    for a in "$@"; do
        if [[ $prev == -o ]]; then outfile=$a; fi
        prev=$a
    done
    html='<html><title>Test Album</title><link rel="icon" href="https://cdn.example.com/favicon.png"><img src="https://cdn.example.com/logo.png"><img data-rotate-src="https://cdn.example.com/thumbs/grid1.jpg"><img src="https://cdn.example.com/avatar/36x36/u1.jpeg"><img src="data:image/png;base64,AAAA"><img src="https://cdn.example.com/album/pic1.jpg?v=123"><img data-src="//cdn.example.com/album/pic2.png?v=9"><img src="https://cdn.example.com/album/video1.jpg"><img src="https://cdn.example.com/other/thumb/side.jpg"></html>'
    if [[ -n $outfile ]]; then
        printf '%s\n' "$html" > "$outfile"
    else
        printf '%s\n' "$html"
    fi
    exit 0
fi
if [[ ${0##*/} == wl-paste ]]; then
    printf '%s' "${FAKE_CLIP:-https://example.com/from-clipboard}"
fi
exit 0
