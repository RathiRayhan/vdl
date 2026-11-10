#!/usr/bin/env bash
# shellcheck shell=bash
# shellcheck disable=SC1091,SC2154
# Smoke tests for vdl. Uses stub yt-dlp / aria2c / ffmpeg / wl-paste binaries,
# so it needs nothing but bash and coreutils.
#
# Cases live in test/smoke/cases/*.sh and run in filename order.
#
# Run: bash test/smoke.sh

set -uo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
smoke_dir=$root/test/smoke

# shellcheck source=smoke/setup.sh
source "$smoke_dir/setup.sh"

for case_file in "$smoke_dir"/cases/*.sh; do
    # shellcheck source=/dev/null
    source "$case_file"
done

printf '\n%d passed, %d failed\n' "$pass" "$fail"
(( fail == 0 ))
