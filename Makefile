PREFIX ?= $(HOME)/.local/bin
# Optional code-signing identity, e.g. `make install SIGN_ID=tyler-dev`, or set once in local.mk
# (git-ignored). With one, `build` and `install` also build Tyler.app, which tylerd runs as with a
# grant of its own; without, tylerd runs under the terminal's grant (devdocs/design.md, Releases).
SIGN_ID ?=
-include local.mk

APP_ID := io.github.dhansmair.tyler
# Builds Tyler.app in the bin folder $(1) with bundle ID $(2), name $(3) and placement $(4)
# (devtools/make-app). A development build is only bundled when signed, as an ad-hoc bundle would
# need the grant after every build; otherwise an old one is removed so `tyler` doesn't launch it.
# A release is bundled either way, ad hoc without SIGN_ID: the grant is then asked for again
# after each update.
define bundle
	$(if $(SIGN_ID),devtools/make-app "$(1)" "$(2)" "$(3)" "$(SIGN_ID)" $(4),rm -rf "$(1)/Tyler.app")
endef
define release_bundle
	devtools/make-app "$(1)" "$(2)" "$(3)" "$(or $(SIGN_ID),-)" $(4)
endef

# The Command Line Tools ship Swift Testing, but SwiftPM doesn't search for it there, nor for its
# macro plugin, which sits in a folder of its own. Only for them: Xcode finds its own, and a
# plugin of the Command Line Tools may not match Xcode's compiler.
CLT := /Library/Developer/CommandLineTools
ifeq ($(shell xcode-select -p),$(CLT))
CLT_DEV := $(CLT)/Library/Developer
TEST_FLAGS := \
	-Xswiftc -F -Xswiftc $(CLT_DEV)/Frameworks \
	-Xswiftc -plugin-path -Xswiftc $(CLT)/usr/lib/swift/host/plugins/testing \
	-Xlinker -F -Xlinker $(CLT_DEV)/Frameworks \
	-Xlinker -rpath -Xlinker $(CLT_DEV)/Frameworks \
	-Xlinker -rpath -Xlinker $(CLT_DEV)/usr/lib
endif

.PHONY: build test test-unit test-scenario lint check release install clean

build:
	swift build
	$(call bundle,$(shell swift build --show-bin-path),$(APP_ID).dev,Tyler (development),in-place)

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
	$(call release_bundle,$(shell swift build -c release --show-bin-path),$(APP_ID),Tyler,installed)

install: release
	mkdir -p $(PREFIX)
	cp .build/release/tyler .build/release/tylerd $(PREFIX)/
	rm -rf $(PREFIX)/Tyler.app
	cp -R .build/release/Tyler.app $(PREFIX)/
ifneq ($(SIGN_ID),)
	codesign --force --sign "$(SIGN_ID)" $(PREFIX)/tyler $(PREFIX)/tylerd
endif
	@echo "installed to $(PREFIX)"

clean:
	swift package clean
