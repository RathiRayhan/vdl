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
# Light preflight for --images: probe each media page's extractor once, so
# image-only pages can be removed from the media queue before yt-dlp runs,
# and known-site extractors can be skipped later.  The heavy page scan and
# the image downloads happen after the media downloads (see scrape_images).
#
# Note: scan_pages/scan_do/scan_title are declared by bin/vdl and filled here.
preflight_images() {
    img_urls=()
    img_refs=()
    img_dirs=()
    scan_pages=()
    scan_do=()
    scan_title=()
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

        scan_pages+=("$u")
        probe_out=$(yt-dlp --ignore-config --quiet --simulate -I 1 \
            --print '%(extractor)s|%(playlist_title)s' -- "$u" 2>&1)
        probe_rc=$?
        extractor=${probe_out##*$'\n'}
        extractor=${extractor%%|*}
        album_title=${probe_out##*$'\n'}
        album_title=${album_title#*|}
        [[ $probe_rc == 0 ]] || album_title=''
        [[ $album_title == NA ]] && album_title=''
        scan_title["$u"]=$album_title
        images_only=0
        case $probe_out in
            *"Unsupported URL"*|*"No video formats found"*)
                [[ $probe_rc != 0 ]] && images_only=1
                ;;
        esac
        if [[ $probe_rc == 0 && -n $extractor ]] \
            && [[ $extractor != generic && $extractor != generic:* && $extractor != html5 ]]; then
            # known-site extractor: never scan
            media_kept+=("$u")
            continue
        fi
        scan_do["$u"]=1
        if (( images_only )); then
            # yt-dlp has nothing to download for this page; scan it for
            # images after the media phase instead of failing on it.
            note "No video formats on page — images will be scanned after the downloads"
            if [[ -n $custom_name ]]; then
                note "--name ignored: this page only yields embedded images"
                custom_name=''
                custom_direct=''
                custom_media=''
            fi
        else
            media_kept+=("$u")
        fi
    done
    media=("${media_kept[@]}")
}

# The heavy part of --images, run after the media downloads: fetch each
# queued page, extract the album's images, and queue them for
# download_images.  Pages skipped by preflight_images are left alone, and
# --dry-run never touches the network.
scrape_images() {
    if (( ${#scan_pages[@]} == 0 )); then
        return 0
    fi

    for u in "${scan_pages[@]}"; do
        [[ -n ${scan_do["$u"]:-} ]] || continue

        note "Scanning page for embedded images: $u"

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
            --print '%(url)s' -- "$u" 2>/dev/null)

        curl_args=( -sL --max-time 30 )
        [[ -n $ua ]] && curl_args+=( -A "$ua" )
        [[ -n $referer ]] && curl_args+=( -e "$referer" )
        [[ -n $proxy ]] && curl_args+=( -x "$proxy" )

        if [[ -d ${tmp_dir:-} ]]; then
            page_file=$(mktemp "$tmp_dir/page.XXXXXX") || page_file=''
        else
            page_file=$(mktemp "${TMPDIR:-/tmp}/vdl-page.XXXXXX") || page_file=''
        fi
        if [[ -n $page_file ]]; then
            curl "${curl_args[@]}" -o "$page_file" -- "$u" || true
        fi

        if [[ -n $page_file ]] && grep -aqiE '<(img|html|body|head|a[ >]|video|title)' "$page_file"; then
            # Fall back to the page <title> when yt-dlp has no playlist
            # title, then sanitize it so the image folder matches the one
            # yt-dlp creates for the videos.
            album_title=${scan_title["$u"]}
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
                for q in "${urls[@]}" "${direct[@]}" "${media[@]}" "${gallery[@]}" "${img_urls[@]}"; do
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
                note "Embedded image: $img"
            done < <(if have python3; then
                    python3 "$vdl_lib/scrape.py" "$page_file"
                else
                    # fallback: regex extraction for systems without python3
                    sed -E 's/data-rotate-src="[^"]*"//g' "$page_file" \
                        | sed -E "s/data-rotate-src='[^']*'//g" \
                        | grep -oiE "<img[^>]*(src|data-src)=[\"'][^\"']+\.(jpe?g|png|webp|gif)(\?[^\"']*)?[\"']" \
                        | grep -oE "(src|data-src)=[\"'][^\"']+[\"']" \
                        | sed -E "s/^(src|data-src)=[\"']//; s/[\"']$//" | sed 's/&amp;/\&/g'
                fi)
        fi
        [[ -n $page_file ]] && rm -f -- "$page_file"
    done
}

# Download the images queued by scrape_images, grouped by their source page
# so each group can send the right referer.  aria2c does the work when
# available; missing images fall back to yt-dlp per file.
download_images() {
    if (( ${#img_urls[@]} == 0 )); then
        return 0
    fi

    ui_section "Embedded Images"
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

        # Resolve one unique filename per image in this destination folder.
        # A pre-existing regular file is not this run's download: report it as
        # skipped instead of counting it as a success.  Partials with an
        # .aria2 sidecar stay in the batch so they can be retried.
        declare -A img_name=()
        declare -a img_pending=()
        _claimed_names=()
        for u in "${batch[@]}"; do
            if name=$(url_filename "$u"); then
                claim_run_name "$name"
                name=$_claimed_name
                img_name[$u]=$name
                dest=$dir/$name
                if [[ -f $dest && ! -e ${dest}.aria2 ]]; then
                    case ${on_collision:-skip} in
                        rename)
                            claim_free_name "$dir" "$name"
                            name=$_claimed_name
                            img_name[$u]=$name
                            dest=$dir/$name
                            ;;
                        overwrite)
                            : # keep the requested path and let the engine replace it
                            ;;
                        fail)
                            img_fail=$((img_fail + 1))
                            failed_items+=("$u|destination already exists")
                            (( rc )) || rc=1
                            if (( use_aria )); then
                                report_item "$u" aria2c failed "$dest" "destination already exists"
                            else
                                report_item "$u" yt-dlp failed "$dest" "destination already exists"
                            fi
                            ui_result 1 "$(ui_name "$u")"
                            continue
                            ;;
                        *)
                            if manifest_has_file "$dest"; then
                                # Another page already downloaded this
                                # basename in the same folder during this run;
                                # keep both images.
                                claim_free_name "$dir" "$name"
                                name=$_claimed_name
                                img_name[$u]=$name
                                dest=$dir/$name
                            else
                                img_skip=$((img_skip + 1))
                                if (( use_aria )); then
                                    report_item "$u" aria2c skipped "$dest" "destination already exists"
                                else
                                    report_item "$u" yt-dlp skipped "$dest" "destination already exists"
                                fi
                                ui_skip "$(ui_name "$u")"
                                continue
                            fi
                            ;;
                    esac
                fi
            else
                img_name[$u]=''
            fi
            img_pending+=("$u")
        done
        batch=("${img_pending[@]}")
        (( ${#batch[@]} )) || continue

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
            if [[ ${on_collision:-skip} == overwrite ]]; then
                img_aria+=( --allow-overwrite=true --auto-file-renaming=false --continue=false )
            fi
            (( quiet )) && img_aria+=( --quiet=true )
            if [[ -n ${aria_hook:-} && -x $aria_hook ]]; then
                img_aria+=( "--on-download-complete=$aria_hook" )
            fi
            if (( ${json_output:-0} )); then
                aria2c "${img_aria[@]}" "${batch[@]}" 1>&2 || img_rc=$?
            else
                aria2c "${img_aria[@]}" "${batch[@]}" || img_rc=$?
            fi
        fi

        if (( img_rc == 0 )) && (( use_aria )); then
            for u in "${batch[@]}"; do
                name=${img_name[$u]:-}
                ui_result 0 "$(ui_name "$u")"
                report_item "$u" aria2c ok "${name:+$dir/$name}" ""
            done
            img_ok=$((img_ok + ${#batch[@]}))
            continue
        fi

        if (( use_aria )); then
            # Only retry the images that are still incomplete; -Z downloads
            # sequentially, so some may have completed before the failure.
            # Completed images are counted separately from retried/failed
            # ones, but only when they were produced by this run (pre-existing
            # files were filtered out above).
            declare -a retry_batch=()
            for u in "${batch[@]}"; do
                name=${img_name[$u]:-}
                if [[ -n $name ]]; then
                    dest=$dir/$name
                    if [[ -e "${dest}.aria2" ]]; then
                        if have yt-dlp; then
                            rm -f -- "${dest}.aria2" "$dest"
                            retry_batch+=("$u")
                        else
                            img_fail=$((img_fail + 1))
                            failed_items+=("$u|aria2c failed; partial kept for resume")
                            (( rc )) || rc=1
                            report_item "$u" aria2c failed "" "aria2c failed; partial kept for resume"
                            ui_result 1 "$(ui_name "$u")"
                        fi
                        continue
                    elif [[ -s "$dest" ]]; then
                        img_ok=$((img_ok + 1))
                        report_item "$u" aria2c ok "$dest" ""
                        ui_result 0 "$(ui_name "$u")"
                        continue
                    else
                        rm -f -- "$dest"
                    fi
                fi
                retry_batch+=("$u")
            done
            if (( ${#retry_batch[@]} == 0 )); then
                continue
            fi
            batch=("${retry_batch[@]}")
            warn "aria2c failed (exit $img_rc) — retrying ${#batch[@]} image(s) via yt-dlp"
        fi

        if ! have yt-dlp; then
            err "yt-dlp is required to download the embedded images"
            (( rc )) || rc=1
            img_fail=$((img_fail + ${#batch[@]}))
            for u in "${batch[@]}"; do
                failed_items+=("$u|yt-dlp not found")
                report_item "$u" yt-dlp failed "" "yt-dlp not found"
                ui_result 1 "$(ui_name "$u")"
            done
            continue
        fi

        declare -a yt_img=( "${yt_common[@]}" --downloader "http,https:native"
            -P "home:$dir"
            --referer "$ref" --user-agent "${ua:-$img_ua}" )
        [[ -n ${run_manifest:-} ]] && yt_img+=( --print-to-file after_move:filepath "${run_manifest//%/%%}" )
        local yt_name u_log url_tmp label
        local -a partial_args=()
        for u in "${batch[@]}"; do
            name=${img_name[$u]:-}
            label=${name:-$(ui_name "$u")}
            if [[ -n $name ]]; then
                yt_name=${name//%/%%}
            else
                yt_name='%(title)s.%(ext)s'
            fi

            url_tmp=$(partial_dir_for "img|$dir|$name|$u")
            if [[ -n $url_tmp ]] && mkdir -p -- "$url_tmp"; then
                partial_args=( -P "temp:$url_tmp" )
            else
                partial_args=()
                url_tmp=''
            fi

            u_log=''
            if [[ -d ${tmp_dir:-} ]]; then
                u_log=$(mktemp "$tmp_dir/img.log.XXXXXX") || u_log=''
            fi
            u_rc=0
            if (( ${json_output:-0} )); then
                if [[ -n $u_log ]]; then
                    yt-dlp "${yt_img[@]}" ${passthru[@]+"${passthru[@]}"} \
                        "${partial_args[@]}" -o "$yt_name" "$u" 2>&1 \
                        | tee "$u_log" >&2 || u_rc=$?
                else
                    yt-dlp "${yt_img[@]}" ${passthru[@]+"${passthru[@]}"} \
                        "${partial_args[@]}" -o "$yt_name" "$u" >/dev/null 2>&1 || u_rc=$?
                fi
            elif [[ -n $u_log ]]; then
                yt-dlp "${yt_img[@]}" ${passthru[@]+"${passthru[@]}"} \
                    "${partial_args[@]}" -o "$yt_name" "$u" 2>&1 \
                    | tee "$u_log" | yt_bar || u_rc=$?
            else
                yt-dlp "${yt_img[@]}" ${passthru[@]+"${passthru[@]}"} \
                    "${partial_args[@]}" -o "$yt_name" "$u" 2>&1 \
                    | yt_bar || u_rc=$?
            fi
            (( u_rc )) && rc=$u_rc

            if (( u_rc )); then
                img_fail=$((img_fail + 1))
                failed_items+=("$u|yt-dlp exit $u_rc")
                report_item "$u" yt-dlp failed "" "yt-dlp exit $u_rc"
                ui_result 1 "$label"
            elif [[ -n $u_log ]] && grep -qF 'already been downloaded' "$u_log"; then
                if [[ ${on_collision:-skip} == fail ]]; then
                    img_fail=$((img_fail + 1))
                    failed_items+=("$u|destination already exists")
                    (( rc )) || rc=1
                    report_item "$u" yt-dlp failed "${name:+$dir/$name}" "destination already exists"
                    ui_result 1 "$label"
                else
                    img_skip=$((img_skip + 1))
                    report_item "$u" yt-dlp skipped "${name:+$dir/$name}" "destination already exists"
                    ui_skip "$label"
                fi
            else
                img_ok=$((img_ok + 1))
                report_item "$u" yt-dlp ok "${name:+$dir/$name}" ""
                ui_result 0 "$label"
            fi

            [[ -n $u_log ]] && rm -f -- "$u_log"
            if (( u_rc == 0 )) && [[ -n $url_tmp ]]; then
                rm -rf -- "$url_tmp"
            fi
        done
    done
}
