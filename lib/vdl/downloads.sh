#!/usr/bin/env bash
# shellcheck shell=bash
# shellcheck disable=SC2154,SC2034,SC2329  # globals live in bin/vdl; functions invoked from there
#
# vdl download engines: direct files via aria2c (with yt-dlp fallback),
# pending direct files via yt-dlp, media/pages via yt-dlp, and the --dedupe
# post-step.  Sourced by bin/vdl.

# With --zip: archive the files downloaded in this run into a single zip in
# the save directory.  Runs after dedupe so duplicates are not archived.
archive_run() {
    (( zip_mode )) || return 0

    have zip || { warn "zip is not installed: skipping --zip archive"; return 0; }

    local -a entries=()
    local f
    while IFS= read -r -d '' f; do
        case ${f##*/} in
            *.aria2|*.part|*.ytdl|*.temp) continue ;;
        esac
        entries+=("$f")
    done < <(find "$save_dir" -type f -newermt "@$dedupe_mark" \
        ! -path "$tmp_dir" ! -path "$tmp_dir/*" -print0 2>/dev/null)

    if (( ${#entries[@]} == 0 )); then
        note "--zip: no files were downloaded in this run; nothing to archive"
        return 0
    fi

    local target=$zip_name
    if [[ -z $target ]]; then
        target="vdl-$(date +%Y%m%d-%H%M%S).zip"
    elif [[ $target != *.zip ]]; then
        target=$target.zip
    fi
    if [[ $target == */* ]]; then
        mkdir -p "$save_dir/${target%/*}" || return 0
    fi

    rm -f -- "$save_dir/$target"
    if ( cd "$save_dir" && zip -q -r -- "$target" "${entries[@]#"$save_dir"/}" ); then
        zip_created=$target
        note "Archived ${#entries[@]} file(s) to ${target}"
    else
        warn "zip failed — files were left in place"
    fi
}

# With --dedupe: remove files created during this run whose content is
# identical to another file from the same run.  Only same-size files are
# hashed, and the oldest copy is always kept, so a file that already existed
# before this run can never be removed.
dedupe_saved() {
    (( dedupe )) || return 0

    local f size h dt keep keep_t
    local -A size_groups=()
    local -a files
    local -A hash_groups

    while IFS= read -r -d '' f; do
        case ${f##*/} in
            *.aria2|*.part|*.ytdl|*.temp) continue ;;
        esac
        size=$(stat -c %s -- "$f" 2>/dev/null) || continue
        size_groups[$size]+=$f$'\n'
    done < <(find "$save_dir" -type f -newermt "@$dedupe_mark" \
        ! -path "$tmp_dir" ! -path "$tmp_dir/*" -print0 2>/dev/null)

    for size in "${!size_groups[@]}"; do
        mapfile -t files <<< "${size_groups[$size]%$'\n'}"
        (( ${#files[@]} > 1 )) || continue
        hash_groups=()
        for f in "${files[@]}"; do
            h=$(sha256sum -- "$f" 2>/dev/null | awk '{print $1}') || continue
            [[ -n $h ]] && hash_groups[$h]+=$f$'\n'
        done
        for h in "${!hash_groups[@]}"; do
            mapfile -t files <<< "${hash_groups[$h]%$'\n'}"
            (( ${#files[@]} > 1 )) || continue
            keep=${files[0]}
            keep_t=$(stat -c %Y -- "$keep" 2>/dev/null || echo 0)
            for f in "${files[@]:1}"; do
                dt=$(stat -c %Y -- "$f" 2>/dev/null || echo 0)
                if (( dt < keep_t )); then
                    rm -f -- "$keep"
                    note "Removed duplicate: ${keep#"$save_dir"/} (same content as ${f#"$save_dir"/})"
                    keep=$f
                    keep_t=$dt
                else
                    rm -f -- "$f"
                    note "Removed duplicate: ${f#"$save_dir"/} (same content as ${keep#"$save_dir"/})"
                fi
            done
        done
    done
}

# Direct files via aria2c.  On failure, mark which files are incomplete so
# download_pending_directs() can retry only those.
download_directs() {
    if (( ${#direct[@]} == 0 )) || (( direct_via_ytdlp )); then
        return 0
    fi

    aria_attempted=1
    ui_section "Direct downloads via aria2c"
    for u in "${direct[@]}"; do
        ui_item "$(ui_name "$u")"
    done

    declare -a aria_args=(
        -x 16 -s 16 -k 1M
        --continue=true
        --file-allocation=none
        -d "$save_dir"
    )
    # aria2c ignores -o when -Z is used, so pick one or the other: a custom
    # name implies a single URL, which does not need -Z anyway.
    if [[ -n ${custom_direct:-} ]]; then
        aria_args+=( -o "$custom_direct" )
    else
        aria_args+=( -Z )
    fi
    [[ -n $ua ]] && aria_args+=( "--user-agent=$ua" )
    [[ -n $referer ]] && aria_args+=( "--referer=$referer" )
    [[ -n $proxy ]] && aria_args+=( "--all-proxy=$proxy" )
    (( quiet )) && aria_args+=( --quiet=true )
    if [[ -n $max_speed_bytes ]]; then
        aria_args+=( "--max-overall-download-limit=$max_speed_bytes" )
    fi
    if [[ -n $limit_speed_bytes ]]; then
        aria_args+=( "--max-download-limit=$limit_speed_bytes" )
    fi
    # Parse --aria-opts as space-separated; use word splitting intentionally.
    if [[ -n $aria_opts ]]; then
        # shellcheck disable=SC2206,SC2086  # deliberate word splitting of user-provided opts
        aria_args+=($aria_opts)
    fi

    aria_rc=0
    aria2c "${aria_args[@]}" "${direct[@]}" || aria_rc=$?
    if (( aria_rc == 0 )); then
        direct_ok=${#direct[@]}
        for u in "${direct[@]}"; do
            ui_result 0 "$(ui_name "$u")"
        done
        return 0
    fi

    direct_pending=()
    for u in "${direct[@]}"; do
        # yt-dlp cannot fetch magnet/torrent payloads; report those
        # failures instead of retrying the wrong thing.
        case ${u,,} in
            magnet:*|*.torrent)
                direct_fail=$((direct_fail + 1))
                ui_result 1 "$(ui_name "$u")"
                continue
                ;;
        esac

        if name=$(url_filename "$u"); then
            dest=$save_dir/$name
            if [[ -f ${dest}.aria2 ]]; then
                # Remove the incomplete file and its control file before
                # retrying.  yt-dlp with --no-overwrites would otherwise
                # mistake the aria2c partial for a completed download.
                rm -f -- "${dest}.aria2" "$dest"
                direct_pending+=("$u")
            elif [[ ! -f $dest ]]; then
                direct_pending+=("$u")
            else
                direct_ok=$((direct_ok + 1))
                ui_result 0 "$name"
            fi
        else
            direct_pending+=("$u")
        fi
    done

    if (( ${#direct_pending[@]} )); then
        direct_via_ytdlp=1
        warn "aria2c failed (exit $aria_rc) — retrying ${#direct_pending[@]} incomplete direct download(s) via yt-dlp"
    else
        warn "aria2c failed (exit $aria_rc) but no incomplete HTTP(S) downloads were found"
        rc=$aria_rc
    fi
}

# Direct downloads via yt-dlp: the no-aria2c/--no-aria path, or the retry of
# the files download_directs() could not finish.
download_pending_directs() {
    if (( ${#direct_pending[@]} == 0 )); then
        return 0
    fi

    ui_section "Direct downloads via yt-dlp"
    if ! have yt-dlp; then
        err "yt-dlp is required to retry the failed direct download(s)"
        rc=1
        direct_fail=$((direct_fail + ${#direct_pending[@]}))
        for u in "${direct_pending[@]}"; do
            ui_result 1 "$(ui_name "$u")"
        done
        return 0
    fi

    declare -a yt_direct=( "${yt_common[@]}" --downloader "http,https:native" )
    yt_direct+=( -P "home:$save_dir" -P "temp:$tmp_dir" )
    if [[ $browser != none ]]; then
        yt_direct+=( --cookies-from-browser "$browser" )
    fi
    [[ -n $impersonate ]] && yt_direct+=( --impersonate "$impersonate" )
    [[ -n $ua ]] && yt_direct+=( --user-agent "$ua" )
    [[ -n $referer ]] && yt_direct+=( --referer "$referer" )
    [[ -n $proxy ]] && yt_direct+=( --proxy "$proxy" )

    # yt-dlp's generic extractor calls unknown file types "unknown_video".
    # Use the URL basename so direct files keep their real name, unless a
    # custom name was requested.
    for u in "${direct_pending[@]}"; do
        if [[ -n ${custom_direct:-} ]]; then
            name=$custom_direct
        elif name=$(url_filename "$u"); then
            name=${name//%/%%}
        else
            name='%(title)s.%(ext)s'
        fi
        (( aria_attempted )) || ui_item "$(ui_name "$u")"
        u_rc=0
        yt-dlp "${yt_direct[@]}" ${passthru[@]+"${passthru[@]}"} -o "$name" "$u" 2>&1 | yt_bar || u_rc=$?
        (( u_rc )) && rc=$u_rc
        if (( u_rc )); then
            direct_fail=$((direct_fail + 1))
        else
            direct_ok=$((direct_ok + 1))
        fi
        ui_result $u_rc "$(ui_name "$u")"
    done
}

# Media / page downloads via yt-dlp (single invocation for the whole batch).
download_media() {
    if (( ${#media[@]} == 0 )); then
        return 0
    fi

    ui_section "Media / page downloads via yt-dlp"
    for u in "${media[@]}"; do
        ui_item "$u"
    done

    declare -a yt_media=( "${yt_common[@]}" )

    if (( have_aria && ! no_aria )); then
        aria_dl_args="aria2c:-x 10 -s 10 -k 1M --file-allocation=none --summary-interval=0"
        [[ -n $max_speed_bytes ]]   && aria_dl_args+=" --max-overall-download-limit=$max_speed_bytes"
        [[ -n $limit_speed_bytes ]] && aria_dl_args+=" --max-download-limit=$limit_speed_bytes"
        (( quiet )) && aria_dl_args+=" --quiet=true"
        yt_media+=(
            --downloader "http,https:aria2c"
            --downloader-args "$aria_dl_args"
        )
    else
        yt_media+=( --downloader "http,https:native" )
    fi
    yt_media+=( --downloader "dash,m3u8:native" -N 8 )

    if [[ $browser != none ]]; then
        yt_media+=( --cookies-from-browser "$browser" )
    fi
    [[ -n $impersonate ]] && yt_media+=( --impersonate "$impersonate" )
    [[ -n $ua ]] && yt_media+=( --user-agent "$ua" )
    [[ -n $referer ]] && yt_media+=( --referer "$referer" )
    [[ -n $proxy ]] && yt_media+=( --proxy "$proxy" )

    # The item template: with --output FOLDER the playlist title prefix is
    # dropped so everything lands directly in that folder.
    if (( ${out_folder_strip:-0} )); then
        media_out_template='%(playlist_index&{} - |)s%(title).80B [%(id)s].%(ext)s'
    elif (( audio )); then
        media_out_template='%(playlist_title)s/%(playlist_index&{} - |)s%(title).80B [%(id)s].%(ext)s'
    else
        media_out_template='%(playlist_title,album)s/%(playlist_index&{} - |)s%(title).80B [%(id)s].%(ext)s'
    fi

    if (( audio )); then
        yt_media+=(
            -f 'bestaudio/best'
            -x --audio-format mp3 --audio-quality 320K
            --embed-metadata --embed-thumbnail
            -P "home:$out_dir"
            -P "temp:$tmp_dir"
            --output-na-placeholder '.'
            -o "$media_out_template"
        )
    else
        yt_media+=(
            -f "bv*[height<=${quality}]+ba/b[height<=${quality}]/b"
            -S 'ext:mp4:m4a'
            --merge-output-format mp4
            --embed-metadata
            -P "home:$save_dir"
            -P "temp:$tmp_dir"
            --output-na-placeholder '.'
            -o "$media_out_template"
        )
    fi
    # A custom name overrides the default template (the last -o wins).
    [[ -n ${custom_media:-} ]] && yt_media+=( -o "$custom_media" )

    media_rc=0
    yt-dlp "${yt_media[@]}" ${passthru[@]+"${passthru[@]}"} "${media[@]}" 2>&1 | yt_bar || media_rc=$?
    (( media_rc )) && rc=$media_rc
    if (( media_rc == 0 )); then
        media_ok=${#media[@]}
    else
        media_fail=${#media[@]}
    fi
    for u in "${media[@]}"; do
        ui_result $media_rc "$u"
    done
}
