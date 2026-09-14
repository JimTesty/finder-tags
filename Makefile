SWIFTC ?= swiftc
PREFIX ?= $(HOME)/.local
BUILD_DIR ?= build
BINARY := $(BUILD_DIR)/tag
SOURCES := $(wildcard Sources/tag/*.swift)
SWIFTFLAGS ?= -O -swift-version 5

.PHONY: all build debug test compat install clean

all: build

build: $(BINARY)

$(BINARY): $(SOURCES) Makefile
	@mkdir -p "$(BUILD_DIR)"
	@echo "Compiling $(BINARY) with $(SWIFTC) $(SWIFTFLAGS)"
	@if $(SWIFTC) $(SWIFTFLAGS) $(SOURCES) -o "$(BINARY)"; then \
		:; \
	else \
		status=$$?; \
		echo >&2; \
		echo "make: Swift compilation failed (exit $$status)." >&2; \
		echo "Build environment:" >&2; \
		echo "  swiftc: $$(command -v $(SWIFTC) 2>/dev/null || echo unavailable)" >&2; \
		echo "  swiftc version: $$( $(SWIFTC) --version 2>&1 | sed -n '1p' )" >&2; \
		echo "  developer directory: $$(xcode-select -p 2>/dev/null || echo unavailable)" >&2; \
		echo "  macOS SDK: $$(xcrun --show-sdk-path 2>/dev/null || echo unavailable)" >&2; \
		echo >&2; \
		echo "If the errors mention SwiftShims, Swift.swiftmodule, or a module cache," >&2; \
		echo "the selected Swift compiler and macOS SDK are likely from mismatched" >&2; \
		echo "Command Line Tools or Xcode installations. Select one matching" >&2; \
		echo "developer directory or reinstall the Command Line Tools, then run:" >&2; \
		echo "  make clean" >&2; \
		echo "  make" >&2; \
		exit $$status; \
	fi

debug:
	@mkdir -p "$(BUILD_DIR)"
	$(SWIFTC) -Onone -g -swift-version 5 $(SOURCES) -o "$(BINARY)"

test: build
	@echo "Running CLI tests"
	@if sh Tests/cli.sh "$(BINARY)"; then \
		:; \
	else \
		status=$$?; \
		echo >&2; \
		echo "make: CLI tests failed (exit $$status)." >&2; \
		echo "For the failing assertion, rerun with shell tracing:" >&2; \
		echo "  sh -x Tests/cli.sh $(BINARY)" >&2; \
		exit $$status; \
	fi

compat: build
	@test -n "$(JDBERRY_TAG)" || { echo "usage: make compat JDBERRY_TAG=/path/to/jdberry/tag" >&2; exit 64; }
	sh Tests/compat-jdberry.sh "$(BINARY)" "$(JDBERRY_TAG)"

install: build
	install -d "$(PREFIX)/bin"
	install -m 755 "$(BINARY)" "$(PREFIX)/bin/tag"
	install -d "$(PREFIX)/share/man/man1"
	install -m 644 Docs/tag.1 "$(PREFIX)/share/man/man1/tag.1"
	install -d "$(PREFIX)/share/bash-completion/completions"
	install -m 644 Completions/tag.bash "$(PREFIX)/share/bash-completion/completions/tag"
	install -d "$(PREFIX)/share/zsh/site-functions"
	install -m 644 Completions/_tag "$(PREFIX)/share/zsh/site-functions/_tag"
	install -d "$(PREFIX)/share/fish/vendor_completions.d"
	install -m 644 Completions/tag.fish "$(PREFIX)/share/fish/vendor_completions.d/tag.fish"

clean:
	rm -rf "$(BUILD_DIR)"
