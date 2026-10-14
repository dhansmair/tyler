PREFIX ?= $(HOME)/.local/bin
# Optional code-signing identity, e.g. `make install SIGN_ID=tyler-dev`.
SIGN_ID ?=

# The Command Line Tools ship Swift Testing, but SwiftPM doesn't search for it there.
# Harmless when full Xcode is installed.
CLT_DEV := /Library/Developer/CommandLineTools/Library/Developer
TEST_FLAGS := \
	-Xswiftc -F -Xswiftc $(CLT_DEV)/Frameworks \
	-Xlinker -F -Xlinker $(CLT_DEV)/Frameworks \
	-Xlinker -rpath -Xlinker $(CLT_DEV)/Frameworks \
	-Xlinker -rpath -Xlinker $(CLT_DEV)/usr/lib

.PHONY: build test test-unit test-scenario lint check release install clean

build:
	swift build

test:
	swift test $(TEST_FLAGS)

# The layers of devdocs/testing-strategy.md on their own: `test` runs both.
test-unit:
	swift test $(TEST_FLAGS) --skip TylerScenarioTests

test-scenario:
	swift test $(TEST_FLAGS) --filter TylerScenarioTests

# SwiftLint needs the Command Line Tools' sourcekitd when full Xcode isn't installed.
lint:
	swift format lint --recursive --strict Sources Tests Package.swift
	TOOLCHAIN_DIR=$${TOOLCHAIN_DIR:-/Library/Developer/CommandLineTools} swiftlint --strict --quiet
	devtools/check-test-paths

# Everything the pre-commit hook checks, over the whole tree.
check: lint test

# The products only: TylerTestSupport imports TylerServer with @testable, which a release build
# doesn't allow.
release:
	swift build -c release --product tyler
	swift build -c release --product tylerd

install: release
	mkdir -p $(PREFIX)
	cp .build/release/tyler .build/release/tylerd $(PREFIX)/
ifneq ($(SIGN_ID),)
	codesign --force --sign "$(SIGN_ID)" $(PREFIX)/tyler $(PREFIX)/tylerd
endif
	@echo "installed to $(PREFIX)"

clean:
	swift package clean
