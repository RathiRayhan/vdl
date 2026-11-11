#!/usr/bin/env bash
# shellcheck shell=bash
# shellcheck disable=SC2034,SC2154,SC2329  # globals live in bin/vdl or the libs
#
# vdl settings resolution: config file, speed limits, browser, quality.
# Precedence is command line > environment > config file > defaults.

resolve_settings() {
    read_vdl_config

    # Structured output must be the only thing on stdout.
    (( ${json_output:-0} )) && quiet=1

    case ${on_collision:-skip} in
        skip|rename|fail|overwrite) ;;
        *)
            err "Invalid collision policy: $on_collision (try skip, rename, fail, overwrite)"
            exit 2
            ;;
    esac

    # --gallery wins over the environment/config default.
    if (( ! gallery_mode )) && [[ ${VDL_GALLERY:-} == 1 || ${VDL_GALLERY:-} == yes ]]; then
        gallery_mode=1
    fi

    # Convert speed limits once, before any downloader runs.  Keeping them as
    # plain byte values avoids aria2c's rejection of "1.5M"/"1G" and the
    # different semantics of the two backends' rate options.
    max_speed_bytes=''
    if [[ -n $max_speed ]]; then
        if ! max_speed_bytes=$(normalize_speed "$max_speed"); then
            err "Invalid speed: $max_speed (try 1M, 500K, 1.5M)"
            exit 2
        fi
    fi
    limit_speed_bytes=''
    if [[ -n $limit_speed ]]; then
        if ! limit_speed_bytes=$(normalize_speed "$limit_speed"); then
            err "Invalid speed: $limit_speed (try 1M, 500K, 1.5M)"
            exit 2
        fi
    fi

    if (( no_cookies )); then
        browser=none
    elif (( browser_set )); then
        browser=$browser_arg
    elif [[ -n ${VDL_BROWSER:-} ]]; then
        browser=$VDL_BROWSER
    else
        browser=$(detect_browser)
    fi

    if [[ $browser == *:* ]]; then
        bname=${browser%%:*}
        bprof=${browser#*:}
        browser="${bname,,}:$bprof"
    else
        browser=${browser,,}
    fi

    if [[ $browser != none ]]; then
        case ${browser%%:*} in
            vivaldi|firefox|brave|chromium|chrome|edge|opera|safari|whale) ;;
            *)
                err "Unknown browser: $browser"
                printf '    Supported: vivaldi firefox brave chromium chrome edge opera safari whale none\n' >&2
                exit 2
                ;;
        esac
    fi

    if (( quality_set )); then
        quality_raw=$quality_arg
    elif [[ -n ${VDL_QUALITY:-} ]]; then
        quality_raw=$VDL_QUALITY
    else
        quality_raw=1080
    fi
    if ! quality=$(normalize_quality "$quality_raw"); then
        err "Invalid quality: $quality_raw (try 720, 1080, 2k, 4k)"
        exit 2
    fi

    if (( zip_mode && zip_name_set )) && ! validate_zip_name "$zip_name"; then
        err "Invalid archive name: '$zip_name' (must be a plain filename without /, \\, .., or leading -)"
        exit 2
    fi
}
