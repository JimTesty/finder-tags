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

clean:
	rm -rf "$(BUILD_DIR)"
