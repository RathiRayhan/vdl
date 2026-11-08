#!/usr/bin/env bash
# shellcheck shell=bash
# shellcheck disable=SC2034,SC2154,SC2329  # globals live in bin/vdl or the libs
#
# vdl planning: split URLs into direct/media, run the image scanner, decide
# the engines, resolve --name/--output, and check tool requirements.

classify_urls() {
    direct=()
    media=()
    gallery=()

    local gallery_missing=0
    for u in "${urls[@]}"; do
        if url_is_direct "$u"; then
            direct+=("$u")
        elif (( gallery_mode )) || url_is_gallery_host "$u"; then
            # Known hosts go to gallery-dl only when it is installed, so the
            # existing yt-dlp fallback still works on machines without it.
            if have gallery-dl || (( gallery_mode )); then
                gallery+=("$u")
            else
                gallery_missing=1
                media+=("$u")
            fi
        else
            media+=("$u")
        fi
    done

    if (( gallery_missing )); then
        note "gallery-dl not installed: gallery/file hosts will be tried with yt-dlp"
    fi

    direct_via_ytdlp=0
    direct_pending=()

    img_urls=()
    img_refs=()
    img_dirs=()

    preflight_images

    if (( ${#direct[@]} )); then
        if (( ! have_aria || no_aria )); then
            direct_via_ytdlp=1
            direct_pending=("${direct[@]}")
            if (( have_aria )); then
                note "--no-aria: direct files will be fetched with yt-dlp"
            else
                note "aria2c not installed: direct files will be fetched with yt-dlp"
            fi
        fi
    fi

    # Resolve --name into the concrete output names.  For a direct file the
    # extension is appended literally when the user's name lacks one; for a
    # media download the yt-dlp template %(ext)s is used so the real
    # container extension wins.  In audio mode the extension is always mp3.
    if [[ -n $custom_name ]]; then
        local ext uext folder pl_out
        custom_direct=''
        custom_media=''
        ext=''
        uext=${named_url##*/}
        uext=${uext%%\?*}
        uext=${uext%%#*}
        case $uext in
            *.*) ext=${uext##*.} ;;
        esac
        ext=${ext,,}
        [[ $ext =~ ^[a-z0-9]{1,8}$ ]] || ext=''
        (( audio )) && ext=mp3

        if [[ $custom_name == *.* ]]; then
            custom_direct=$custom_name
            custom_media=$custom_name
        else
            custom_direct=$custom_name
            [[ -n $ext ]] && custom_direct=$custom_name.$ext
            custom_media=$custom_name.'%(ext)s'
        fi

        if (( ${#direct[@]} )); then
            (( ${#direct[@]} == 1 )) || { err "--name works with a single direct file"; exit 2; }
        elif (( ${#media[@]} )); then
            (( ${#media[@]} == 1 )) || { err "--name works with a single media item"; exit 2; }
            # A playlist URL: NAME becomes the folder name instead of a
            # single filename.  One light probe tells the two cases apart.
            if (( ! dry_run )) && have yt-dlp; then
                pl_out=$(yt-dlp --ignore-config --quiet --simulate -I 1 \
                    --print '%(playlist_count)s' -- "${media[0]}" 2>/dev/null)
                pl_out=${pl_out##*$'\n'}
                if [[ $pl_out =~ ^[0-9]+$ ]]; then
                    folder=$(sanitize_title "$custom_name")
                    [[ -n $folder ]] || folder=$custom_name
                    custom_media="${folder}/%(playlist_index&{} - |)s%(title).80B [%(id)s].%(ext)s"
                fi
            fi
        elif (( ${#img_urls[@]} )); then
            note "--name ignored: this page only yields embedded images"
            custom_name=''
            custom_direct=''
            custom_media=''
        fi
    fi

    # A playlist cannot be saved as a single file, so --output with an
    # extension must reject playlist URLs (one light probe tells them apart).
    if [[ -n $output_arg ]] && [[ -n ${custom_direct:-} ]] && (( ${#media[@]} )) \
        && (( ! dry_run )) && have yt-dlp; then
        pl_out=$(yt-dlp --ignore-config --quiet --simulate -I 1 \
            --print '%(playlist_count)s' -- "${media[0]}" 2>/dev/null)
        pl_out=${pl_out##*$'\n'}
        if [[ $pl_out =~ ^[0-9]+$ ]]; then
            err "--output with a file extension cannot be used for a playlist URL"
            exit 2
        fi
    fi

    if (( ${#gallery[@]} )) && ! have gallery-dl; then
        err "gallery-dl is required for --gallery or gallery/file-host URLs"
        printf '    Install it with: pipx install gallery-dl\n' >&2
        exit 1
    fi

    if (( audio )) && (( ${#gallery[@]} )); then
        err "--audio cannot be combined with gallery-dl URLs"
        printf '    gallery-dl does not convert media to MP3.\n' >&2
        exit 2
    fi

    need_ytdlp=0
    (( ${#media[@]} )) && need_ytdlp=1
    (( direct_via_ytdlp )) && need_ytdlp=1

    if (( need_ytdlp )) && ! have yt-dlp; then
        err "yt-dlp is required but was not found in PATH"
        exit 1
    fi

    if (( audio )) && (( ${#media[@]} )) && ! have ffmpeg; then
        err "ffmpeg is required for audio extraction (-a)"
        exit 1
    fi

    if (( ${#gallery[@]} )) \
        && [[ -n ${custom_name:-} || -n ${custom_direct:-} || -n ${custom_media:-} ]]; then
        note "gallery-dl keeps its own filenames; --name/--output file naming is ignored for gallery URLs"
    fi
}
