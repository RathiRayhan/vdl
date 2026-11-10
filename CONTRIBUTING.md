# Contributing to vdl

Thanks for helping improve vdl! It is a Bash project: a thin orchestrator
(`bin/vdl`) plus focused libraries in `lib/vdl/`. This file explains the
layout, the conventions, and how to make a change end to end.

## Before you start

1. Read **[docs/SPEC.md](docs/SPEC.md)** — it is the behavior contract:
   pipeline, routing table, exit codes, shared state, and feature-specific
   rules.
2. Check the issue tracker for existing discussions, or open an issue to
   discuss non-trivial changes first.

## Getting set up

```sh
git clone https://github.com/RathiRayhan/vdl.git
cd vdl
bash test/smoke.sh   # needs nothing but bash + coreutils
bash test/unit.sh
make lint            # needs shellcheck on PATH
```

## Repository layout

| Path | Purpose |
|------|---------|
| `bin/vdl` | Orchestrator: sources the libraries and runs the pipeline |
| `lib/vdl/*.sh` | One library per phase (see the SPEC file map) |
| `install.sh` | Installer / uninstaller |
| `completions/` | bash, zsh, fish completions |
| `man/vdl.1` | Man page |
| `docs/USAGE.md` | User guide |
| `docs/SPEC.md` | Behavior contract |
| `test/smoke.sh` | Stub-based end-to-end CLI test runner |
| `test/smoke/cases/` | Individual smoke-test case files (run in filename order) |
| `test/unit.sh` | Unit tests for pure helpers |
| `test/integration.sh` | End-to-end tests against the real yt-dlp/aria2c/ffmpeg on a local fixture |
| `lib/vdl/scrape.py` | HTML image extractor used by `--images` (python3; regex fallback included) |

## Making a change

1. **Keep the split.** New logic belongs in the matching `lib/vdl/` file as
   a function; `bin/vdl` only wires phases together. Pure helpers go into
   `lib/vdl/helpers.sh` so they stay unit-testable.
2. **Follow the contracts.** Update `docs/SPEC.md` whenever behavior, exit
   codes, routing, or shared state change.
3. **Add tests.**
   - New or changed CLI behavior → a case file in `test/smoke/cases/` (uses
     stub binaries; no network needed). Cases run in filename order, so pick
     a descriptive number and keep related state changes together.
   - New pure function → cases in `test/unit.sh`.
4. **Update docs.** `--help` (`lib/vdl/helpers.sh`), the man page,
   `docs/USAGE.md`, and the README when adding or changing options.
   Completions live in `completions/`.
5. **Run everything.**

```sh
make test               # smoke + unit
make test-integration   # real downloaders, local fixture (needs yt-dlp, aria2c, ffmpeg)
make lint
```

## Style

- Bash 4+, `set -u -o pipefail` (add `-e` in install.sh).
- Quote expansions; use `[[ ... ]]`.
- Library files start with `# shellcheck shell=bash` and a
  `# shellcheck disable=` comment listing the warnings that only make sense
  cross-file (`SC2154`, `SC2034`, `SC2329`).
- Keep `bin/vdl` an orchestrator — no engine logic.
- Messages go through `warn`/`err`/`note` (stderr) or the `ui_*` helpers
  (stdout, silenced by `--quiet`).

## Commit messages

Use short imperative subjects, e.g. `add --output for exact destinations`.
One logical change per commit.

## CI

Every push to `main` runs ShellCheck (the Ubuntu-packaged version) on all
scripts plus the smoke and unit suites. Keep both green.
