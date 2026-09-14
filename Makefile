SWIFTC ?= swiftc
PREFIX ?= $(HOME)/.local
BUILD_DIR ?= build
BINARY := $(BUILD_DIR)/tag
SOURCES := $(wildcard Sources/tag/*.swift)
SWIFTFLAGS ?= -O

.PHONY: all build debug test install clean

all: build

build: $(BINARY)

$(BINARY): $(SOURCES)
	@mkdir -p "$(BUILD_DIR)"
	$(SWIFTC) $(SWIFTFLAGS) $(SOURCES) -o "$(BINARY)"

debug:
	@mkdir -p "$(BUILD_DIR)"
	$(SWIFTC) -Onone -g $(SOURCES) -o "$(BINARY)"

test: build
	sh Tests/cli.sh "$(BINARY)"

install: build
	install -d "$(PREFIX)/bin"
	install -m 755 "$(BINARY)" "$(PREFIX)/bin/tag"

clean:
	rm -rf "$(BUILD_DIR)"
