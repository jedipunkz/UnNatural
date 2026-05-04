PROJECT := UnNatural.xcodeproj
SCHEME := UnNatural
CONFIGURATION := Debug
DERIVED_DATA := .DerivedData
APP_NAME := UnNatural.app
BUILT_APP := $(DERIVED_DATA)/Build/Products/$(CONFIGURATION)/$(APP_NAME)
INSTALL_DIR := /Applications
INSTALLED_APP := $(INSTALL_DIR)/$(APP_NAME)

.PHONY: build install open clean uninstall reinstall

build:
	xcodebuild \
		-project $(PROJECT) \
		-scheme $(SCHEME) \
		-configuration $(CONFIGURATION) \
		-derivedDataPath $(DERIVED_DATA) \
		CODE_SIGNING_ALLOWED=NO \
		build

install: build
	ditto "$(BUILT_APP)" "$(INSTALLED_APP)"

open: install
	open "$(INSTALLED_APP)"

uninstall:
	rm -rf "$(INSTALLED_APP)"

reinstall: uninstall install

clean:
	xcodebuild \
		-project $(PROJECT) \
		-scheme $(SCHEME) \
		-configuration $(CONFIGURATION) \
		-derivedDataPath $(DERIVED_DATA) \
		clean
