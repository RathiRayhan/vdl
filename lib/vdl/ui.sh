#!/usr/bin/env bash
# shellcheck shell=bash
# shellcheck disable=SC2154  # globals (quiet, C_*, ...) live in bin/vdl
#
# vdl UI layer: colors, message helpers, status output, the progress-bar
# renderer, and the banner/summary printers.  Sourced by bin/vdl.

if [[ -t 1 && -z ${NO_COLOR:-} && ${TERM:-dumb} != dumb ]]; then
    C_RED=$'\033[1;31m'
    C_GRN=$'\033[1;32m'
    C_YEL=$'\033[1;33m'
    C_CYN=$'\033[1;36m'
    C_DIM=$'\033[2m'
    C_OFF=$'\033[0m'
else
    C_RED='' C_GRN='' C_YEL='' C_CYN='' C_DIM='' C_OFF=''
fi

warn() { printf '%s[!] %s%s\n' "$C_YEL" "$*" "$C_OFF" >&2; }
err()  { printf '%s[!] %s%s\n' "$C_RED" "$*" "$C_OFF" >&2; }
note() { printf '%s[::] %s%s\n' "$C_DIM" "$*" "$C_OFF" >&2; }
have() { command -v "$1" >/dev/null 2>&1; }

# All helpers below print to stdout and are silenced by --quiet.

# Section header, e.g. "--- Direct downloads via aria2c ---"
ui_section() {
    (( quiet )) && return 0
    printf '\n%s--- %s ---%s\n' "$C_CYN" "$*" "$C_OFF"
}

# Aligned label/value row inside the banner and summary.
ui_row() {
    (( quiet )) && return 0
    printf '  %s%-9s%s %s\n' "$C_GRN" "$1:" "$C_OFF" "$2"
}

# A URL/about-to-start line, e.g. "  • file.iso"
ui_item() {
    (( quiet )) && return 0
    printf '  %s•%s %s\n' "$C_DIM" "$C_OFF" "$1"
}

# A per-URL or per-phase result, e.g. "  [ok] file.iso"
ui_result() {
    local code=$1 label=$2
    (( quiet )) && return 0
    if (( code == 0 )); then
        printf '  %s[ok]%s   %s\n' "$C_GRN" "$C_OFF" "$label"
    else
        printf '  %s[fail]%s %s\n' "$C_RED" "$C_OFF" "$label"
    fi
}

# Human-friendly display name for a URL (basename when possible).
ui_name() {
    local name
    case $1 in
        magnet:*) printf '%s\n' "$1" ;;
        *)
            if name=$(url_filename "$1"); then
                printf '%s\n' "$name"
            else
                printf '%s\n' "$1"
            fi
            ;;
    esac
}

# Render yt-dlp's \r-separated progress stream as a fixed-width bar plus the
# speed/ETA text, all on one updating line.  Non-progress output passes
# through untouched, with the leading [tag]/WARNING:/ERROR: prefix colored to
# match vdl's palette (yt-dlp skips its own colors when piped).
yt_bar() {
    awk -v grn="$C_GRN" -v yel="$C_YEL" -v red="$C_RED" -v off="$C_OFF" '
        BEGIN { RS = "\r"; ORS = ""; w = 20; newline = 1; pending = 0 }

        function colorize(seg) {
            if (seg ~ /^\[[A-Za-z0-9_.-]+\]/) {
                match(seg, /^\[[A-Za-z0-9_.-]+\]/)
                return grn substr(seg, 1, RLENGTH) off substr(seg, RLENGTH + 1)
            }
            if (seg ~ /^WARNING:/) {
                sub(/^WARNING:/, "", seg)
                return yel "WARNING:" off seg
            }
            if (seg ~ /^ERROR:/) {
                sub(/^ERROR:/, "", seg)
                return red "ERROR:" off seg
            }
            return seg
        }

        /^ *[0-9][0-9.]*% \|/ {
            p = $0
            sub(/^ */, "", p)
            sub(/% .*/, "", p)
            filled = int(p * w / 100 + 0.5)
            if (filled < 0) filled = 0
            if (filled > w) filled = w
            hashes = dashes = ""
            for (i = 1; i <= filled; i++) hashes = hashes "#"
            for (i = filled + 1; i <= w; i++) dashes = dashes "-"
            rest = $0
            sub(/^ *[0-9][0-9.]*% \| /, "", rest)
            sub(/^\.\//, "  ", rest)
            n = split(rest, pl, "\n")
            printf "\r%s[%s%s]%s %5s%% %s", grn, hashes, dashes, off, p, pl[1]
            for (i = 2; i <= n; i++) printf "\n%s", colorize(pl[i])
            newline = ($0 ~ /\n$/)
            pending = !newline
            next
        }
        {
            if (pending && $0 !~ /^\n/) printf "\n"
            n = split($0, parts, "\n")
            out = ""
            for (i = 1; i <= n; i++) {
                out = out colorize(parts[i])
                if (i < n) out = out "\n"
            }
            printf "%s", out
            newline = ($0 ~ /\n$/)
            pending = !newline
        }
        END { if (pending) printf "\n" }
    '
}

# The startup banner with engine, mode, URL counts and save directory.
print_banner() {
    (( quiet )) && return 0
    printf '\n%s===============================================%s\n' "$C_CYN" "$C_OFF"
    printf '  %svdl %s%s  —  smart downloader\n' "$C_CYN" "$VDL_VERSION" "$C_OFF"
    printf '%s-----------------------------------------------%s\n' "$C_DIM" "$C_OFF"
    ui_row 'Engine' "$engine"
    ui_row 'Mode' "$mode"
    ui_row 'URLs' "${#urls[@]} (${#direct[@]} direct, ${#media[@]} media)"
    if (( ${#batch_files[@]} )); then
        ui_row 'Batch' "${#batch_files[@]} file(s)"
    fi
    if (( ${#media[@]} )) && [[ $browser != none ]]; then
        ui_row 'Cookies' "$browser"
    fi
    ui_row 'Save dir' "$display_dir"
    printf '%s===============================================%s\n\n' "$C_CYN" "$C_OFF"
}

# The end-of-run summary with per-engine results, elapsed time and verdict.
print_summary() {
    ui_section "Summary"
    ui_row 'Total' "${#urls[@]}"
    if (( ${#direct[@]} )); then
        ui_row 'Direct' "$direct_ok ok, $direct_fail failed"
    fi
    if (( ${#media[@]} )); then
        ui_row 'Media' "$media_ok ok, $media_fail failed"
    fi
    if (( ${#img_urls[@]} )); then
        ui_row 'Images' "$img_ok ok, $img_fail failed"
    fi
    if (( SECONDS >= 60 )); then
        ui_row 'Time' "$((SECONDS / 60))m $((SECONDS % 60))s"
    else
        ui_row 'Time' "${SECONDS}s"
    fi
    ui_row 'Save dir' "$display_dir"
    if (( rc == 0 && direct_fail == 0 && media_fail == 0 && img_fail == 0 )); then
        ui_result 0 "all downloads finished"
    else
        ui_result 1 "some downloads failed"
    fi
}
