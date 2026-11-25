# Expenses: owner-only macOS app. SwiftPM builds the binaries; `just app` wraps them into
# dist/Expenses.app with the widget inside (no Xcode project, Batteries' recipe).

sign_id := env("CODESIGN_ID", "Developer ID Application: Andrey Kim (73R36N2A46)")
# The parser the app runs: expenses-capture's parse.js, the same file the phone and `just reparse` run.
capture := env("EXPENSES_CAPTURE", "../expenses-capture")
notarize_profile := env("NOTARIZE_PROFILE", "Notarize")
app := "dist/Expenses.app"
appex := app + "/Contents/PlugIns/ExpensesWidget.appex"

# Build the core library, the app and the widget binaries (debug)
build:
  swift build

# Build and sign dist/Expenses.app with the widget and parse.js inside. Installs and launches nothing.
app:
  #!/usr/bin/env bash
  set -euo pipefail
  test -f "{{capture}}/parse.js" || { echo "no {{capture}}/parse.js: build from the expenses workspace, or set EXPENSES_CAPTURE"; exit 1; }
  swift build -c release
  bin=$(swift build -c release --show-bin-path)
  rm -rf "{{app}}"
  mkdir -p "{{app}}/Contents/MacOS" "{{app}}/Contents/Resources" "{{appex}}/Contents/MacOS"
  cp "$bin/ExpensesApp" "{{app}}/Contents/MacOS/Expenses"
  cp "$bin/ExpensesWidget" "{{appex}}/Contents/MacOS/ExpensesWidget"
  cp "{{capture}}/parse.js" "{{app}}/Contents/Resources/parse.js"
  cp App/Info.plist "{{app}}/Contents/Info.plist"
  # Assets.car (CFBundleIconName, what newer macOS reads) plus AppIcon.icns for older readers
  xcrun actool App/Assets.xcassets --compile "{{app}}/Contents/Resources" --platform macosx \
    --minimum-deployment-target 15.0 --app-icon AppIcon --output-partial-info-plist /dev/null >/dev/null
  cp Widget/Info.plist "{{appex}}/Contents/Info.plist"
  version=$(cat VERSION)
  build=$(date +%y%m%d%H%M)
  for plist in "{{app}}/Contents/Info.plist" "{{appex}}/Contents/Info.plist"; do
    plutil -replace CFBundleShortVersionString -string "$version" "$plist"
    plutil -replace CFBundleVersion -string "$build" "$plist"
  done
  # Inside out: the extension first, then the app that seals it.
  ts="--timestamp=none"; [ "${RELEASE:-0}" = 1 ] && ts="--timestamp"
  codesign --force "$ts" -o runtime --entitlements Widget/Widget.entitlements --sign "{{sign_id}}" "{{appex}}"
  codesign --force "$ts" -o runtime --entitlements App/Expenses.entitlements --sign "{{sign_id}}" "{{app}}"
  codesign --verify --deep --strict "{{app}}"
  echo "Built {{app}} v$version"

# Owner only: quits a running copy, replaces /Applications/Expenses.app and registers its widget.
# Launching it stays a separate step: `open /Applications/Expenses.app`.
install: app
  pkill -x Expenses || true
  # A widget process from the old build keeps reporting the old version, and WidgetKit then rejects
  # every snapshot ("Bundle version did not match"). macOS relaunches it from the new build.
  pkill -x ExpensesWidget || true
  rm -rf /Applications/Expenses.app
  ditto "{{app}}" /Applications/Expenses.app
  # An app never opened is unknown to LaunchServices, and the widget gallery ignores its extension.
  /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f -R /Applications/Expenses.app
  pluginkit -a /Applications/Expenses.app/Contents/PlugIns/ExpensesWidget.appex

# Release, as Batteries and LidGuard do: bump VERSION (BUMP=patch|minor|major), build with a secure
# timestamp, notarize and staple, commit, tag, push, publish a GitHub release with the zip. Needs
# RELEASE_NOTES.md. The installed app finds it there (Updater: every 12 h, offers it, never silent).
release:
  #!/usr/bin/env bash
  set -euo pipefail
  test -f RELEASE_NOTES.md || { echo "Error: RELEASE_NOTES.md is required. Write release notes first."; exit 1; }
  test -z "$(git status --porcelain -- . ':!RELEASE_NOTES.md')" || { echo "Error: commit your changes first."; exit 1; }
  IFS=. read -r major minor patch < VERSION
  case "${BUMP:-patch}" in
    major) version="$((major + 1)).0.0" ;;
    minor) version="$major.$((minor + 1)).0" ;;
    *) version="$major.$minor.$((patch + 1))" ;;
  esac
  echo "$version" > VERSION
  RELEASE=1 just app
  ditto -c -k --keepParent "{{app}}" dist/notarize.zip
  xcrun notarytool submit dist/notarize.zip --keychain-profile "{{notarize_profile}}" --wait
  xcrun stapler staple "{{app}}"
  rm -f dist/notarize.zip
  zip="dist/Expenses-$version.zip"
  ditto -c -k --keepParent "{{app}}" "$zip"
  git add VERSION
  git commit -m "chore: bump version to $version"
  git tag "v$version"
  git push origin main --tags
  gh release create "v$version" "$zip" --repo Erel3/expenses --title "v$version" --notes-file RELEASE_NOTES.md
  rm -f RELEASE_NOTES.md
  echo "Released v$version"

# Redraw the app icon set (Scripts/generate_icon.swift); `just icon preview.png` also writes a 1024 px PNG
icon *preview:
  swift Scripts/generate_icon.swift {{preview}}

# Unit and render tests. `EXPENSES_RENDER_DIR=/dir just test` also writes the rendered PNGs.
test:
  swift test

lint:
  swiftlint --strict

clean:
  rm -rf .build dist

# ── iPhone ───────────────────────────────────────────────────────────

# Generate iOS/Expenses.xcodeproj from iOS/project.yml (XcodeGen; the project is not committed)
ios-project:
  cd iOS && xcodegen generate --quiet

# The paired iPhone's id, read from devicectl, never hardcoded. Its state reads "available (paired)"
# or "connected (no DDI)" (no developer disk image yet: xcodebuild mounts it); never "unavailable".
_iphone:
  @xcrun devicectl list devices 2>/dev/null | awk '/iPhone/ && /physical/ && !/unavailable/ { for (i = 1; i <= NF; i++) if ($i ~ /^[0-9A-F]{8}-[0-9A-F]{16}$/) print $i; exit }'

# Build an Ad Hoc .ipa for the registered iPhone: archive, then export signed for "release-testing".
# Ad Hoc runs without Developer Mode (a development build would not open with it off), one year per
# profile, never published. The first run registers the paired iPhone in the team (it has to be
# connected and unlocked then) and creates the profiles; later runs need no device at all.
ios-build: ios-project
  #!/usr/bin/env bash
  set -euo pipefail
  test -f "{{capture}}/parse.js" || { echo "no {{capture}}/parse.js: build from the expenses workspace"; exit 1; }
  rm -rf .build/ios/Expenses.xcarchive .build/ios/export
  xcodebuild -project iOS/Expenses.xcodeproj -scheme ExpensesPhone -configuration Release \
    -destination 'generic/platform=iOS' -derivedDataPath .build/ios -archivePath .build/ios/Expenses.xcarchive \
    -allowProvisioningUpdates -allowProvisioningDeviceRegistration archive | tail -2
  xcodebuild -exportArchive -archivePath .build/ios/Expenses.xcarchive -exportOptionsPlist iOS/ExportOptions.plist \
    -exportPath .build/ios/export -allowProvisioningUpdates | tail -2
  ls .build/ios/export/*.ipa

# Owner only: install the last ios-build on the paired iPhone (connected, unlocked)
ios-install:
  #!/usr/bin/env bash
  set -euo pipefail
  device=$(just _iphone)
  test -n "$device" || { echo "no connected iPhone (xcrun devicectl list devices)"; exit 1; }
  xcrun devicectl device install app --device "$device" .build/ios/export/Expenses.ipa | tail -2

# Simulator build, unsigned: checks the iPhone target compiles without a certificate
ios-check: ios-project
  xcodebuild -project iOS/Expenses.xcodeproj -scheme ExpensesPhone -destination 'generic/platform=iOS Simulator' \
    -derivedDataPath .build/ios CODE_SIGNING_ALLOWED=NO build | tail -1
