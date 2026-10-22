#!/usr/bin/env bash
# shellcheck shell=bash
# vdl installer
#
# Usage: ./install.sh [options]
#   --prefix DIR       install prefix (default: ~/.local)
#   --system           shortcut for --prefix /usr/local
#   --shells LIST      comma-separated: bash,zsh,fish (default: auto-detect)
#   --no-completions   install the command only
#   --uninstall        remove the command and completions
#   -h, --help         show this help

set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
prefix=$HOME/.local
system_install=0
shells=auto
install_completions=1
uninstall=0

usage() {
    sed -n '2,10p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

while (( $# > 0 )); do
    case $1 in
        --prefix)
            (( $# > 1 )) || { echo "install.sh: --prefix requires a value" >&2; exit 2; }
            prefix=$2
            shift 2
            ;;
        --prefix=*)
            prefix=${1#*=}
            shift
            ;;
        --system)
            prefix=/usr/local
            system_install=1
            shift
            ;;
        --shells)
            (( $# > 1 )) || { echo "install.sh: --shells requires a value" >&2; exit 2; }
            shells=$2
            shift 2
            ;;
        --shells=*)
            shells=${1#*=}
            shift
            ;;
        --no-completions)
            install_completions=0
            shift
            ;;
        --uninstall)
            uninstall=1
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "install.sh: unknown option: $1" >&2
            exit 2
            ;;
    esac
done

prefix=${prefix/#\~/$HOME}
[[ $prefix == /* ]] || prefix=$PWD/$prefix
prefix=${prefix%/}

config_home=${XDG_CONFIG_HOME:-$HOME/.config}
data_home=${XDG_DATA_HOME:-$HOME/.local/share}

fish_dir="$config_home/fish/completions"
bash_dir="$data_home/bash-completion/completions"
zsh_dir="$data_home/zsh/site-functions"
src_fish=vdl.fish
src_bash=vdl.bash
src_zsh=_vdl
dst_fish=vdl.fish
dst_bash=vdl
dst_zsh=_vdl

if (( system_install )); then
    fish_dir="$prefix/share/fish/vendor_completions.d"
    bash_dir="$prefix/share/bash-completion/completions"
    zsh_dir="$prefix/share/zsh/site-functions"
fi

detect_shells() {
    local found=''
    if [[ -d $config_home/fish ]] || command -v fish >/dev/null 2>&1; then
        found+=" fish"
    fi
    if [[ -f $HOME/.zshrc ]] || command -v zsh >/dev/null 2>&1; then
        found+=" zsh"
    fi
    if [[ -f $HOME/.bashrc ]] || command -v bash >/dev/null 2>&1; then
        found+=" bash"
    fi
    printf '%s\n' "${found:- bash}"
}

if [[ $shells == auto ]]; then
    shells=$(detect_shells)
else
    shells=${shells//,/ }
fi

do_remove() {
    local removed=0
    for path in \
        "$prefix/bin/vdl" \
        "$prefix/share/man/man1/vdl.1" \
        "$fish_dir/$dst_fish" \
        "$bash_dir/$dst_bash" \
        "$zsh_dir/$dst_zsh"
    do
        if [[ -e $path ]]; then
            rm -f -- "$path"
            printf 'removed %s\n' "$path"
            removed=$((removed + 1))
        fi
    done
    return 0
}

if (( uninstall )); then
    do_remove
    printf '\nvdl uninstalled.\n'
    exit 0
fi

if [[ ! -f $script_dir/bin/vdl ]]; then
    echo "install.sh: bin/vdl not found (run this from the project root)" >&2
    exit 1
fi

if ! command -v yt-dlp >/dev/null 2>&1; then
    printf 'warning: yt-dlp is not installed or not in PATH; vdl needs it.\n' >&2
fi

# Pre-check write permissions to the target prefix so the user gets a
# clear error instead of a confusing install(1) failure midway through.
if (( system_install )); then
    if [[ ! -w $prefix ]] && ! [[ $EUID -eq 0 ]]; then
        printf 'install.sh: %s is not writable and you are not root.\n' "$prefix" >&2
        printf '         Run with sudo or use --prefix ~/.local\n' >&2
        exit 1
    fi
fi

install -d -- "$prefix/bin"

if [[ -f $script_dir/man/vdl.1 ]]; then
    install -d -- "$prefix/share/man/man1"
    install -m 0644 -- "$script_dir/man/vdl.1" "$prefix/share/man/man1/vdl.1"
    printf 'installed %s\n' "$prefix/share/man/man1/vdl.1"
fi

install -m 0755 -- "$script_dir/bin/vdl" "$prefix/bin/vdl"
printf 'installed %s\n' "$prefix/bin/vdl"

if (( install_completions )); then
    for sh in $shells; do
        case $sh in
            fish)
                if [[ -f $script_dir/completions/$src_fish ]]; then
                    install -d -- "$fish_dir"
                    install -m 0644 -- "$script_dir/completions/$src_fish" "$fish_dir/$dst_fish"
                    printf 'installed %s\n' "$fish_dir/$dst_fish"
                fi
                ;;
            bash)
                if [[ -f $script_dir/completions/$src_bash ]]; then
                    install -d -- "$bash_dir"
                    install -m 0644 -- "$script_dir/completions/$src_bash" "$bash_dir/$dst_bash"
                    printf 'installed %s\n' "$bash_dir/$dst_bash"
                fi
                ;;
            zsh)
                if [[ -f $script_dir/completions/$src_zsh ]]; then
                    install -d -- "$zsh_dir"
                    install -m 0644 -- "$script_dir/completions/$src_zsh" "$zsh_dir/$dst_zsh"
                    printf 'installed %s\n' "$zsh_dir/$dst_zsh"
                fi
                ;;
            *)
                printf 'warning: unknown shell "%s" skipped (use bash,zsh,fish)\n' "$sh" >&2
                ;;
        esac
    done
fi

case ":$PATH:" in
    *":$prefix/bin:"*) ;;
    *)
        printf '\nNote: %s/bin is not in your PATH. Add it, e.g.:\n' "$prefix"
        printf '  export PATH="%s/bin:$PATH"\n' "$prefix"
        ;;
esac

if (( install_completions )) && [[ " $shells " == *" zsh "* ]] && (( ! system_install )); then
    printf '\nNote: for zsh completions, make sure this runs before compinit:\n'
    printf '  fpath=("%s" $fpath)\n' "$zsh_dir"
fi

printf '\nDone. Run "vdl --help" to get started.\n'
