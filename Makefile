# Makefile for vdl — portable smart downloader for Linux

.PHONY: test lint install clean man

## Run the smoke and unit test suites
test:
	bash test/smoke.sh
	bash test/unit.sh

## Run the integration suite against the real yt-dlp/aria2c/ffmpeg
## (local HTTP fixture, no internet; needs python3, yt-dlp, aria2c, ffmpeg)
test-integration:
	bash test/integration.sh

## Lint all shell scripts with shellcheck
lint:
	@command -v shellcheck >/dev/null 2>&1 || { \
		echo "shellcheck not found in PATH; install it (apt install shellcheck) or run the CI workflow." >&2; \
		exit 1; \
	}
	shellcheck --shell=bash bin/vdl install.sh test/smoke.sh test/unit.sh \
		test/smoke/setup.sh test/smoke/stub.sh test/smoke/cases/*.sh \
		lib/vdl/ui.sh lib/vdl/helpers.sh lib/vdl/images.sh lib/vdl/downloads.sh \
		lib/vdl/gallery.sh lib/vdl/args.sh lib/vdl/settings.sh lib/vdl/collect.sh lib/vdl/paths.sh \
		lib/vdl/classify.sh lib/vdl/ytdlp.sh lib/vdl/plan.sh lib/vdl/report.sh lib/vdl/doctor.sh
	shellcheck completions/vdl.bash

## Install vdl locally (user-level)
install:
	./install.sh

## Install system-wide
install-system:
	sudo ./install.sh --system

## Generate the man page from the script's --help output
man:
	@# This is a placeholder; the real man page ships in man/vdl.1
	@echo "Man page source: man/vdl.1"

## Remove temp artifacts
clean:
	rm -rf /tmp/vdl-lm
