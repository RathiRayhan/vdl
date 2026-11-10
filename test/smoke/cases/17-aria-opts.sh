# shellcheck shell=bash
# shellcheck disable=SC2154

# Raw aria2c option forwarding.

# --- aria-opts forwarding --------------------------------------------------
run -n --aria-opts '--check-interval=30 --max-connection-per-server=4' \
    'https://example.com/file.iso'
if arg_is '--check-interval=30' && arg_is '--max-connection-per-server=4'; then
    ok
else
    bad "--aria-opts should be forwarded to aria2c verbatim"
fi

