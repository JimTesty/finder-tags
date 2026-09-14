.PHONY: build test install clean

build:
	swift build -c release

test:
	swift build
	.build/debug/tag --help >/dev/null
	.build/debug/tag --version >/dev/null

PREFIX ?= $(HOME)/.local
install: build
	install -d "$(PREFIX)/bin"
	install -m 755 "$$(swift build -c release --show-bin-path)/tag" "$(PREFIX)/bin/tag"

clean:
	swift package clean
