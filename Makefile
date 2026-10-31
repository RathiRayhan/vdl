# Makefile for vdl — portable smart downloader for Linux

.PHONY: test lint install clean man

## Run the smoke and unit test suites
test:
	bash test/smoke.sh
	bash test/unit.sh

## Lint all shell scripts with shellcheck
lint:
	shellcheck --shell=bash bin/vdl install.sh test/smoke.sh test/unit.sh \
		lib/vdl/ui.sh lib/vdl/helpers.sh lib/vdl/images.sh lib/vdl/downloads.sh
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
