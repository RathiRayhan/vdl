#!/usr/bin/env bash
# shellcheck shell=bash
# shellcheck disable=SC2154,SC2034,SC2329  # globals live in bin/vdl; functions invoked from there
#
# vdl download engines: direct files via aria2c (with yt-dlp fallback),
# pending direct files via yt-dlp, media/pages via yt-dlp, and the --dedupe
# post-step.  Sourced by bin/vdl.

# Record pre-existing files in save_dir before any downloader runs so --dedupe
# and --zip can never act on files that already existed untouched before this
# invocation.
snapshot_save_dir() {
    (( dedupe || zip_mode )) || return 0
    local root_dir=${save_dir_abs:-$save_dir}
    [[ -d $root_dir ]] || return 0
    local meta path
    while IFS= read -r -d '' meta && IFS= read -r -d '' path; do
        [[ -n $path ]] && pre_files["$path"]=$meta
    done < <(find "$root_dir" -type f -exec stat --printf='%d:%i:%s:%y:%z\0%n\0' {} + 2>/dev/null)
}

# Collect canonical paths of files created or updated during this run from the
# explicit downloader completion manifest, excluding partials and untouched
# pre-existing files.
collect_run_files() {
    run_files=()
    [[ -n ${run_manifest:-} && -f $run_manifest ]] || return 0

    local line abs_p cur_meta
    local -A seen_p=()
    while IFS= read -r line || [[ -n $line ]]; do
        [[ -n $line ]] || continue
        case ${line##*/} in
            *.aria2|*.part|*.ytdl|*.temp) continue ;;
        esac
        abs_p=$(readlink -f -- "$line" 2>/dev/null || printf '%s\n' "$line")
        [[ -f $abs_p ]] || continue
        [[ -n ${seen_p["$abs_p"]+x} ]] && continue
        seen_p["$abs_p"]=1

        if [[ -n ${pre_files["$abs_p"]+x} ]]; then
            cur_meta=$(stat -c '%d:%i:%s:%y:%z' -- "$abs_p" 2>/dev/null || true)
            [[ -n $cur_meta && $cur_meta == "${pre_files["$abs_p"]}" ]] && continue
        fi
        run_files+=("$abs_p")
    done < "$run_manifest"
}

# Is this exact path recorded as completed in this run's manifest?
manifest_has_file() {
    local want=$1 line abs
    [[ -n ${run_manifest:-} && -f $run_manifest ]] || return 1
    want=$(readlink -f -- "$want" 2>/dev/null) || want=$1
    while IFS= read -r line || [[ -n $line ]]; do
        [[ -n $line ]] || continue
        abs=$(readlink -f -- "$line" 2>/dev/null) || abs=$line
        [[ $abs == "$want" ]] && return 0
    done < "$run_manifest"
    return 1
}

manifest_line_count() {
    [[ -f ${run_manifest:-} ]] || { printf '0\n'; return 0; }
    wc -l < "$run_manifest"
}

# Populate NEW_FILES with paths appended to the manifest after line START.
manifest_files_since() {
    local start=$1 line i=0
    NEW_FILES=()
    [[ -f ${run_manifest:-} ]] || return 0
    while IFS= read -r line || [[ -n $line ]]; do
        i=$((i + 1))
        (( i > start )) || continue
        [[ -f $line ]] && NEW_FILES+=("$line")
    done < "$run_manifest"
}

manifest_new_files_string() {
    local f out=''
    for f in "${NEW_FILES[@]}"; do
        out+=$f$'\n'
    done
    printf '%s' "$out"
}

# With --zip: archive the files downloaded in this run into a single zip in
# the save directory.  Runs after dedupe so duplicates are not archived.
archive_run() {
    (( zip_mode )) || return 0

    local root_dir=${save_dir_abs:-$save_dir}
    local base_prefix=$root_dir/
    [[ $root_dir == / ]] && base_prefix=/

    collect_run_files
    local -a rel_entries=()
    local f
    for f in "${run_files[@]}"; do
        if [[ $f == "$base_prefix"* ]]; then
            rel_entries+=("${f#"$base_prefix"}")
        fi
    done

    if (( ${#rel_entries[@]} == 0 )); then
        note "--zip: no files were downloaded in this run; nothing to archive"
        return 0
    fi

    if ! have zip; then
        warn "zip is not installed: cannot create the requested archive"
        archive_fail=1
        return 0
    fi

    local target=$zip_name
    if [[ -z $target ]]; then
        target="vdl-$(date +%Y%m%d-%H%M%S).zip"
    else
        if ! validate_zip_name "$target"; then
            warn "Refusing unsafe archive name: $target"
            archive_fail=1
            return 0
        fi
        [[ $target != *.zip ]] && target=$target.zip
        if ! validate_zip_name "$target"; then
            warn "Refusing unsafe archive name: $target"
            archive_fail=1
            return 0
        fi
    fi

    local target_path=$root_dir/$target target_cmp
    target_cmp=$(readlink -f -- "$target_path" 2>/dev/null) || target_cmp=$target_path
    if [[ -d $target_path ]]; then
        warn "Refusing archive name '$target': destination is a directory"
        archive_fail=1
        return 0
    fi
    for f in "${run_files[@]}"; do
        if [[ $f == "$target_cmp" ]]; then
            warn "Refusing archive name '$target': it matches a file downloaded in this run"
            archive_fail=1
            return 0
        fi
    done

    # Build the archive under a temporary name and move it into place only
    # after zip succeeds.  A failed archive must never delete an existing
    # destination (or a downloaded file with the requested name).
    archive_tmp=$(mktemp "$root_dir/.vdl-archive.XXXXXX") || {
        warn "could not create a temporary archive in $root_dir"
        archive_fail=1
        return 0
    }
    rm -f -- "$archive_tmp"
    if ( cd -- "$root_dir" && zip -q -r "$archive_tmp" -- "${rel_entries[@]}" ); then
        if mv -f -- "$archive_tmp" "$target_path"; then
            archive_tmp=''
            zip_created=$target
            note "Archived ${#rel_entries[@]} file(s) to ${target}"
        else
            warn "archive was created but could not be moved into place"
            rm -f -- "$archive_tmp"
            archive_tmp=''
            archive_fail=1
        fi
    else
        warn "zip failed — files were left in place"
        rm -f -- "$archive_tmp"
        archive_tmp=''
        archive_fail=1
    fi
}

# With --dedupe: remove files created during this run whose content is
# identical to another file from the same run.  Only same-size files are
# hashed, and the oldest copy is always kept, so a file that already existed
# before this run can never be removed.
dedupe_saved() {
    (( dedupe )) || return 0

    local root_dir=${save_dir_abs:-$save_dir}
    local base_prefix=$root_dir/
    [[ $root_dir == / ]] && base_prefix=/

    collect_run_files
    local f size h dt keep keep_t
    local -A size_groups=()
    local -a files
    local -A hash_groups

    for f in "${run_files[@]}"; do
        size=$(stat -c %s -- "$f" 2>/dev/null) || continue
        size_groups[$size]+=$f$'\n'
    done

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
                    note "Removed duplicate: ${keep#"$base_prefix"} (same content as ${f#"$base_prefix"})"
                    keep=$f
                    keep_t=$dt
                else
                    rm -f -- "$f"
                    note "Removed duplicate: ${f#"$base_prefix"} (same content as ${keep#"$base_prefix"})"
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

    local u name
    local -a aria_queue=()
    if [[ ${on_collision:-skip} == skip ]]; then
        for u in "${direct[@]}"; do
            name=${direct_dest[$u]:-}
            if [[ -n $name && -f $save_dir/$name && ! -e $save_dir/${name}.aria2 ]]; then
                direct_skip=$((direct_skip + 1))
                ui_skip "$name"
                report_item "$u" aria2c skipped "$save_dir/$name" "destination already exists"
                continue
            fi
            aria_queue+=("$u")
        done
    else
        aria_queue=("${direct[@]}")
    fi
    (( ${#aria_queue[@]} )) || return 0

    aria_attempted=1
    ui_section "Direct Downloads via aria2c"
    for u in "${aria_queue[@]}"; do
        ui_item "$(ui_name "$u")"
    done

    declare -a aria_args=(
        -x 16 -s 16 -k 1M
        --continue=true
        --file-allocation=none
        -d "$save_dir"
    )
    local per_url_mode=0 aria_rc=0 urc
    if [[ -n ${custom_direct:-} || ${on_collision:-skip} == rename ]]; then
        per_url_mode=1
    else
        aria_args+=( -Z )
    fi
    if [[ ${on_collision:-skip} == overwrite ]]; then
        # --continue=true treats an existing complete file as done without
        # fetching it; overwrite needs a fresh request.
        aria_args+=( --allow-overwrite=true --auto-file-renaming=false --continue=false )
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
    if [[ -n ${aria_hook:-} && -x $aria_hook ]]; then
        aria_args+=( "--on-download-complete=$aria_hook" )
    fi
    # Parse --aria-opts as space-separated; use word splitting intentionally.
    if [[ -n $aria_opts ]]; then
        # shellcheck disable=SC2206,SC2086  # deliberate word splitting of user-provided opts
        aria_args+=($aria_opts)
    fi

    if [[ -d ${tmp_dir:-} ]]; then
        aria_log=$(mktemp "$tmp_dir/aria.log.XXXXXX") || aria_log=''
    else
        aria_log=$(mktemp) || aria_log=''
    fi
    if (( per_url_mode )); then
        local -a aria_this=()
        for u in "${aria_queue[@]}"; do
            name=${direct_dest[$u]:-}
            aria_this=( "${aria_args[@]}" )
            [[ -n $name ]] && aria_this+=( -o "$name" )
            urc=0
            if [[ -n $aria_log ]]; then
                if (( ${json_output:-0} )); then
                    aria2c "${aria_this[@]}" "$u" 2>&1 | tee -a "$aria_log" >&2 || urc=$?
                else
                    aria2c "${aria_this[@]}" "$u" 2>&1 | tee -a "$aria_log" || urc=$?
                fi
            elif (( ${json_output:-0} )); then
                aria2c "${aria_this[@]}" "$u" >/dev/null 2>&1 || urc=$?
            else
                aria2c "${aria_this[@]}" "$u" || urc=$?
            fi
            if (( urc )); then
                (( aria_rc )) || aria_rc=$urc
            fi
        done
    elif [[ -n $aria_log ]]; then
        if (( ${json_output:-0} )); then
            aria2c "${aria_args[@]}" "${aria_queue[@]}" 2>&1 | tee "$aria_log" >&2 || aria_rc=$?
        else
            aria2c "${aria_args[@]}" "${aria_queue[@]}" 2>&1 | tee "$aria_log" || aria_rc=$?
        fi
    elif (( ${json_output:-0} )); then
        aria2c "${aria_args[@]}" "${aria_queue[@]}" >/dev/null 2>&1 || aria_rc=$?
    else
        aria2c "${aria_args[@]}" "${aria_queue[@]}" || aria_rc=$?
    fi
    if (( aria_rc == 0 )); then
        direct_ok=${#aria_queue[@]}
        for u in "${aria_queue[@]}"; do
            name=${direct_dest[$u]:-}
            ui_result 0 "$(ui_name "$u")"
            report_item "$u" aria2c ok "${name:+$save_dir/$name}" ""
        done
        rm -f -- "$aria_log"
        return 0
    fi
    [[ -n $aria_log ]] && grep -qiE 'cloudflare|403[^0-9]*forbidden' "$aria_log" && cf_challenge=1
    rm -f -- "$aria_log"

    direct_pending=()
    for u in "${aria_queue[@]}"; do
        # yt-dlp cannot fetch magnet/torrent payloads; report those
        # failures instead of retrying the wrong thing.
        local lower_u=${u,,}
        lower_u=${lower_u%%\?*}
        lower_u=${lower_u%%#*}
        case $lower_u in
            magnet:*|*.torrent)
                direct_fail=$((direct_fail + 1))
                failed_items+=("$u|aria2c failed")
                (( rc )) || rc=1
                report_item "$u" aria2c failed "" "aria2c failed"
                ui_result 1 "$(ui_name "$u")"
                continue
                ;;
        esac

        name=${direct_dest[$u]:-}
        if [[ -n $name ]]; then
            dest=$save_dir/$name
            if manifest_has_file "$dest"; then
                # This run's aria2c hook recorded the file, so it completed
                # even though the batch exited nonzero.
                direct_ok=$((direct_ok + 1))
                ui_result 0 "$name"
                report_item "$u" aria2c ok "$dest" ""
            elif [[ -f ${dest}.aria2 ]] || [[ ! -e $dest ]]; then
                # Remove the incomplete file and its control file before
                # retrying.  yt-dlp with --no-overwrites would otherwise
                # mistake the aria2c partial for a completed download.
                # When yt-dlp is unavailable, keep the partial so a later
                # run can resume it with aria2c.
                if [[ -f ${dest}.aria2 ]] && ! have yt-dlp; then
                    direct_fail=$((direct_fail + 1))
                    failed_items+=("$u|aria2c failed; partial kept for resume")
                    (( rc )) || rc=1
                    report_item "$u" aria2c failed "" "aria2c failed; partial kept for resume"
                    ui_result 1 "$(ui_name "$u")"
                else
                    rm -f -- "${dest}.aria2" "$dest"
                    direct_pending+=("$u")
                fi
            else
                # A destination that predates this run is not a success.  Do
                # not retry it through yt-dlp either; report it explicitly so
                # a stale or conflicting file cannot masquerade as a download.
                direct_skip=$((direct_skip + 1))
                ui_skip "$name"
                report_item "$u" aria2c skipped "$dest" "destination already exists"
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

    ui_section "Direct Downloads via yt-dlp"
    if ! have yt-dlp; then
        err "yt-dlp is required to retry the failed direct download(s)"
        rc=1
        direct_fail=$((direct_fail + ${#direct_pending[@]}))
        for u in "${direct_pending[@]}"; do
            failed_items+=("$u|yt-dlp not found")
            report_item "$u" yt-dlp failed "" "yt-dlp not found"
            ui_result 1 "$(ui_name "$u")"
        done
        return 0
    fi

    declare -a yt_direct=( "${yt_common[@]}" --downloader "http,https:native" )
    yt_direct+=( -P "home:$save_dir" )
    [[ -n ${run_manifest:-} ]] && yt_direct+=( --print-to-file after_move:filepath "${run_manifest//%/%%}" )
    if [[ $browser != none ]]; then
        yt_direct+=( --cookies-from-browser "$browser" )
    fi
    [[ -n $impersonate ]] && yt_direct+=( --impersonate "$impersonate" )
    [[ -n $ua ]] && yt_direct+=( --user-agent "$ua" )
    [[ -n $referer ]] && yt_direct+=( --referer "$referer" )
    [[ -n $proxy ]] && yt_direct+=( --proxy "$proxy" )

    # yt-dlp's generic extractor calls unknown file types "unknown_video".
    # Use the resolved basename so direct files keep their real name, unless a
    # custom name was requested.  Duplicate basenames were disambiguated by
    # resolve_direct_names() so a second URL cannot be skipped as "already
    # downloaded" under the first URL's name.
    local u name yt_name u_rc u_log url_tmp label
    local -a partial_args=()
    for u in "${direct_pending[@]}"; do
        if [[ -n ${direct_dest[$u]:-} ]]; then
            name=${direct_dest[$u]}
            yt_name=${name//%/%%}
        else
            name=''
            yt_name='%(title)s.%(ext)s'
        fi
        label=${name:-$(ui_name "$u")}
        (( aria_attempted )) || ui_item "$label"

        # Stable partial directory: an interrupted transfer reuses it on the
        # next invocation instead of starting over in a new run directory.
        url_tmp=$(partial_dir_for "direct|$save_dir|$name|$u")
        if [[ -n $url_tmp ]] && mkdir -p -- "$url_tmp"; then
            partial_args=( -P "temp:$url_tmp" )
        else
            partial_args=()
            url_tmp=''
        fi

        u_log=''
        if [[ -d ${tmp_dir:-} ]]; then
            u_log=$(mktemp "$tmp_dir/direct.log.XXXXXX") || u_log=''
        fi
        u_rc=0
        if (( ${json_output:-0} )); then
            if [[ -n $u_log ]]; then
                yt-dlp "${yt_direct[@]}" ${passthru[@]+"${passthru[@]}"} \
                    "${partial_args[@]}" -o "$yt_name" "$u" 2>&1 \
                    | tee "$u_log" >&2 || u_rc=$?
            else
                yt-dlp "${yt_direct[@]}" ${passthru[@]+"${passthru[@]}"} \
                    "${partial_args[@]}" -o "$yt_name" "$u" >/dev/null 2>&1 || u_rc=$?
            fi
        elif [[ -n $u_log ]]; then
            yt-dlp "${yt_direct[@]}" ${passthru[@]+"${passthru[@]}"} \
                "${partial_args[@]}" -o "$yt_name" "$u" 2>&1 \
                | tee "$u_log" | yt_bar || u_rc=$?
        else
            yt-dlp "${yt_direct[@]}" ${passthru[@]+"${passthru[@]}"} \
                "${partial_args[@]}" -o "$yt_name" "$u" 2>&1 \
                | yt_bar || u_rc=$?
        fi
        (( u_rc )) && rc=$u_rc

        if (( u_rc )); then
            direct_fail=$((direct_fail + 1))
            failed_items+=("$u|yt-dlp exit $u_rc")
            report_item "$u" yt-dlp failed "" "yt-dlp exit $u_rc"
            ui_result 1 "$label"
        elif [[ -n $u_log ]] && grep -qF 'already been downloaded' "$u_log"; then
            # A pre-existing destination is not a completed download from
            # this run.
            if [[ ${on_collision:-skip} == fail ]]; then
                direct_fail=$((direct_fail + 1))
                failed_items+=("$u|destination already exists")
                (( rc )) || rc=1
                report_item "$u" yt-dlp failed "${name:+$save_dir/$name}" "destination already exists"
                ui_result 1 "$label"
            else
                direct_skip=$((direct_skip + 1))
                report_item "$u" yt-dlp skipped "${name:+$save_dir/$name}" "destination already exists"
                ui_skip "$label"
            fi
        else
            direct_ok=$((direct_ok + 1))
            report_item "$u" yt-dlp ok "${name:+$save_dir/$name}" ""
            ui_result 0 "$label"
        fi

        [[ -n $u_log ]] && rm -f -- "$u_log"
        if (( u_rc == 0 )) && [[ -n $url_tmp ]]; then
            rm -rf -- "$url_tmp"
        fi
    done
}

# Media / page downloads via yt-dlp.  Each URL is a separate invocation so a
# failure in one item cannot mark successful items as failed.
download_media() {
    if (( ${#media[@]} == 0 )); then
        return 0
    fi

    ui_section "Media / Page Downloads via yt-dlp"
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
            --output-na-placeholder '.'
            -o "$media_out_template"
        )
    fi
    # A custom name overrides the default template (the last -o wins).
    [[ -n ${custom_media:-} ]] && yt_media+=( -o "$custom_media" )
    [[ -n ${run_manifest:-} ]] && yt_media+=( --print-to-file after_move:filepath "${run_manifest//%/%%}" )

    local u u_rc media_log url_tmp cand g_rc manifest_before
    local gallery_ready=0
    local -a partial_args=()
    for u in "${media[@]}"; do
        manifest_before=$(manifest_line_count)
        url_tmp=$(partial_dir_for "media|$save_dir|$out_dir|$quality|$audio|${out_folder_strip:-0}|${custom_media:-}|$((have_aria && ! no_aria))|$u")
        if [[ -n $url_tmp ]] && mkdir -p -- "$url_tmp"; then
            partial_args=( -P "temp:$url_tmp" )
        else
            partial_args=()
            url_tmp=''
        fi

        media_log=''
        if [[ -d ${tmp_dir:-} ]]; then
            media_log=$(mktemp "$tmp_dir/media.log.XXXXXX") || media_log=''
        fi
        u_rc=0
        if (( ${json_output:-0} )); then
            if [[ -n $media_log ]]; then
                yt-dlp "${yt_media[@]}" ${passthru[@]+"${passthru[@]}"} \
                    "${partial_args[@]}" "$u" 2>&1 \
                    | tee "$media_log" >&2 || u_rc=$?
            else
                yt-dlp "${yt_media[@]}" ${passthru[@]+"${passthru[@]}"} \
                    "${partial_args[@]}" "$u" >/dev/null 2>&1 || u_rc=$?
            fi
        elif [[ -n $media_log ]]; then
            yt-dlp "${yt_media[@]}" ${passthru[@]+"${passthru[@]}"} \
                "${partial_args[@]}" "$u" 2>&1 \
                | tee "$media_log" | yt_bar || u_rc=$?
        else
            yt-dlp "${yt_media[@]}" ${passthru[@]+"${passthru[@]}"} \
                "${partial_args[@]}" "$u" 2>&1 \
                | yt_bar || u_rc=$?
        fi

        if (( u_rc == 0 )); then
            manifest_files_since "$manifest_before"
            if [[ -n $media_log ]] && grep -qF 'already been downloaded' "$media_log" \
                && (( ${#NEW_FILES[@]} == 0 )); then
                if [[ ${on_collision:-skip} == fail ]]; then
                    media_fail=$((media_fail + 1))
                    failed_items+=("$u|destination already exists")
                    rc=1
                    report_item "$u" yt-dlp failed "" "destination already exists"
                    ui_result 1 "$u"
                else
                    media_skip=$((media_skip + 1))
                    ui_skip "$u"
                    report_item "$u" yt-dlp skipped "" "destination already exists"
                fi
            else
                media_ok=$((media_ok + 1))
                ui_result 0 "$u"
                report_item "$u" yt-dlp ok "$(manifest_new_files_string)" ""
            fi
            [[ -n $url_tmp ]] && rm -rf -- "$url_tmp"
            [[ -n $media_log ]] && rm -f -- "$media_log"
            continue
        fi

        [[ -n $media_log ]] && grep -qiE 'cloudflare|403[^0-9]*forbidden' "$media_log" && cf_challenge=1

        # Only an explicit "Unsupported URL" is eligible for gallery-dl.
        # Network/auth/Cloudflare failures stay yt-dlp failures.
        local retry_gallery=0
        if have gallery-dl && (( ! gallery_mode )); then
            while IFS= read -r cand; do
                if [[ $cand == "$u" ]]; then
                    retry_gallery=1
                    break
                fi
            done < <(gallery_unsupported_urls "$media_log")
        fi

        if (( retry_gallery )); then
            if (( ! gallery_ready )); then
                ui_section "Fallback Downloads via gallery-dl"
                build_gallery_common
                gallery_ready=1
            fi
            g_rc=0
            gallery_download_one "$u" || g_rc=$?
            if (( g_rc )); then
                gallery_fail=$((gallery_fail + 1))
                failed_items+=("$u|gallery-dl exit $g_rc")
                rc=$g_rc
                report_item "$u" gallery-dl failed "" "gallery-dl exit $g_rc"
                ui_result 1 "$u"
            else
                manifest_files_since "$manifest_before"
                gallery_ok=$((gallery_ok + 1))
                report_item "$u" gallery-dl ok "$(manifest_new_files_string)" ""
                ui_result 0 "$u"
            fi
            # yt-dlp cannot use this URL, so its partial has no resume value.
            [[ -n $url_tmp ]] && rm -rf -- "$url_tmp"
        else
            media_fail=$((media_fail + 1))
            failed_items+=("$u|yt-dlp exit $u_rc")
            rc=$u_rc
            report_item "$u" yt-dlp failed "" "yt-dlp exit $u_rc"
            ui_result 1 "$u"
        fi
        [[ -n $media_log ]] && rm -f -- "$media_log"
    done
}
