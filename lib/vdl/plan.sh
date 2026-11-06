#!/usr/bin/env bash
# shellcheck shell=bash
# shellcheck disable=SC2034,SC2154,SC2329  # globals live in bin/vdl or the libs
#
# vdl plan strings and the pre-download plan output (banner, directories,
# --dry-run).

build_header() {
    if (( ${#direct[@]} )) && (( ${#media[@]} )); then
        engine="Hybrid (aria2c + yt-dlp)"
    elif (( ${#direct[@]} )); then
        if (( direct_via_ytdlp )); then
            engine="Direct (yt-dlp, native)"
        else
            engine="Direct (aria2c, 16 connections)"
        fi
    elif (( ${#media[@]} )); then
        if (( have_aria && ! no_aria )); then
            engine="Media (yt-dlp + aria2c)"
        else
            engine="Media (yt-dlp, native)"
        fi
    elif (( ${#img_urls[@]} )); then
        if (( have_aria && ! no_aria )); then
            engine="Images (aria2c)"
        else
            engine="Images (yt-dlp)"
        fi
    else
        engine="Idle"
    fi

    if (( audio )); then
        mode="Audio only (MP3 320k)"
    elif (( ${#direct[@]} )) && (( ${#media[@]} == 0 )); then
        mode="Direct file download"
    elif (( ${#media[@]} == 0 )) && (( ${#img_urls[@]} )); then
        mode="Embedded images"
    else
        mode="Video (max ${quality}p, MP4 preferred)"
    fi

    display_dir=$out_dir
    if [[ $display_dir == "$HOME"* ]]; then
        display_dir="~${display_dir#"$HOME"}"
    fi
}

print_plan() {
    print_banner

    mkdir -p "$save_dir" || exit 1
    if (( audio )); then
        mkdir -p "$out_dir" || exit 1
    fi

    # --dry-run: print the resolved plan and exit without downloading.
    if (( dry_run )); then
        printf '%sURLs:%s\n' "$C_GRN" "$C_OFF"
        for u in "${urls[@]}"; do
            printf '   %s\n' "$u"
        done
        printf '%sDirect:  %d  Media: %d\n' "" "${#direct[@]}" "${#media[@]}"
        printf '%sImpersonate: %s\n' "" "${impersonate:-none}"
        [[ -n $ua ]] && printf '%sUser-Agent: %s\n' "" "$ua"
        printf '\n%s(dry-run — nothing downloaded)%s\n' "$C_DIM" "$C_OFF"
        exit 0
    fi
}
