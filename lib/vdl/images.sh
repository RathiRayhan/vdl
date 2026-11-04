#!/usr/bin/env bash
# shellcheck shell=bash
# shellcheck disable=SC2154,SC2034,SC2329  # globals live in bin/vdl; functions invoked from there
#
# vdl embedded-image support: scanning album pages and downloading the
# images found on them, plus the --dedupe post-step.  Sourced by bin/vdl.

# Browser-like UA used for embedded image downloads (some CDNs block the
# default curl/aria2 agents and require a page referer).
img_ua="Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36"

# Scan pages without a dedicated yt-dlp extractor (generic/html5) for
# embedded <img> links and queue them as image downloads.  Known-site
# extractors (youtube, ...) are left alone, and --dry-run never touches the
# network.  A page with images but no video formats is treated as an
# image-only album and removed from the media list.
#
# Note: img_urls/img_refs/img_dirs are declared by bin/vdl and filled here.
scrape_images() {
    img_urls=()
    img_refs=()
    img_dirs=()
    images_on=0
    (( images )) && images_on=1
    [[ ${VDL_IMAGES:-} == 1 || ${VDL_IMAGES:-} == yes ]] && images_on=1

    if (( dry_run )) || (( ! images_on )) || (( ${#media[@]} == 0 )) || ! have yt-dlp; then
        return 0
    fi

    have curl || note "curl not installed: skipping embedded image scan"
    if ! have curl; then
        return 0
    fi

    declare -a media_kept=()
    for u in "${media[@]}"; do
        case $u in
            http://*|https://*) ;;
            *) media_kept+=("$u"); continue ;;
        esac

        probe_out=$(yt-dlp --ignore-config --quiet --simulate -I 1 \
            ${yt_cookie_args[@]+"${yt_cookie_args[@]}"} \
            --print '%(extractor)s|%(playlist_title)s' -- "$u" 2>&1)
        probe_rc=$?
        extractor=${probe_out##*$'\n'}
        extractor=${extractor%%|*}
        album_title=${probe_out##*$'\n'}
        album_title=${album_title#*|}
        [[ $probe_rc == 0 ]] || album_title=''
        [[ $album_title == NA ]] && album_title=''
        images_only=0
        case $probe_out in
            *"Unsupported URL"*|*"No video formats found"*)
                [[ $probe_rc != 0 ]] && images_only=1
                ;;
        esac
        if [[ $probe_rc == 0 && -n $extractor ]] \
            && [[ $extractor != generic && $extractor != generic:* && $extractor != html5 ]]; then
            media_kept+=("$u")
            continue
        fi

        # Collect the playlist's media URLs.  Their directory prefixes
        # scope the page's images to this album, and their basenames
        # identify video covers that must not be treated as photos.
        media_names=$'\n'
        media_dirs=$'\n'
        while IFS= read -r murl; do
            murl=${murl%%\?*}
            [[ $murl == http://* || $murl == https://* ]] || continue
            mb=${murl##*/}
            mb=${mb%.*}
            [[ -n $mb ]] && media_names+=$mb$'\n'
            mdir=${murl#*://*/}
            mdir=${mdir%/*}
            [[ $mdir == "${murl#*://*/}" ]] && mdir=''
            [[ -n $mdir ]] && media_dirs+=$mdir$'\n'
        done < <(yt-dlp --ignore-config --quiet --simulate \
            ${yt_cookie_args[@]+"${yt_cookie_args[@]}"} \
            --print '%(url)s' -- "$u" 2>/dev/null)

        curl_args=( -sL --max-time 30 )
        [[ -n $ua ]] && curl_args+=( -A "$ua" )
        [[ -n $referer ]] && curl_args+=( -e "$referer" )
        [[ -n $proxy ]] && curl_args+=( -x "$proxy" )

        page_file=$(mktemp "${TMPDIR:-/tmp}/vdl-page.XXXXXX") || page_file=''
        if [[ -n $page_file ]]; then
            curl "${curl_args[@]}" -o "$page_file" -- "$u" || true
        fi

        found=0

        # Only treat the response as a page when it looks like HTML.
        # Binary responses (e.g. a misclassified file) are skipped so
        # they are never slurped into a shell variable.
        if [[ -n $page_file ]] && grep -aqiE '<(img|html|body|head|a[ >]|video|title)' "$page_file"; then
            # Fall back to the page <title> when yt-dlp has no playlist
            # title, then sanitize it so the image folder matches the one
            # yt-dlp creates for the videos.
            if [[ -z $album_title ]]; then
                album_title=$(grep -oiE '<title[^>]*>[^<]+' "$page_file" \
                    | head -1 | sed -E 's/^<title[^>]*>//')
            fi
            img_dir=$save_dir
            if [[ -n $album_title ]]; then
                album_title=$(sanitize_title "$album_title")
                [[ -n $album_title ]] && img_dir=$save_dir/$album_title
            fi

            while IFS= read -r img; do
                [[ -n $img ]] || continue
                img=${img%%\?*}
                case ${img,,} in
                    *favicon*|*apple-touch*|*logo*|*/icons/*|*icon-*|*avatar*|*/thumbs/*)
                        # site chrome or thumbnail, not full content
                        continue
                        ;;
                esac
                case $img in
                    //*) img="https:$img" ;;
                    http://*|https://*) ;;
                    /*)
                        scheme_host=${u#*//}
                        scheme_host=${scheme_host%%/*}
                        img="https://$scheme_host$img"
                        ;;
                    *)
                        img="${u%/*}/$img"
                        ;;
                esac
                img=${img%%[[:space:]]*}

                # Scope to this album and skip video covers when the page has
                # a media playlist.  /thumb/ segments are ignored for the
                # comparison so previews and full images share a directory.
                if [[ $media_names != $'\n' ]]; then
                    ipath=${img#*://*/}
                    [[ ${ipath,,} == */thumb/* ]] && ipath=${ipath//\/thumb\//\/}
                    idir=${ipath%/*}
                    [[ $idir == "$ipath" ]] && idir=''
                    [[ $media_dirs == *$'\n'"$idir"$'\n'* ]] || continue
                    ibase=${ipath##*/}
                    ibase=${ibase%.*}
                    [[ $media_names == *$'\n'"$ibase"$'\n'* ]] && continue
                fi

                # A /thumb/ path is a preview: try the full-size image next to
                # it (same name, possibly .jpg for a .webp thumb).  A quick
                # header check with a browser UA and the page referer decides.
                if [[ ${img,,} == */thumb/* ]]; then
                    base=${img//\/thumb\//\/}
                    cand=''
                    for c in "$base" "${base%.webp}.jpg"; do
                        status=$(curl -sIL -A "${ua:-$img_ua}" -e "$u" \
                            --max-time 15 -o /dev/null -w '%{http_code}' "$c")
                        if [[ $status == 200 ]]; then
                            cand=$c
                            break
                        fi
                    done
                    [[ -n $cand ]] && img=$cand
                fi

                saw=0
                for q in "${urls[@]}" "${direct[@]}" "${media[@]}" "${img_urls[@]}"; do
                    if [[ $q == "$img" ]]; then
                        saw=1
                        break
                    fi
                done
                (( saw )) && continue
                urls+=("$img")
                img_urls+=("$img")
                img_refs+=("$u")
                img_dirs+=("$img_dir")
                found=1
                note "Embedded image: $img"
            done < <(sed -E 's/data-rotate-src="[^"]*"//g' "$page_file" \
                | sed -E "s/data-rotate-src='[^']*'//g" \
                | grep -oiE "<img[^>]*(src|data-src)=[\"'][^\"']+\.(jpe?g|png|webp|gif)(\?[^\"']*)?[\"']" \
                | grep -oE "(src|data-src)=[\"'][^\"']+[\"']" \
                | sed -E "s/^(src|data-src)=[\"']//; s/[\"']$//" | sed 's/&amp;/\&/g')
        fi
        [[ -n $page_file ]] && rm -f -- "$page_file"

        if (( images_only && found )); then
            # yt-dlp has nothing to download for this page; the images
            # are the whole album.
            note "No video formats on page — ${found} embedded image(s) queued"
        else
            media_kept+=("$u")
        fi
    done
    media=("${media_kept[@]}")
}

# Download the images queued by scrape_images, grouped by their source page
# so each group can send the right referer.  aria2c does the work when
# available; missing images fall back to yt-dlp per file.
download_images() {
    if (( ${#img_urls[@]} == 0 )); then
        return 0
    fi

    ui_section "Embedded images"
    for u in "${img_urls[@]}"; do
        ui_item "$(ui_name "$u")"
    done

    use_aria=0
    have aria2c && (( ! no_aria )) && use_aria=1

    declare -A img_ref_done=()
    for i in "${!img_urls[@]}"; do
        ref=${img_refs[$i]}
        [[ -n ${img_ref_done[$ref]:-} ]] && continue
        img_ref_done[$ref]=1

        dir=${img_dirs[$i]}
        if [[ $dir != "$save_dir" ]]; then
            mkdir -p "$dir" || continue
            (( quiet )) || printf '  %s→ %s%s\n' "$C_DIM" "${dir#"$save_dir"/}" "$C_OFF"
        fi

        declare -a batch=()
        for j in "${!img_urls[@]}"; do
            [[ ${img_refs[$j]} == "$ref" ]] && batch+=("${img_urls[$j]}")
        done

        img_rc=0
        if (( use_aria )); then
            declare -a img_aria=(
                -Z
                -x 4 -s 4 -k 1M
                --continue=true
                --file-allocation=none
                -d "$dir"
                "--referer=$ref"
                "--user-agent=${ua:-$img_ua}"
            )
            (( quiet )) && img_aria+=( --quiet=true )
            aria2c "${img_aria[@]}" "${batch[@]}" || img_rc=$?
        fi

        if (( img_rc == 0 )) && (( use_aria )); then
            for u in "${batch[@]}"; do
                ui_result 0 "$(ui_name "$u")"
            done
            img_ok=$((img_ok + ${#batch[@]}))
            continue
        fi

        if (( use_aria )); then
            # Only retry the images that are still missing; -Z downloads
            # sequentially, so some may have completed before the failure.
            declare -a retry_batch=()
            for u in "${batch[@]}"; do
                if name=$(url_filename "$u"); then
                    dest=$dir/$name
                    rm -f -- "${dest}.aria2"
                    [[ -e $dest ]] && continue
                fi
                retry_batch+=("$u")
            done
            if (( ${#retry_batch[@]} == 0 )); then
                for u in "${batch[@]}"; do
                    ui_result 0 "$(ui_name "$u")"
                done
                img_ok=$((img_ok + ${#batch[@]}))
                continue
            fi
            batch=("${retry_batch[@]}")
            warn "aria2c failed (exit $img_rc) — retrying ${#batch[@]} image(s) via yt-dlp"
        fi

        if ! have yt-dlp; then
            err "yt-dlp is required to download the embedded images"
            img_fail=$((img_fail + ${#batch[@]}))
            for u in "${batch[@]}"; do
                ui_result 1 "$(ui_name "$u")"
            done
            continue
        fi

        declare -a yt_img=( "${yt_common[@]}" --downloader "http,https:native"
            -P "home:$dir" -P "temp:$tmp_dir"
            --referer "$ref" --user-agent "${ua:-$img_ua}" )
        for u in "${batch[@]}"; do
            if name=$(url_filename "$u"); then
                name=${name//%/%%}
            else
                name='%(title)s.%(ext)s'
            fi
            u_rc=0
            yt-dlp "${yt_img[@]}" ${passthru[@]+"${passthru[@]}"} -o "$name" "$u" 2>&1 | yt_bar || u_rc=$?
            (( u_rc )) && rc=$u_rc
            if (( u_rc )); then
                img_fail=$((img_fail + 1))
            else
                img_ok=$((img_ok + 1))
            fi
            ui_result $u_rc "$(ui_name "$u")"
        done
    done
}
