.PHONY: build test app dmg package-dmg notarize submit-dmg-notarization release clean site-icons

APP_NAME   := ATEM ISO to FCPXML
APP_BUNDLE := build/$(APP_NAME).app
DMG_PATH   := build/ATEM-ISO-to-FCPXML.dmg
ARCHS      := --arch arm64 --arch x86_64
VERSION    := $(shell /usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Resources/Info.plist 2>/dev/null || echo "0.0.0")
# Created once with: xcrun notarytool store-credentials "$(NOTARY_PROFILE)" --key AuthKey.p8 --key-id ID --issuer UUID
NOTARY_PROFILE ?= atem-iso-to-fcpxml

build:
	swift build -c release $(ARCHS) --product ATEMISOtoFCPXML

test:
	swift test
	python3 -m unittest discover -s tests -v
	python3 scripts/build_quick_action.py --check

# Pass DEV_ID="Developer ID Application: ... (TEAMID)" for a notarization-ready bundle.
app: build
	bash scripts/make-app.sh "$(APP_BUNDLE)"

dmg: app package-dmg

package-dmg:
	@rm -f "$(DMG_PATH)"
	@mkdir -p build/dmg-staging && rm -rf build/dmg-staging/*
	@cp -R "$(APP_BUNDLE)" build/dmg-staging/
	@ln -sf /Applications build/dmg-staging/Applications
	hdiutil create -volname "$(APP_NAME) $(VERSION)" -srcfolder build/dmg-staging -ov -format UDZO "$(DMG_PATH)"
	@rm -rf build/dmg-staging
	@if [[ -n "$$DEV_ID" ]]; then codesign --force --sign "$$DEV_ID" --timestamp "$(DMG_PATH)"; fi
	@echo "==> Built $(DMG_PATH)"

notarize: app
	@[[ -n "$$DEV_ID" ]] || { echo "Error: set DEV_ID to a Developer ID Application identity." >&2; exit 1; }
	@rm -f build/notarize.zip
	ditto -c -k --keepParent "$(APP_BUNDLE)" build/notarize.zip
	xcrun notarytool submit build/notarize.zip --keychain-profile "$(NOTARY_PROFILE)" --wait
	xcrun stapler staple "$(APP_BUNDLE)"
	xcrun stapler validate "$(APP_BUNDLE)"
	spctl --assess --type execute --verbose=1 "$(APP_BUNDLE)"
	@rm -f build/notarize.zip

submit-dmg-notarization:
	xcrun notarytool submit "$(DMG_PATH)" --keychain-profile "$(NOTARY_PROFILE)" --wait
	xcrun stapler staple "$(DMG_PATH)"
	xcrun stapler validate "$(DMG_PATH)"

# Full pipeline: clean build, sign, notarize the app, package, notarize the disk image.
release: clean notarize
	$(MAKE) package-dmg
	$(MAKE) submit-dmg-notarization
	@echo "==> Release artifact: $(DMG_PATH)"

clean:
	@# Retry once: an indexer can hold a file in .build for a moment and make the first rm fail.
	rm -rf build .build || { sleep 2; rm -rf build .build; }

# Render the website's favicon and app-icon PNGs from the built app's icon, as macOS draws it, and refresh the social card.
site-icons: app
	/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$(APP_BUNDLE)"
	swift scripts/render-icon.swift "$(APP_BUNDLE)" docs/site
	swift scripts/build_social_card.swift
