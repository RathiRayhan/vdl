#!/usr/bin/env bash
# shellcheck shell=bash
# shellcheck disable=SC2034,SC2154,SC2329  # globals live in bin/vdl or the libs
#
# Structured run reporting for --json and --json-lines.  Human output stays
# on the normal UI path; this module records per-URL outcomes and renders them
# as JSON without requiring jq or Python.

declare -a report_urls=()
declare -a report_engines=()
declare -a report_statuses=()
declare -a report_files=()
declare -a report_errors=()
declare -a NEW_FILES=()

# Escape a string for a JSON string literal.  Backslashes and quotes are
# escaped first, then the remaining C0 control characters become \u00XX.
json_escape() {
    local s=$1 out='' ch hex i
    s=${s//\\/\\\\}
    s=${s//\"/\\\"}
    s=${s//$'\n'/\\n}
    s=${s//$'\r'/\\r}
    s=${s//$'\t'/\\t}
    s=${s//$'\b'/\\b}
    s=${s//$'\f'/\\f}
    for ((i = 0; i < ${#s}; i++)); do
        ch=${s:i:1}
        if [[ $ch == [[:cntrl:]] ]]; then
            printf -v hex '\\u%04x' "'$ch"
            out+=$hex
        else
            out+=$ch
        fi
    done
    printf '%s' "$out"
}

json_files_array() {
    local files=$1 f first=1
    while IFS= read -r f; do
        [[ -n $f ]] || continue
        [[ -f $f ]] || continue
        (( first )) || printf ','
        printf '"%s"' "$(json_escape "$f")"
        first=0
    done <<< "$files"
}

json_string_or_null() {
    if [[ -n ${1:-} ]]; then
        printf '"%s"' "$(json_escape "$1")"
    else
        printf 'null'
    fi
}

# Record one completed URL.  FILES is a newline-separated list of paths.
report_item() {
    report_urls+=("$1")
    report_engines+=("$2")
    report_statuses+=("$3")
    report_files+=("$4")
    report_errors+=("$5")
}

print_item_json() {
    local i=$1 type=${2:-item}
    printf '{"type":"%s","url":"%s","engine":"%s","status":"%s","files":[' \
        "$type" \
        "$(json_escape "${report_urls[$i]}")" \
        "$(json_escape "${report_engines[$i]}")" \
        "$(json_escape "${report_statuses[$i]}")"
    json_files_array "${report_files[$i]}"
    printf '],"error":%s}' "$(json_string_or_null "${report_errors[$i]}")"
}

json_counts() {
    printf '"total":%d,"direct_ok":%d,"direct_fail":%d,"direct_skipped":%d' \
        "${#urls[@]}" "${direct_ok:-0}" "${direct_fail:-0}" "${direct_skip:-0}"
    printf ',"media_ok":%d,"media_fail":%d,"media_skipped":%d' \
        "${media_ok:-0}" "${media_fail:-0}" "${media_skip:-0}"
    printf ',"gallery_ok":%d,"gallery_fail":%d' \
        "${gallery_ok:-0}" "${gallery_fail:-0}"
    printf ',"images_ok":%d,"images_fail":%d,"images_skipped":%d' \
        "${img_ok:-0}" "${img_fail:-0}" "${img_skip:-0}"
    printf ',"archive_failed":%d' "${archive_fail:-0}"
}

print_json_report() {
    local exit_code=$1 i sep=''
    printf '{"version":"%s","started_at":"%s","finished_at":"%s",' \
        "$(json_escape "$VDL_VERSION")" \
        "$(json_escape "${run_started_at:-}")" \
        "$(json_escape "$(date -u +%Y-%m-%dT%H:%M:%SZ)")"
    printf '"dry_run":false,"save_dir":"%s","counts":{%s},"items":[' \
        "$(json_escape "${save_dir_abs:-$save_dir}")" "$(json_counts)"
    for i in "${!report_urls[@]}"; do
        printf '%s' "$sep"
        print_item_json "$i"
        sep=','
    done
    printf '],"archive":%s,"exit_code":%d}\n' \
        "$(json_string_or_null "${zip_created:-}")" "$exit_code"
}

print_json_lines_report() {
    local exit_code=$1 i
    for i in "${!report_urls[@]}"; do
        print_item_json "$i"
        printf '\n'
    done
    printf '{"type":"summary","version":"%s","started_at":"%s","finished_at":"%s",' \
        "$(json_escape "$VDL_VERSION")" \
        "$(json_escape "${run_started_at:-}")" \
        "$(json_escape "$(date -u +%Y-%m-%dT%H:%M:%SZ)")"
    printf '"save_dir":"%s","counts":{%s},"archive":%s,"exit_code":%d}\n' \
        "$(json_escape "${save_dir_abs:-$save_dir}")" "$(json_counts)" \
        "$(json_string_or_null "${zip_created:-}")" "$exit_code"
}

# Dry-run plan as one JSON object.  No network or filesystem writes.
print_json_plan() {
    local i sep=''
    printf '{"version":"%s","started_at":"%s","dry_run":true,' \
        "$(json_escape "$VDL_VERSION")" \
        "$(json_escape "${run_started_at:-}")"
    printf '"engine":"%s","mode":"%s","save_dir":"%s","urls":[' \
        "$(json_escape "${engine:-}")" "$(json_escape "${mode:-}")" \
        "$(json_escape "${save_dir_abs:-$save_dir}")"
    for i in "${!urls[@]}"; do
        printf '%s"%s"' "$sep" "$(json_escape "${urls[$i]}")"
        sep=','
    done
    printf '],"counts":{"direct":%d,"media":%d,"gallery":%d,"images":%d},' \
        "${#direct[@]}" "${#media[@]}" "${#gallery[@]}" "${#img_urls[@]}"
    printf '"impersonate":%s}\n' "$(json_string_or_null "${impersonate:-}")"
}
