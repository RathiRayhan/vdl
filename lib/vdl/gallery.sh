#!/usr/bin/env bash
# shellcheck shell=bash
# shellcheck disable=SC2034,SC2154,SC2329  # globals live in bin/vdl or the libs
#
# vdl gallery engine: route gallery/album/file hosts that yt-dlp does not
# support to gallery-dl, and retry yt-dlp's "Unsupported URL" failures with
# gallery-dl when it is installed.  Sourced by bin/vdl.

# Does this URL belong to a host where gallery-dl is a better fit than
# yt-dlp?  Keep this list to gallery/album/file hosts; ordinary video sites
# stay on yt-dlp.  Direct file URLs are handled by url_is_direct() first.
url_is_gallery_host() {
    local url=${1,,} rest host path

    case $url in
        http://*|https://*) ;;
        *) return 1 ;;
    esac

    rest=${url#*://}
    host=${rest%%/*}
    host=${host##*@}
    host=${host%%:*}
    host=${host#www.}
    host=${host#app.}

    path=/
    if [[ $rest == */* ]]; then
        path=/${rest#*/}
        path=${path%%\?*}
        path=${path%%#*}
    fi

    case $host in
        gofile.io)        [[ $path == /d/* ]] ;;
        pixeldrain.com|pixeldrain.net)
                          [[ $path == /u/* || $path == /l/* || $path == /api/file/* ]] ;;
        cyberfile.me)                             return 0 ;;
        filester.*)                               return 0 ;;
        catbox.moe)       [[ $path == /c/* ]] ;;
        imgbox.com)       [[ $path == /g/* ]] ;;
        imagebam.com)     [[ $path == /gallery/* || $path == /view/* ]] ;;
        imagepond.net)                            return 0 ;;
        *) return 1 ;;
    esac
}

# Shared gallery-dl arguments.  Unknown vdl options are yt-dlp passthrough
# arguments and deliberately never reach gallery-dl.
build_gallery_common() {
    gallery_common=( --no-colors --retries 10 )

    (( quiet )) && gallery_common+=( --quiet )
    [[ -n ${ua:-} ]] && gallery_common+=( --user-agent "$ua" )
    [[ -n ${proxy:-} ]] && gallery_common+=( --proxy "$proxy" )
    [[ ${browser:-none} != none ]] && \
        gallery_common+=( --cookies-from-browser "$browser" )

    # yt_speed is the stricter non-zero limit chosen by build_yt_common().
    [[ -n ${yt_speed:-} ]] && gallery_common+=( --limit-rate "$yt_speed" )
}

# Run one URL through gallery-dl.  -D (not -d) keeps vdl's save-directory
# contract: files land directly in the requested directory instead of a
# gallery-dl category subfolder.
#
# In an interactive terminal, force gallery-dl's custom output mode so its
# progress updates are emitted even though stdout is piped, then render them
# as vdl's own bar.  Without this, gallery-dl detects the pipe, switches to
# pipe output, and disables progress entirely.
gallery_download_one() {
    local u=$1
    if (( quiet )) || [[ ! -t 1 ]]; then
        if (( quiet )); then
            # Keep stderr (errors/warnings) but silence file paths and the
            # progress indicator.  Redirecting stdout also makes gallery-dl
            # select its non-TTY pipe output, so no bar is drawn.
            gallery-dl "${gallery_common[@]}" -D "$save_dir" "$u" >/dev/null
        else
            gallery-dl "${gallery_common[@]}" -D "$save_dir" "$u"
        fi
        return
    fi

    local mode='{"start":"@@VDL_START {}\n","success":"\r@@VDL_SUCCESS {}\n","skip":"\r@@VDL_SKIP {}\n","progress":"\r@@VDL_PROGRESS_BYTES {0} {1} ","progress-total":"\r@@VDL_PROGRESS {3} {0} {2} {1} "}'
    gallery-dl "${gallery_common[@]}" \
        -o "output.mode=$mode" -o output.shorten=false \
        -o downloader.http.progress=0.1 \
        -D "$save_dir" "$u" 2>&1 | gallery_bar
    return "${PIPESTATUS[0]}"
}

# Download the queue routed to gallery-dl.
download_gallery() {
    (( ${#gallery[@]} )) || return 0

    ui_section "Gallery / File Host Downloads via gallery-dl"
    for u in "${gallery[@]}"; do
        ui_item "$u"
    done

    build_gallery_common
    local u g_rc
    for u in "${gallery[@]}"; do
        g_rc=0
        gallery_download_one "$u" || g_rc=$?
        if (( g_rc )); then
            gallery_fail=$((gallery_fail + 1))
            failed_items+=("$u|gallery-dl exit $g_rc")
            rc=$g_rc
        else
            gallery_ok=$((gallery_ok + 1))
        fi
        ui_result "$g_rc" "$u"
    done
}

# URLs reported by yt-dlp as "Unsupported URL:" in its log.  Only these are
# eligible for the gallery-dl fallback; transient network and auth failures
# must not trigger a second engine.
gallery_unsupported_urls() {
    local log=${1:-} line url
    [[ -n $log && -f $log ]] || return 0

    while IFS= read -r line; do
        url=${line#*Unsupported URL: }
        url=${url%$'\r'}
        url=${url%"${url##*[![:space:]]}"}
        [[ $url == http://* || $url == https://* ]] || continue
        printf '%s\n' "$url"
    done < <(grep -F 'Unsupported URL:' "$log" 2>/dev/null)
}
