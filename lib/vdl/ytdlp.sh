#!/usr/bin/env bash
# shellcheck shell=bash
# shellcheck disable=SC2034,SC2154,SC2329  # globals live in bin/vdl or the libs
#
# vdl yt-dlp defaults (self-contained; ignores ~/.config/yt-dlp/config),
# the stricter-of-two speed limit, and browser impersonation setup.

build_yt_common() {
    extra_conf=${VDL_CONFIG:-${XDG_CONFIG_HOME:-$HOME/.config}/vdl/yt-dlp.conf}

    yt_common=( --ignore-config )
    if [[ -f $extra_conf ]]; then
        yt_common+=( --config-locations "$extra_conf" )
    fi
    yt_common+=(
        --socket-timeout 15
        --retries 10
        --fragment-retries 10
        --continue
    )
    if [[ ${on_collision:-skip} == overwrite ]]; then
        yt_common+=( --force-overwrites )
    else
        yt_common+=( --no-overwrites )
    fi
    (( quiet )) && yt_common+=( --quiet )
    (( ! quiet )) && yt_common+=(
        --progress --console-title
        --progress-template 'download:%(progress._percent_str)s | %(progress._downloaded_bytes_str)s/%(progress._total_bytes_str)s | %(progress._speed_str)s | ETA %(progress._eta_str)s'
    )

    # yt-dlp exposes one per-download rate limit, so when both limits are set
    # use the stricter one.  A zero rate means "unlimited" and is ignored
    # here.
    yt_speed=''
    if [[ -n $max_speed_bytes && $max_speed_bytes != 0 ]]; then
        yt_speed=$max_speed_bytes
    fi
    if [[ -n $limit_speed_bytes && $limit_speed_bytes != 0 ]]; then
        if [[ -z $yt_speed || $limit_speed_bytes -lt $yt_speed ]]; then
            yt_speed=$limit_speed_bytes
        fi
    fi
    [[ -n $yt_speed ]] && yt_common+=( --limit-rate "$yt_speed" )

    impersonate=''
    if (( ! no_impersonate )) && (( need_ytdlp )); then
        local imp_target imp_list
        imp_target=${VDL_IMPERSONATE:-auto}
        if [[ $imp_target != off && $imp_target != none ]]; then
            imp_list=''
            if have yt-dlp; then
                imp_list=$(yt-dlp --ignore-config --list-impersonate-targets 2>/dev/null) || imp_list=''
            fi
            if [[ $imp_target == auto ]]; then
                for candidate in chrome firefox safari; do
                    if impersonate=$(imp_resolve_target "$imp_list" "$candidate"); then
                        break
                    fi
                done
            elif impersonate=$(imp_resolve_target "$imp_list" "$imp_target"); then
                :
            else
                warn "yt-dlp cannot impersonate '$imp_target'; --impersonate ignored"
            fi
        fi
    fi
}
