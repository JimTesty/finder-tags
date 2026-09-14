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
	$(SWIFTC) $(SWIFTFLAGS) $(SOURCES) -o "$(BINARY)"

debug:
	@mkdir -p "$(BUILD_DIR)"
	$(SWIFTC) -Onone -g -swift-version 5 $(SOURCES) -o "$(BINARY)"

test: build
	sh Tests/cli.sh "$(BINARY)"

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
