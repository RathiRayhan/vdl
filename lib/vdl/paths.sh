#!/usr/bin/env bash
# shellcheck shell=bash
# shellcheck disable=SC2034,SC2154,SC2329,SC2317  # globals live in bin/vdl or the libs; trap handlers
#
# vdl paths and dependencies: save directory, temp dir with its cleanup
# traps, Ctrl+C handler, and the --output repointing.

setup_paths() {
    if [[ -n $download_dir ]]; then
        save_dir=$download_dir
    elif [[ -n ${VDL_SAVE_DIR:-} ]]; then
        save_dir=$VDL_SAVE_DIR
    else
        download_base=''
        if have xdg-user-dir; then
            download_base=$(xdg-user-dir DOWNLOAD 2>/dev/null) || download_base=''
        fi
        if [[ -z $download_base || $download_base == "$HOME" ]]; then
            download_base=$HOME/Downloads
        fi
        save_dir=$download_base/vdl
    fi
    tmp_dir=$save_dir/.tmp
    tmp_keep_days=${VDL_TMP_KEEP_DAYS:-7}
    [[ $tmp_keep_days =~ ^[0-9]+$ ]] || tmp_keep_days=7
    cleanup_tmp() {
        [[ -d $tmp_dir ]] || return 0
        find "$tmp_dir" -mindepth 1 -type f -mtime +"$tmp_keep_days" -delete 2>/dev/null || true
        find "$tmp_dir" -mindepth 1 -type d -empty -mtime +0 -delete 2>/dev/null || true
        rmdir "$tmp_dir" 2>/dev/null || true
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
        tmp_dir=$save_dir/.tmp
        out_dir=$save_dir
    fi
}
