#!/usr/bin/env bash
# shellcheck shell=bash
# shellcheck disable=SC2034,SC2154,SC2329,SC2317  # globals live in bin/vdl or the libs; trap handlers
#
# vdl paths and dependencies: save directory, temp dir with its cleanup
# traps, Ctrl+C handler, and the --output repointing.

setup_paths() {
    # The default save directory doubles as the base for bare --download-dir
    # names: "custom-dir" lands inside the vdl folder, not the current
    # working directory.
    download_base=''
    if have xdg-user-dir; then
        download_base=$(xdg-user-dir DOWNLOAD 2>/dev/null) || download_base=''
    fi
    if [[ -z $download_base || $download_base == "$HOME" ]]; then
        download_base=$HOME/Downloads
    fi
    default_dir=$download_base/vdl

    local dir
    dir=''
    [[ -n $download_dir ]] && dir=$download_dir
    [[ -z $dir && -n ${VDL_SAVE_DIR:-} ]] && dir=$VDL_SAVE_DIR

    if [[ -n $dir ]]; then
        case $dir in
            /*|~*|.*)
                # Absolute, home-relative, or current-directory-relative.
                save_dir=$dir
                ;;
            *)
                save_dir=$default_dir/$dir
                ;;
        esac
    else
        save_dir=$default_dir
    fi
    # A leading ~ is the home directory (also when quoted).
    save_dir=${save_dir/#~\//$HOME/}
    # A trailing slash would make joined paths show "dir//file".
    [[ $save_dir != / ]] && save_dir=${save_dir%/}
    # Temporary files go under a vdl-specific cache directory, keyed by a
    # run ID so concurrent invocations do not collide.  This avoids placing
    # a .tmp directory inside the user's save directory, where cleanup could
    # delete unrelated files.
    cache_base=${XDG_CACHE_HOME:-$HOME/.cache}/vdl
    run_id="$(date +%s)-$$-${RANDOM:-0}"
    tmp_dir=$cache_base/runs/$run_id
    partials_base=$cache_base/partials
    run_manifest=$tmp_dir/manifest.txt
    aria_hook=$tmp_dir/aria-complete.sh
    tmp_keep_days=${VDL_TMP_KEEP_DAYS:-7}
    [[ $tmp_keep_days =~ ^[0-9]+$ ]] || tmp_keep_days=7

    # A stable partial directory for one download, so an interrupted yt-dlp
    # transfer can resume on the next invocation.  The run directory remains
    # per-invocation for logs, manifests, and hooks.
    partial_dir_for() {
        local key
        key=$(printf '%s' "$*" | sha256sum 2>/dev/null | awk '{print $1}')
        if [[ -z $key ]]; then
            key=$(printf '%s' "$*" | cksum 2>/dev/null | tr ' ' '-')
        fi
        [[ -n $key ]] || key=vdl-partial
        printf '%s/%s\n' "$partials_base" "${key:0:24}"
    }

    ensure_tmp_dir() {
        (( dry_run )) && return 0
        mkdir -p "$tmp_dir" || return 1
        : > "$run_manifest"
        export VDL_MANIFEST=$run_manifest
        cat > "$aria_hook" <<'EOF'
#!/usr/bin/env bash
[[ -n ${VDL_MANIFEST:-} && -n ${3:-} ]] || exit 0
printf '%s\n' "$3" >> "$VDL_MANIFEST"
EOF
        chmod +x "$aria_hook"
    }

    cleanup_tmp() {
        local keep=$tmp_keep_days
        # Remove vdl's internal scratch files (logs, manifests, hooks).
        if [[ -d $tmp_dir ]]; then
            rm -f -- "$run_manifest" "$aria_hook" \
                "$tmp_dir"/aria.log.* "$tmp_dir"/media.log.* "$tmp_dir"/page.* \
                2>/dev/null || true
            if (( ${rc:-1} == 0 && ${direct_fail:-0} + ${media_fail:-0} + ${gallery_fail:-0} + ${img_fail:-0} == 0 )); then
                rm -rf -- "$tmp_dir"
            else
                rmdir "$tmp_dir" 2>/dev/null || true
            fi
        fi
        # Expire old run directories under vdl's own cache tree only.
        if [[ -d $cache_base/runs ]]; then
            find "$cache_base/runs" -mindepth 1 -maxdepth 1 -type d \
                -mtime +"$keep" -exec rm -rf -- {} + 2>/dev/null || true
            rmdir "$cache_base/runs" 2>/dev/null || true
        fi
        # Stable yt-dlp partials left by failed or interrupted runs follow the
        # same retention policy, but successful downloads remove their own.
        if [[ -d ${partials_base:-} ]]; then
            find "$partials_base" -mindepth 1 -maxdepth 1 -type d \
                -mtime +"$keep" -exec rm -rf -- {} + 2>/dev/null || true
            rmdir "$partials_base" 2>/dev/null || true
        fi
        if [[ -n ${archive_tmp:-} ]]; then
            rm -f -- "$archive_tmp" 2>/dev/null || true
        fi
    }

    # Ctrl+C: finished items have already been moved to their final folders;
    # only the download in flight stays in the temp dir.  Tell the user how
    # to pick up where they left off instead of dying silently.
    # shellcheck disable=SC2317,SC2329  # signal handler, invoked via trap
    on_interrupt() {
        trap - INT
        rc=130
        printf '\n'
        warn "Interrupted — completed downloads were moved to their folders; run the same command again to resume the rest."
        exit 130
    }
    if (( ! dry_run )); then
        trap cleanup_tmp EXIT
        trap on_interrupt INT
    fi

    if (( audio )); then
        out_dir=$save_dir/audio
    else
        out_dir=$save_dir
    fi

    have_aria=0
    have aria2c && have_aria=1

    # --output: exact destination for a single URL.  A path whose last
    # component has an extension is the exact file; otherwise it is the
    # exact folder.  The save directory is repointed here, before
    # classification and the image scanner, so every engine uses it.
    custom_direct=''
    custom_media=''
    out_folder_strip=0
    if [[ -n $output_arg ]]; then
        local out_last ext_present
        out_last=${output_arg%/}
        out_last=${out_last##*/}
        ext_present=0
        case $out_last in
            *.*) [[ ${out_last##*.} =~ ^[a-zA-Z0-9]{1,8}$ ]] && ext_present=1 ;;
        esac
        if (( ext_present )); then
            save_dir=$(dirname "$output_arg")
            custom_direct=$out_last
            custom_media=$out_last
        else
            save_dir=$output_arg
            out_folder_strip=1
        fi
        [[ $save_dir != / ]] && save_dir=${save_dir%/}
        out_dir=$save_dir
    fi
}
