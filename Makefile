APP_NAME = Stats
APP_BUNDLE = $(APP_NAME).app
CODESIGN_IDENTITY ?= -
VERSION ?= 0.0.0
BUILD ?= $(shell git rev-list --count HEAD)

.PHONY: build bundle sign install dmg app-store clean

build:
	swift build -c release

# The same bundle as the release workflow's, in the repository root.
bundle:
	MARKETING=$(VERSION) BUILD=$(BUILD) scripts/build-app.sh .

sign: bundle
	codesign --force --options runtime --sign "$(CODESIGN_IDENTITY)" $(APP_BUNDLE)

install: sign
	rm -rf /Applications/$(APP_BUNDLE)
	cp -r $(APP_BUNDLE) /Applications/$(APP_BUNDLE)
	@echo "Installed to /Applications/$(APP_BUNDLE)"

# The installer image, as published with each release (unsigned here).
dmg: sign
	scripts/build-dmg.sh $(APP_BUNDLE) $(APP_NAME).dmg

# The sandboxed Mac App Store build, ad-hoc signed without the distribution
# certificates: scripts/build-app-store.sh, docs/app-store.md.
app-store:
	MARKETING=$(VERSION) BUILD=$(BUILD) scripts/build-app-store.sh

clean:
	rm -rf $(APP_BUNDLE) $(APP_NAME).dmg build
	swift package clean
