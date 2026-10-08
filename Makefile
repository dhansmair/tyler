PREFIX ?= $(HOME)/.local/bin
# Optional code-signing identity, e.g. `make install SIGN_ID=mwm-dev`.
SIGN_ID ?=

# The Command Line Tools ship Swift Testing, but SwiftPM doesn't search for it there.
# Harmless when full Xcode is installed.
CLT_DEV := /Library/Developer/CommandLineTools/Library/Developer
TEST_FLAGS := \
	-Xswiftc -F -Xswiftc $(CLT_DEV)/Frameworks \
	-Xlinker -F -Xlinker $(CLT_DEV)/Frameworks \
	-Xlinker -rpath -Xlinker $(CLT_DEV)/Frameworks \
	-Xlinker -rpath -Xlinker $(CLT_DEV)/usr/lib

.PHONY: build test release install clean

build:
	swift build

test:
	swift test $(TEST_FLAGS)

release:
	swift build -c release

install: release
	mkdir -p $(PREFIX)
	cp .build/release/mwm .build/release/mwmd $(PREFIX)/
ifneq ($(SIGN_ID),)
	codesign --force --sign "$(SIGN_ID)" $(PREFIX)/mwm $(PREFIX)/mwmd
endif
	@echo "installed to $(PREFIX)"

clean:
	swift package clean
