# shellcheck shell=bash
# shellcheck disable=SC2154

# Config file and environment defaults.

# --- config file -----------------------------------------------------------
confdir=$tmp/cfgtest/.config/vdl
mkdir -p "$confdir"
printf 'QUALITY=480\n' > "$confdir/config"
HOME=$tmp/cfgtest XDG_CONFIG_HOME="$tmp/cfgtest/.config" \
    run -n 'https://example.com/watch?v=abc'
if arg_has 'height<=480'; then
    ok
else
    bad "config file should set default quality"
fi
unset XDG_CONFIG_HOME

vcdir=$tmp/cfgdir
mkdir -p "$vcdir"
printf 'QUALITY=480\n' > "$vcdir/config"
VDL_CONFIG_DIR=$vcdir run -n 'https://example.com/watch?v=abc'
if arg_has 'height<=480'; then
    ok
else
    bad "VDL_CONFIG_DIR/config should set default quality"
fi

