#!/usr/bin/env bash
# shellcheck shell=bash
# shellcheck disable=SC2034,SC2154,SC2329  # globals live in bin/vdl or the libs
#
# vdl command-line parsing.  The recognized flags set globals; unknown
# options are kept in raw_args/raw_kind so their values stay attached in
# the original order.

browser_arg=''
browser_set=0
no_cookies=0
quality_arg=''
quality_set=0
audio=0
no_aria=0
no_impersonate=0
referer=''
ua=''
proxy=''
download_dir=''
quiet=0
dry_run=0
dedupe=0
images=0
aria_opts=''
max_speed=''
limit_speed=''
custom_name=''
output_arg=''

declare -a batch_files=()
declare -a raw_args=()
declare -a raw_kind=()
declare -a passthru=()
prev_unknown_flag=0

parse_args() {
    local arg
    while (( $# > 0 )); do
        arg=$1
        shift
        case $arg in
            -h|--help)
                usage
                exit 0
                ;;
            -V|--version)
                printf 'vdl %s\n' "$VDL_VERSION"
                exit 0
                ;;
            -n|--no-cookies)
                no_cookies=1
                prev_unknown_flag=0
                ;;
            -a|--audio)
                audio=1
                prev_unknown_flag=0
                ;;
            --no-aria)
                no_aria=1
                prev_unknown_flag=0
                ;;
            --no-impersonate)
                no_impersonate=1
                prev_unknown_flag=0
                ;;
            -b|--browser)
                (( $# > 0 )) || need_value "$arg"
                browser_arg=$1
                shift
                browser_set=1
                prev_unknown_flag=0
                ;;
            --browser=*)
                browser_arg=${arg#*=}
                browser_set=1
                prev_unknown_flag=0
                ;;
            -b?*)
                browser_arg=${arg#-b}
                browser_set=1
                prev_unknown_flag=0
                ;;
            -q|--quality)
                (( $# > 0 )) || need_value "$arg"
                quality_arg=$1
                shift
                quality_set=1
                prev_unknown_flag=0
                ;;
            --quality=*)
                quality_arg=${arg#*=}
                quality_set=1
                prev_unknown_flag=0
                ;;
            -q?*)
                quality_arg=${arg#-q}
                quality_set=1
                prev_unknown_flag=0
                ;;
            -i|--batch-file)
                (( $# > 0 )) || need_value "$arg"
                batch_files+=("$1")
                shift
                prev_unknown_flag=0
                ;;
            --batch-file=*)
                batch_files+=("${arg#*=}")
                prev_unknown_flag=0
                ;;
            -i?*)
                batch_files+=("${arg#-i}")
                prev_unknown_flag=0
                ;;
            --referer)
                (( $# > 0 )) || need_value "$arg"
                referer=$1
                shift
                prev_unknown_flag=0
                ;;
            --referer=*)
                referer=${arg#*=}
                prev_unknown_flag=0
                ;;
            --user-agent)
                (( $# > 0 )) || need_value "$arg"
                ua=$1
                shift
                prev_unknown_flag=0
                ;;
            --user-agent=*)
                ua=${arg#*=}
                prev_unknown_flag=0
                ;;
            --proxy)
                (( $# > 0 )) || need_value "$arg"
                proxy=$1
                shift
                prev_unknown_flag=0
                ;;
            --proxy=*)
                proxy=${arg#*=}
                prev_unknown_flag=0
                ;;
            --download-dir)
                (( $# > 0 )) || need_value "$arg"
                download_dir=$1
                shift
                prev_unknown_flag=0
                ;;
            --download-dir=*)
                download_dir=${arg#*=}
                prev_unknown_flag=0
                ;;
            --dry-run)
                dry_run=1
                prev_unknown_flag=0
                ;;
            --dedupe)
                dedupe=1
                prev_unknown_flag=0
                ;;
            --images)
                images=1
                prev_unknown_flag=0
                ;;
            --quiet)
                quiet=1
                prev_unknown_flag=0
                ;;
            --aria-opts)
                (( $# > 0 )) || need_value "$arg"
                aria_opts=$1
                shift
                prev_unknown_flag=0
                ;;
            --aria-opts=*)
                aria_opts=${arg#*=}
                prev_unknown_flag=0
                ;;
            --max-speed)
                (( $# > 0 )) || need_value "$arg"
                max_speed=$1
                shift
                prev_unknown_flag=0
                ;;
            --max-speed=*)
                max_speed=${arg#*=}
                prev_unknown_flag=0
                ;;
            --limit-speed)
                (( $# > 0 )) || need_value "$arg"
                limit_speed=$1
                shift
                prev_unknown_flag=0
                ;;
            --limit-speed=*)
                limit_speed=${arg#*=}
                prev_unknown_flag=0
                ;;
            --name)
                (( $# > 0 )) || need_value "$arg"
                custom_name=$1
                shift
                prev_unknown_flag=0
                ;;
            --name=*)
                custom_name=${arg#*=}
                prev_unknown_flag=0
                ;;
            --output)
                (( $# > 0 )) || need_value "$arg"
                output_arg=$1
                shift
                prev_unknown_flag=0
                ;;
            --output=*)
                output_arg=${arg#*=}
                prev_unknown_flag=0
                ;;
            --)
                while (( $# > 0 )); do
                    raw_args+=("$1")
                    raw_kind+=("pos")
                    shift
                done
                prev_unknown_flag=0
                ;;
            -*)
                raw_args+=("$arg")
                raw_kind+=("pass")
                prev_unknown_flag=1
                ;;
            *)
                raw_args+=("$arg")
                if (( prev_unknown_flag )); then
                    raw_kind+=("pos-after-flag")
                else
                    raw_kind+=("pos")
                fi
                prev_unknown_flag=0
                ;;
        esac
    done
}
