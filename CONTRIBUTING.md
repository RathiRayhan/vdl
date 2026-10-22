# Contributing to vdl

Thanks for taking the time to contribute!  This document covers the most
common tasks and conventions.

## Prerequisites

| Tool | Purpose | Install hint |
|------|---------|-------------|
| `bash` >= 4 | running vdl and the test suite | base system |
| `shellcheck` | linting | `sudo apt install shellcheck` |
| `bats` (optional) | running the test suite natively | `sudo apt install bats` |

## Running tests

The smoke tests use stub binaries for `yt-dlp`, `aria2c`, `ffmpeg`, and
`wl-paste`, so no network access or real downloads are required.

```sh
make test          # or: bash test/smoke.sh
```

To add a new test case, append it to `test/smoke.sh`.  Each case should:

1. Be self-contained and reset `PATH` to the fake-bin directory.
2. Call `run ...` with the desired arguments.
3. Assert on `called`, `arg_is`, or `arg_has` helpers, or on exit codes.
4. End with `ok` or `bad "..."`.

## Linting

```sh
make lint          # or: shellcheck bin/vdl install.sh test/smoke.sh completions/*
```

All shell scripts in this repository should pass `shellcheck` with no warnings.
The `# shellcheck shell=bash` directive at the top of each script tells
shellcheck to target Bash 4+ semantics.

## Code style

- Two-space indentation for continuation lines.
- `printf` for output (never `echo -e`).
- Use `set -u` (unbound variables) and `set -o pipefail` in all scripts.
- Prefer `[[ ... ]]` over `[ ... ]`.
- Keep `bin/vdl` self-contained; default yt-dlp flags live there, not in a
  global config file.

## Submitting changes

1. Fork the repository.
2. Create a feature branch.
3. Make your changes.
4. Ensure `make lint` and `make test` pass.
5. Open a pull request with a clear description of the change.

## Reporting bugs

If you find a bug, please open an issue with:

- Your OS and distribution.
- The `vdl --version` output.
- The exact command you ran.
- The relevant portion of the output (errors, banners).
- Your `yt-dlp --version` and `aria2c --version` if relevant.
