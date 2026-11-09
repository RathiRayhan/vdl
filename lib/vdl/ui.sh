#!/usr/bin/env bash
# shellcheck shell=bash
# shellcheck disable=SC2154,SC2329  # globals live in bin/vdl; functions invoked from there
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

# Aligned label/value row: fixed-width label column, colon at a fixed
# position on every line.
ui_row() {
    (( quiet )) && return 0
    printf '  %s%-11s%s: %s\n' "$C_GRN" "$1" "$C_OFF" "$2"
}

# A URL/about-to-start line, e.g. "  • file.iso"
ui_item() {
    (( quiet )) && return 0
    printf '  %s•%s %s\n' "$C_DIM" "$C_OFF" "$1"
}

# A per-URL or per-phase result, e.g. "  ✓ file.iso"
ui_result() {
    local code=$1 label=$2
    (( quiet )) && return 0
    if (( code == 0 )); then
        printf '  %s✓%s  %s\n' "$C_GRN" "$C_OFF" "$label"
    else
        printf '  %s✗%s  %s\n' "$C_RED" "$C_OFF" "$label"
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

# A run-level progress line, printed after each download phase:
# "  Run  2/3 · 1 failed"
ui_run_progress() {
    (( quiet )) && return 0
    local done=$(( direct_ok + direct_fail + media_ok + media_fail + gallery_ok + gallery_fail + img_ok + img_fail ))
    local total=$(( ${#direct[@]} + ${#media[@]} + ${#gallery[@]} + ${#img_urls[@]} ))
    local failed=$(( direct_fail + media_fail + gallery_fail + img_fail ))
    (( total && done )) || return 0
    if (( failed )); then
        printf '  %sRun%s  %d/%d · %s%d failed%s\n' "$C_DIM" "$C_OFF" "$done" "$total" "$C_RED" "$failed" "$C_OFF"
    else
        printf '  %sRun%s  %d/%d\n' "$C_DIM" "$C_OFF" "$done" "$total"
    fi
}

# Render yt-dlp's \r-separated progress stream as a bar whose width adapts
# to the terminal, plus the speed/ETA text, all on one updating line.
# Non-progress output passes through untouched, with the leading
# [tag]/WARNING:/ERROR: prefix colored to match vdl's palette (yt-dlp skips
# its own colors when piped).
yt_bar() {
    local w=${COLUMNS:-80}
    (( w -= 45 ))
    (( w < 10 )) && w=10
    (( w > 40 )) && w=40
    awk -v grn="$C_GRN" -v yel="$C_YEL" -v red="$C_RED" -v off="$C_OFF" -v w="$w" '
        BEGIN { RS = "\r"; ORS = ""; newline = 1; pending = 0 }

        function colorize(seg) {
            if (seg ~ /^\[[A-Za-z0-9_.-]+\]/) {
                match(seg, /^\[[A-Za-z0-9_.-]+\]/)
                tag = substr(seg, 1, RLENGTH)
                cap = "[" toupper(substr(tag, 2, 1)) substr(tag, 3)
                return grn cap off substr(seg, RLENGTH + 1)
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

# Render gallery-dl's machine-readable progress stream (configured in
# build_gallery_common) as the same style of bar used for yt-dlp.  gallery-dl
# writes file events to stdout and progress to stderr; both are merged into
# this filter.  Records are \r-separated so live updates can overwrite the
# bar in place, and start/success/skip events are tagged with @@VDL_* markers.
gallery_bar() {
    local w=${COLUMNS:-80}
    (( w -= 34 ))
    (( w < 10 )) && w=10
    (( w > 40 )) && w=40

    awk -v grn="$C_GRN" -v dim="$C_DIM" -v off="$C_OFF" -v w="$w" '
        BEGIN { RS = "\r"; ORS = ""; bar = 0 }

        /^@@VDL_START / {
            sub(/^@@VDL_START /, "")
            sub(/\n$/, "")
            printf "\r  %s•%s %s\n", dim, off, $0
            bar = 0
            next
        }
        /^@@VDL_SUCCESS / {
            sub(/^@@VDL_SUCCESS /, "")
            sub(/\n$/, "")
            printf "\r  %s✓%s  %s\n", grn, off, $0
            bar = 0
            next
        }
        /^@@VDL_SKIP / {
            sub(/^@@VDL_SKIP /, "")
            sub(/\n$/, "")
            printf "\r  %s#%s  %s\n", dim, off, $0
            bar = 0
            next
        }
        /^@@VDL_PROGRESS / {
            sub(/^@@VDL_PROGRESS /, "")
            split($0, f, " ")
            pct = f[1] + 0
            if (pct < 0) pct = 0
            if (pct > 100) pct = 100
            filled = int(pct * w / 100 + 0.5)
            hashes = dashes = ""
            for (i = 1; i <= filled; i++) hashes = hashes "#"
            for (i = filled + 1; i <= w; i++) dashes = dashes "-"
            printf "\r%s[%s%s]%s %3d%% %s/%s %s/s", grn, hashes, dashes, off, pct, f[2], f[3], f[4]
            bar = 1
            next
        }
        /^@@VDL_PROGRESS_BYTES / {
            sub(/^@@VDL_PROGRESS_BYTES /, "")
            split($0, f, " ")
            dashes = ""
            for (i = 1; i <= w; i++) dashes = dashes "-"
            printf "\r%s[%s]%s %s %s/s", dim, dashes, off, f[1], f[2]
            bar = 1
            next
        }
        {
            if (bar) printf "\r"
            printf "%s", $0
            bar = 0
        }
        END { if (bar) printf "\n" }
    '
}

# The startup banner with engine, mode, URL counts and save directory.
print_banner() {
    (( quiet )) && return 0
    printf '\n%s===============================================%s\n' "$C_CYN" "$C_OFF"
    printf '  %svdl %s%s  —  Versatile Downloader for Linux\n' "$C_CYN" "$VDL_VERSION" "$C_OFF"
    printf '%s-----------------------------------------------%s\n' "$C_DIM" "$C_OFF"
    ui_row 'Engine' "$engine"
    ui_row 'Mode' "$mode"
    local counts="${#direct[@]} direct, ${#media[@]} media"
    (( ${#gallery[@]} )) && counts+=", ${#gallery[@]} gallery"
    (( ${#img_urls[@]} )) && counts+=", ${#img_urls[@]} images"
    ui_row 'URLs' "${#urls[@]} ($counts)"
    [[ -n ${custom_name:-} ]] && ui_row 'Name' "$custom_name"
    [[ -n ${output_arg:-} ]] && ui_row 'Output' "$output_arg"
    if (( ${#batch_files[@]} )); then
        ui_row 'Batch' "${#batch_files[@]} file(s)"
    fi
    if (( ${#media[@]} + ${#gallery[@]} )) && [[ $browser != none ]]; then
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
        ui_row 'Direct' "$direct_ok OK, $direct_fail Failed"
    fi
    if (( ${#media[@]} )); then
        ui_row 'Media' "$media_ok OK, $media_fail Failed"
    fi
    if (( ${#gallery[@]} || gallery_ok || gallery_fail )); then
        ui_row 'Gallery' "$gallery_ok OK, $gallery_fail Failed"
    fi
    if (( ${#img_urls[@]} )); then
        ui_row 'Images' "$img_ok OK, $img_fail Failed"
    fi
    [[ -n ${zip_created:-} ]] && ui_row 'Archive' "$zip_created"
    if (( SECONDS >= 60 )); then
        ui_row 'Time' "$((SECONDS / 60))m $((SECONDS % 60))s"
    else
        ui_row 'Time' "${SECONDS}s"
    fi
    ui_row 'Save dir' "$display_dir"
    if (( ${#failed_items[@]} )); then
        (( quiet )) || printf '\n  %sFailed%s\n' "$C_RED" "$C_OFF"
        local item u r
        for item in "${failed_items[@]}"; do
            u=${item%%|*}
            r=${item#*|}
            ui_result 1 "$u — $r"
        done
    fi
    (( quiet )) || printf '\n'
    if (( rc == 0 && direct_fail == 0 && media_fail == 0 && gallery_fail == 0 && img_fail == 0 )); then
        ui_result 0 "All downloads finished"
    else
        ui_result 1 "Some downloads failed"
    fi
    (( quiet )) || printf '\n'
}
