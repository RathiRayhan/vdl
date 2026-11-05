#!/usr/bin/env bash
# shellcheck shell=bash
# shellcheck disable=SC2034,SC2154,SC2329  # globals live in bin/vdl or the libs
#
# vdl settings resolution: config file, speed limits, browser, quality.
# Precedence is command line > environment > config file > defaults.

declare -a yt_cookie_args=()
cookie_label=''

# Rebuild the cookie arguments after the browser/cookies file is resolved.
# Called again after a root Firefox import stages a profile.
build_cookie_args() {
    yt_cookie_args=()
    [[ $browser != none ]] && yt_cookie_args+=( --cookies-from-browser "$browser" )
    [[ -n $cookies_file ]] && yt_cookie_args+=( --cookies "$cookies_file" )

    cookie_label=''
    if (( root_cookies )); then
        cookie_label='firefox (root)'
    elif [[ $browser != none ]]; then
        cookie_label=$browser
    fi
    if [[ -n $cookies_file ]]; then
        if [[ -n $cookie_label ]]; then
            cookie_label+=" + $(basename -- "$cookies_file")"
        else
            cookie_label="file: $(basename -- "$cookies_file")"
        fi
    fi
}

resolve_settings() {
    read_vdl_config

    # Manual cookies file and root-only Firefox import.  Command-line flags
    # have already been captured, so only fill in environment/config values.
    [[ -z $cookies_file && -n ${VDL_COOKIES:-} ]] && cookies_file=$VDL_COOKIES
    if (( ! root_cookies )); then
        case ${VDL_ROOT_COOKIES:-} in
            1|yes|firefox) root_cookies=1 ;;
        esac
    fi

    if (( no_cookies )); then
        [[ -n $cookies_file ]] && warn "--no-cookies ignores the cookies file"
        (( root_cookies )) && warn "--no-cookies ignores --root-cookies"
        cookies_file=''
        root_cookies=0
    fi

    cookies_file=${cookies_file/#\~/$HOME}

    if [[ -n $cookies_file && ! -f $cookies_file ]]; then
        err "Cookies file not found: $cookies_file"
        exit 2
    fi

    if (( root_cookies )); then
        if ! is_termux; then
            err "--root-cookies is only supported inside Termux"
            exit 2
        fi
        if (( browser_set )); then
            case ${browser_arg,,} in
                firefox|firefox:*) ;;
                *)
                    err "--root-cookies only supports Firefox; use --cookies for other browsers"
                    exit 2
                    ;;
            esac
        fi
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
    elif (( root_cookies )); then
        # Staged later, once URLs have been collected and root is available.
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
        if is_termux && [[ $browser != *:* ]] && (( ! root_cookies )); then
            warn "Termux cannot read Android browser profiles; use --cookies FILE or --root-cookies"
        fi
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

    build_cookie_args
}
