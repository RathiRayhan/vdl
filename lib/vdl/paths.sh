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
    tmp_dir=$save_dir/.tmp
    tmp_keep_days=${VDL_TMP_KEEP_DAYS:-7}
    [[ $tmp_keep_days =~ ^[0-9]+$ ]] || tmp_keep_days=7
    cleanup_tmp() {
        local keep=$tmp_keep_days
        if [[ -d $tmp_dir ]]; then
            find "$tmp_dir" -mindepth 1 -type f -mtime +"$keep" -delete 2>/dev/null || true
            find "$tmp_dir" -mindepth 1 -type d -empty -mtime +0 -delete 2>/dev/null || true
            rmdir "$tmp_dir" 2>/dev/null || true
        fi

        # aria2c leftovers: a control file and its partial, both older than
        # the keep window, are a stale interrupted download.  In-progress
        # downloads are safe because aria2c refreshes the control file's
        # mtime while running.
        local ctrl
        while IFS= read -r -d '' ctrl; do
            local part=${ctrl%.aria2}
            if [[ ! -e $part ]] || find "$part" -type f -mtime +"$keep" -print -quit 2>/dev/null | grep -q .; then
                rm -f -- "$ctrl" "$part"
            fi
        done < <(find "$save_dir" -type f -name '*.aria2' -mtime +"$keep" \
            ! -path "$tmp_dir" ! -path "$tmp_dir/*" -print0 2>/dev/null)
    }
    trap cleanup_tmp EXIT

    # Ctrl+C: finished items have already been moved to their final folders;
    # only the download in flight stays in the temp dir.  Tell the user how
    # to pick up where they left off instead of dying silently.
    # shellcheck disable=SC2317,SC2329  # signal handler, invoked via trap
    on_interrupt() {
        trap - INT
        printf '\n'
        warn "Interrupted — completed downloads were moved to their folders; run the same command again to resume the rest."
        exit 130
    }
    trap on_interrupt INT

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
        tmp_dir=$save_dir/.tmp
        out_dir=$save_dir
    fi
}
