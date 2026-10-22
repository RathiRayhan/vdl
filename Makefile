# Makefile for vdl — portable smart downloader for Linux

.PHONY: test lint install clean man

## Run the smoke test suite
test:
	bash test/smoke.sh

## Lint all shell scripts with shellcheck
lint:
	shellcheck bin/vdl install.sh test/smoke.sh completions/vdl completions/vdl.fish completions/_vdl

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
