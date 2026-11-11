#!/usr/bin/env bash
# shellcheck shell=bash
# shellcheck disable=SC2034,SC2154,SC2329  # globals live in bin/vdl or the libs
#
# `vdl --doctor`: inspect the environment without downloading anything.
# Required failures (Bash, yt-dlp, writable save directory) set exit status 1;
# optional tools and conveniences only produce warnings.

declare -a doctor_names=()
declare -a doctor_states=()
declare -a doctor_details=()

doctor_add() {
    doctor_names+=("$1")
    doctor_states+=("$2")
    doctor_details+=("$3")
}

doctor_tool_version() {
    local tool=$1 out
    case $tool in
        zip)          out=$(timeout 5 zip -v 2>/dev/null | head -1) ;;
        ffmpeg)       out=$(timeout 5 ffmpeg -version 2>/dev/null | head -1) ;;
        *)            out=$(timeout 5 "$tool" --version 2>/dev/null | head -1) ;;
    esac
    printf '%s\n' "$out"
}

doctor_save_dir_check() {
    local probe=$save_dir detail free_kb
    if [[ -e $probe && ! -d $probe ]]; then
        doctor_add 'save dir' fail "$probe exists but is not a directory"
        return
    fi
    if [[ ! -d $probe ]]; then
        probe=${probe%/}
        [[ -z $probe ]] && probe=/
        while [[ $probe != / && ! -d $probe ]]; do
            probe=${probe%/*}
            [[ -z $probe ]] && probe=/
        done
        if [[ -d $probe && -w $probe ]]; then
            doctor_add 'save dir' ok "will be created under $probe"
        else
            doctor_add 'save dir' fail "$save_dir is not writable"
            return
        fi
    elif [[ -w $probe ]]; then
        doctor_add 'save dir' ok "writable: $save_dir"
    else
        doctor_add 'save dir' fail "not writable: $save_dir"
        return
    fi
    if free_kb=$(df -Pk "$probe" 2>/dev/null | awk 'NR==2 {print $4}') \
        && [[ $free_kb =~ ^[0-9]+$ ]]; then
        doctor_add 'free space' ok "$((free_kb / 1024)) MiB available at $probe"
    else
        doctor_add 'free space' warn "could not determine free space at $probe"
    fi
}

doctor_config_check() {
    local conf_dir conf extra
    conf_dir=${VDL_CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/vdl}
    conf=$conf_dir/config
    if [[ -f $conf && -r $conf ]]; then
        doctor_add 'config' ok "$conf"
    elif [[ -e $conf ]]; then
        doctor_add 'config' warn "$conf exists but is not readable"
    else
        doctor_add 'config' ok "not present (optional): $conf"
    fi
    extra=${VDL_CONFIG:-${XDG_CONFIG_HOME:-$HOME/.config}/vdl/yt-dlp.conf}
    if [[ -f $extra && -r $extra ]]; then
        doctor_add 'yt-dlp config' ok "$extra"
    elif [[ -e $extra ]]; then
        doctor_add 'yt-dlp config' warn "$extra exists but is not readable"
    else
        doctor_add 'yt-dlp config' ok "not present (optional): $extra"
    fi
}

doctor_browser_check() {
    local name bin found
    if [[ ${browser:-none} == none ]]; then
        doctor_add 'cookies' ok "browser cookies disabled"
        return
    fi
    name=${browser%%:*}
    found=0
    while IFS= read -r bin; do
        if have "$bin"; then
            found=1
            break
        fi
    done < <(browser_binary "$name")
    if (( found )); then
        doctor_add 'cookies' ok "browser: ${browser} ($bin)"
    else
        doctor_add 'cookies' warn "browser '${browser}' selected, but its binary is not in PATH"
    fi
}

doctor_clipboard_check() {
    if [[ -n ${WAYLAND_DISPLAY:-} ]] && have wl-paste; then
        doctor_add 'clipboard' ok "wayland: wl-paste"
    elif [[ -n ${DISPLAY:-} ]] && have xclip; then
        doctor_add 'clipboard' ok "X11: xclip"
    elif [[ -n ${DISPLAY:-} ]] && have xsel; then
        doctor_add 'clipboard' ok "X11: xsel"
    else
        doctor_add 'clipboard' warn "no clipboard tool/session detected (optional)"
    fi
}

doctor_impersonation_check() {
    local list target
    if ! have yt-dlp; then
        doctor_add 'impersonation' warn "yt-dlp not available"
        return
    fi
    list=$(timeout 8 yt-dlp --ignore-config --list-impersonate-targets 2>/dev/null) || list=''
    if [[ -z $list ]]; then
        doctor_add 'impersonation' warn "yt-dlp did not report impersonation targets"
        return
    fi
    for target in chrome firefox safari; do
        if imp_resolve_target "$list" "$target" >/dev/null 2>&1; then
            doctor_add 'impersonation' ok "available: $(imp_resolve_target "$list" "$target")"
            return
        fi
    done
    doctor_add 'impersonation' warn "no usable curl_cffi target (install yt-dlp[default,curl-cffi])"
}

print_doctor_json() {
    local i sep='' ok=0 warn=0 fail=0 ok_json=false
    for i in "${!doctor_states[@]}"; do
        case ${doctor_states[$i]} in
            ok) ok=$((ok + 1)) ;;
            warn) warn=$((warn + 1)) ;;
            *) fail=$((fail + 1)) ;;
        esac
    done
    (( fail == 0 )) && ok_json=true
    printf '{"version":"%s","ok":%s,"checks":[' \
        "$(json_escape "$VDL_VERSION")" "$ok_json"
    for i in "${!doctor_names[@]}"; do
        printf '%s{"name":"%s","status":"%s","detail":"%s"}' "$sep" \
            "$(json_escape "${doctor_names[$i]}")" \
            "$(json_escape "${doctor_states[$i]}")" \
            "$(json_escape "${doctor_details[$i]}")"
        sep=','
    done
    printf '],"summary":{"ok":%d,"warn":%d,"fail":%d}}\n' "$ok" "$warn" "$fail"
}

run_doctor() {
    local tool version rc=0 i

    doctor_add 'bash' ok "$BASH_VERSION"
    if (( BASH_VERSINFO[0] < 4 )); then
        doctor_states[0]=fail
        doctor_details[0]="Bash 4+ is required"
    fi

    for tool in yt-dlp aria2c ffmpeg gallery-dl zip curl python3 sha256sum wl-paste xclip xsel; do
        if ! have "$tool"; then
            if [[ $tool == yt-dlp ]]; then
                doctor_add "$tool" fail "required, not found in PATH"
            else
                doctor_add "$tool" warn "not installed (optional)"
            fi
            continue
        fi
        version=$(doctor_tool_version "$tool")
        doctor_add "$tool" ok "${version:-installed}"
    done

    doctor_browser_check
    doctor_save_dir_check
    doctor_config_check
    doctor_clipboard_check
    doctor_impersonation_check

    if (( ${json_output:-0} )); then
        print_doctor_json
    else
        printf '\nvdl doctor %s\n\n' "$VDL_VERSION"
        for i in "${!doctor_names[@]}"; do
            case ${doctor_states[$i]} in
                ok)   printf '  [ok]   %-16s %s\n' "${doctor_names[$i]}" "${doctor_details[$i]}" ;;
                warn) printf '  [warn] %-16s %s\n' "${doctor_names[$i]}" "${doctor_details[$i]}" ;;
                *)    printf '  [FAIL] %-16s %s\n' "${doctor_names[$i]}" "${doctor_details[$i]}" ;;
            esac
        done
        printf '\n'
    fi

    for i in "${!doctor_states[@]}"; do
        [[ ${doctor_states[$i]} == fail ]] && rc=1
    done
    return "$rc"
}
