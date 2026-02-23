APP_NAME = Stats
BUILD_DIR = .build/release
APP_BUNDLE = $(APP_NAME).app
CONTENTS = $(APP_BUNDLE)/Contents
MACOS = $(CONTENTS)/MacOS
CODESIGN_IDENTITY ?= -

.PHONY: build bundle sign install clean

build:
	swift build -c release

bundle: build
	rm -rf $(APP_BUNDLE)
	mkdir -p $(MACOS)
	cp $(BUILD_DIR)/$(APP_NAME) $(MACOS)/$(APP_NAME)
	cp Sources/Stats/Info.plist $(CONTENTS)/Info.plist

sign: bundle
	codesign --force --options runtime --sign "$(CODESIGN_IDENTITY)" $(APP_BUNDLE)

install: sign
	rm -rf /Applications/$(APP_BUNDLE)
	cp -r $(APP_BUNDLE) /Applications/$(APP_BUNDLE)
	@echo "Installed to /Applications/$(APP_BUNDLE)"

clean:
	rm -rf $(APP_BUNDLE)
	swift package clean
