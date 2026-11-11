# shellcheck shell=bash
# shellcheck disable=SC2154

# JSON reports and the environment doctor.

json_ok() { # file
    python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$1" >/dev/null 2>&1
}

# --- --json dry-run ---------------------------------------------------------
run -n --json --dry-run 'https://example.com/a.iso' 'https://example.com/watch?v=x'
rc=$?
if [[ $rc -eq 0 ]] && json_ok "$out" \
    && python3 - "$out" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["dry_run"] is True
assert d["counts"]["direct"] == 1 and d["counts"]["media"] == 1
assert len(d["urls"]) == 2
PY
then
    ok
else
    bad "--json --dry-run should emit a valid plan object"
fi

# --- --json normal run ------------------------------------------------------
run -n --json 'https://example.com/file.iso'
rc=$?
if [[ $rc -eq 0 ]] && json_ok "$out" \
    && python3 - "$out" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["dry_run"] is False
assert d["counts"]["direct_ok"] == 1
assert d["items"][0]["engine"] == "aria2c"
assert d["items"][0]["status"] == "ok"
assert d["exit_code"] == 0
PY
then
    ok
else
    bad "--json should emit one valid report object"
fi

# --- --json reports skipped and failed media items accurately ---------------
export FAKE_YTDLP_SKIP=yes
run -n --json 'https://example.com/watch?v=x'
rc=$?
unset FAKE_YTDLP_SKIP
if [[ $rc -eq 0 ]] \
    && python3 - "$out" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["counts"]["media_skipped"] == 1
assert d["items"][0]["status"] == "skipped"
assert d["items"][0]["engine"] == "yt-dlp"
PY
then
    ok
else
    bad "--json should report a skipped media item"
fi

export FAKE_YTDLP_FAIL=forbidden
run -n --json 'https://example.com/watch?v=x'
rc=$?
unset FAKE_YTDLP_FAIL
if [[ $rc -eq 1 ]] && json_ok "$out" \
    && python3 - "$out" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["exit_code"] == 1
assert d["counts"]["media_fail"] == 1
assert d["items"][0]["status"] == "failed"
assert "yt-dlp exit 1" in d["items"][0]["error"]
PY
then
    ok
else
    bad "--json should report a failed media item and keep stdout valid"
fi

# --- --json includes the archive result -------------------------------------
export FAKE_ARIA_DUP=yes
run -n --json --zip=report.zip 'https://example.com/archive.iso'
rc=$?
unset FAKE_ARIA_DUP
if [[ $rc -eq 0 ]] \
    && python3 - "$out" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["archive"] == "report.zip"
assert d["counts"]["direct_ok"] == 1
assert d["items"][0]["files"]
PY
then
    ok
else
    bad "--json should include the created archive and file paths"
fi

# --- --json-lines -----------------------------------------------------------
run -n --json-lines 'https://example.com/a.iso' 'https://example.com/b.iso'
rc=$?
if [[ $rc -eq 0 ]] \
    && python3 - "$out" <<'PY'
import json, sys
rows = [json.loads(line) for line in open(sys.argv[1]) if line.strip()]
assert len(rows) == 3
assert [r["type"] for r in rows] == ["item", "item", "summary"]
assert rows[-1]["counts"]["direct_ok"] == 2
PY
then
    ok
else
    bad "--json-lines should emit item objects followed by a summary"
fi

# --- --doctor text and JSON -------------------------------------------------
run --doctor
rc=$?
if [[ $rc -eq 0 ]] && grep -q 'vdl doctor' "$out" \
    && grep -q '\[ok\].*yt-dlp' "$out" \
    && grep -q '\[ok\].*save dir' "$out"; then
    ok
else
    bad "--doctor should report tools and a writable save path"
fi

run --doctor --json
rc=$?
if [[ $rc -eq 0 ]] && json_ok "$out" \
    && python3 - "$out" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["ok"] is True
assert any(c["name"] == "yt-dlp" and c["status"] == "ok" for c in d["checks"])
PY
then
    ok
else
    bad "--doctor --json should emit a valid check report"
fi

# --- --doctor fails when yt-dlp is missing ----------------------------------
# Use a minimal PATH so the real /usr/bin/yt-dlp cannot satisfy the check.
minbin=$tmp/doctor_minbin
mkdir -p "$minbin"
for tool in date dirname readlink pwd mktemp mkdir rm find stat awk tr head timeout df wc; do
    tool_path=$(command -v "$tool" 2>/dev/null) && ln -sf "$tool_path" "$minbin/$tool"
done
PATH="$minbin" HOME="$home" NO_COLOR=1 XDG_CACHE_HOME="$tmp/doctor_cache" \
    "$BASH" "$root/bin/vdl" --doctor >"$out" 2>"$err"
rc=$?
if [[ $rc -eq 1 ]] && grep -q '\[FAIL\].*yt-dlp' "$out"; then
    ok
else
    bad "--doctor should exit 1 when yt-dlp is missing"
fi
