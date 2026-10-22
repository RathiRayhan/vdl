# bash completion for vdl
# Install as ~/.local/share/bash-completion/completions/vdl

_vdl() {
    local cur prev
    cur=${COMP_WORDS[COMP_CWORD]}
    prev=${COMP_WORDS[COMP_CWORD-1]}

    case $prev in
        -b|--browser)
            COMPREPLY=( $(compgen -W "vivaldi firefox brave chromium chrome edge opera safari whale none" -- "$cur") )
            return
            ;;
        -q|--quality)
            COMPREPLY=( $(compgen -W "360 480 720 1080 1440 2160 4320 2k 4k 8k" -- "$cur") )
            return
            ;;
        -i|--batch-file)
            COMPREPLY=( $(compgen -f -- "$cur") )
            return
            ;;
        --referer|--user-agent|--proxy)
            return
            ;;
    esac

    if [[ $cur == -* ]]; then
        COMPREPLY=( $(compgen -W "--help --version --browser --no-cookies --quality --audio --batch-file --no-aria --no-impersonate --download-dir --dry-run --quiet --aria-opts --max-speed --limit-speed --referer --user-agent --proxy" -- "$cur") )
    elif [[ $cur == *=* && $prev == --* ]]; then
        return
    else
        COMPREPLY=( $(compgen -f -X '!*.txt' -- "$cur") )
    fi
}

complete -F _vdl vdl
