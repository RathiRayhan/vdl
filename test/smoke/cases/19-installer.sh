# shellcheck shell=bash
# shellcheck disable=SC2154

# Installer and uninstaller.

# --- installer (now also installs man page) ----------------------------------
prefix=$tmp/prefix
if PATH="$fakebin:/usr/bin:/bin" bash "$root/install.sh" \
    --prefix "$prefix" --shells bash,fish >/dev/null 2>&1 \
    && [[ -x $prefix/bin/vdl ]] \
    && [[ -f "$prefix/share/man/man1/vdl.1" ]] \
    && [[ -f $home/.local/share/bash-completion/completions/vdl ]] \
    && [[ -f $home/.config/fish/completions/vdl.fish ]]; then
    ok
else
    bad "installer should place the command, completions and man page"
fi

if PATH="$fakebin:/usr/bin:/bin" bash "$root/install.sh" \
    --uninstall --prefix "$prefix" >/dev/null 2>&1 \
    && [[ ! -e $prefix/bin/vdl ]] \
    && [[ ! -e $home/.local/share/bash-completion/completions/vdl ]] \
    && [[ ! -e $home/.config/fish/completions/vdl.fish ]]; then
    ok
else
    bad "uninstaller should remove installed files"
fi

