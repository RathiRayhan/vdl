#!/usr/bin/env bash
# shellcheck shell=bash
# shellcheck disable=SC2034,SC2154,SC2329  # globals live in bin/vdl or the libs
#
# vdl URL collection: positional URLs, batch files, clipboard fallback,
# order-preserving dedupe, and the single-URL checks for --name/--output.

collect_urls() {
    urls=()

    # Classify one positional token: URL-shaped tokens become downloads,
    # bare .txt files become batch files, everything else is a yt-dlp
    # passthrough value.  Lines from a pasted multi-line block use kind
    # "paste": non-URL lines are ignored instead of forwarded.
    collect_token() {
        local arg=$1 kind=$2
        case $arg in
            '') ;;
            http://*|https://*)
                urls+=("$arg")
                ;;
            www.*)
                urls+=("https://$arg")
                ;;
            magnet:*)
                urls+=("$arg")
                ;;
            *.txt)
                # A bare .txt is a batch file unless it is the value of an
                # unknown flag (e.g. --download-archive archive.txt).
                if [[ -f $arg && ($kind == pos || $kind == paste) ]]; then
                    batch_files+=("$arg")
                elif [[ $kind != paste ]]; then
                    passthru+=("$arg")
                fi
                ;;
            *)
                [[ $kind == paste ]] || passthru+=("$arg")
                ;;
        esac
    }

    # raw_args preserves the original argument order.  Non-URL tokens,
    # including values belonging to unknown yt-dlp options, stay in passthru
    # in that order; only URL-shaped tokens and bare batch files are pulled
    # out.  A positional argument containing newlines is a pasted block of
    # URLs and is split into one token per line (flag values are never
    # split, so forwarded options stay intact).
    local i arg line
    for i in "${!raw_args[@]}"; do
        arg=${raw_args[$i]}
        if [[ ${raw_kind[$i]} == pos && $arg == *$'\n'* ]]; then
            while IFS= read -r line || [[ -n $line ]]; do
                line=${line%$'\r'}
                line=${line#"${line%%[![:space:]]*}"}
                line=${line%"${line##*[![:space:]]}"}
                collect_token "$line" paste
            done <<< "$arg"
        else
            collect_token "$arg" "${raw_kind[$i]}"
        fi
    done

    if (( ${#batch_files[@]} )); then
        local f
        for f in "${batch_files[@]}"; do
            if [[ ! -f $f ]]; then
                warn "Batch file not found: $f"
                continue
            fi
            while IFS= read -r line || [[ -n $line ]]; do
                line=${line%$'\r'}
                line=${line#"${line%%[![:space:]]*}"}
                line=${line%"${line##*[![:space:]]}"}
                if [[ $line =~ ^https?:// ]]; then
                    urls+=("$line")
                fi
            done < "$f"
        done
    fi

    if (( ${#urls[@]} == 0 )); then
        local clip
        if clip=$(read_clipboard) && [[ $clip =~ ^https?:// ]]; then
            urls+=("$clip")
            note "Auto-grabbed URL from clipboard"
        else
            err "No valid URL, batch file, or clipboard link found."
            printf '    Run vdl --help for usage.\n' >&2
            exit 1
        fi
    fi

    # Remove duplicates while preserving order.
    declare -A seen=()
    declare -a uniq_urls=()
    for u in "${urls[@]}"; do
        [[ -n ${seen[$u]:-} ]] && continue
        seen[$u]=1
        uniq_urls+=("$u")
    done
    urls=("${uniq_urls[@]}")

    # --name applies to a single URL; remember it before images are appended.
    named_url=''
    if [[ -n $custom_name ]]; then
        if (( ${#urls[@]} != 1 )); then
            err "--name works with a single URL"
            exit 2
        fi
        named_url=${urls[0]}
    fi

    # --output is the exact destination for a single URL.
    if [[ -n $output_arg ]]; then
        (( ${#urls[@]} == 1 )) || { err "--output works with a single URL"; exit 2; }
        [[ -z $custom_name ]] || { err "--output cannot be combined with --name"; exit 2; }
    fi
}
