# shellcheck shell=bash
# shellcheck disable=SC2154

# Audio extraction mode.

# --- audio mode ------------------------------------------------------------
if run -n -a 'https://example.com/watch?v=abc' \
    && arg_has '--audio-format' && arg_is mp3 \
    && arg_has "$VDL_SAVE_DIR/audio"; then
    ok
else
    bad "audio mode should extract MP3 into <save>/audio"
fi

