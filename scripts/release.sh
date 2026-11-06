#!/usr/bin/env bash
# Builds a signed, notarized Vaasi release into dist/: ZIP, DMG, PKG and a
# Sparkle appcast. Runs the same way on this Mac and in CI.
#
#   scripts/release.sh 0.1.3
#
# Environment:
#   ASC_KEY_PATH, ASC_KEY_ID, ASC_ISSUER_ID   App Store Connect API key for notarytool
#   SIGNING_KEYCHAIN                           keychain holding the Developer ID identities (CI)
#   SPARKLE_PRIVATE_KEY                        EdDSA key; without it the login keychain
#                                              account "vaasi" is used (local)
set -euo pipefail
cd "$(dirname "$0")/.."

version="${1:?usage: scripts/release.sh <major.minor.patch>}"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "Version must be major.minor.patch" >&2; exit 1; }
: "${ASC_KEY_PATH:?}" "${ASC_KEY_ID:?}" "${ASC_ISSUER_ID:?}"

team="LW385M78LW"
app_identity="Developer ID Application: Juge Praveen ($team)"
installer_identity="Developer ID Installer: Juge Praveen ($team)"
dist="dist"
derived="build/ReleaseDerivedData"
archive="$dist/Vaasi.xcarchive"
app="$dist/export/Vaasi.app"
name="Vaasi-$version"
keychain_flag=()
[[ -n "${SIGNING_KEYCHAIN:-}" ]] && keychain_flag=(--keychain "$SIGNING_KEYCHAIN")

if [[ -e "$dist" ]]; then
  if command -v trash >/dev/null; then trash "$dist"; else rm -rf "$dist"; fi
fi
mkdir -p "$dist"

notarize() {
  local file="$1" result status id
  echo "▸ Notarizing $(basename "$file")"
  result="$(xcrun notarytool submit "$file" --key "$ASC_KEY_PATH" --key-id "$ASC_KEY_ID" \
    --issuer "$ASC_ISSUER_ID" --wait --timeout 30m --output-format json)"
  status="$(python3 -I -c 'import json,sys; print(json.load(sys.stdin)["status"])' <<<"$result")"
  if [[ "$status" != "Accepted" ]]; then
    id="$(python3 -I -c 'import json,sys; print(json.load(sys.stdin)["id"])' <<<"$result")"
    xcrun notarytool log "$id" --key "$ASC_KEY_PATH" --key-id "$ASC_KEY_ID" --issuer "$ASC_ISSUER_ID" >&2 || true
    echo "Notarization of $file ended with status $status" >&2
    exit 1
  fi
}

echo "▸ Archiving $version (universal, Release)"
xcodebuild -project Vaasi.xcodeproj -scheme Vaasi -configuration Release \
  -destination 'generic/platform=macOS' -derivedDataPath "$derived" -archivePath "$archive" \
  MARKETING_VERSION="$version" CURRENT_PROJECT_VERSION="$version" \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="$app_identity" DEVELOPMENT_TEAM="$team" \
  OTHER_CODE_SIGN_FLAGS="--timestamp ${keychain_flag[*]+${keychain_flag[*]}}" \
  archive >"$dist/archive.log" 2>&1 || { tail -50 "$dist/archive.log"; exit 1; }

echo "▸ Exporting for Developer ID"
xcodebuild -exportArchive -archivePath "$archive" -exportPath "$dist/export" \
  -exportOptionsPlist scripts/ExportOptions.plist >"$dist/export.log" 2>&1 \
  || { tail -50 "$dist/export.log"; exit 1; }

echo "▸ Checking the app bundle"
codesign --verify --deep --strict --verbose=2 "$app"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")" == "$version" ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$app/Contents/Info.plist")" == "$version" ]]
archs="$(lipo -archs "$app/Contents/MacOS/Vaasi")"
[[ "$archs" == *arm64* && "$archs" == *x86_64* ]] || { echo "Expected a universal binary, got: $archs" >&2; exit 1; }
entitlements="$(codesign -d --entitlements - --xml "$app" 2>/dev/null)"
[[ "$entitlements" == *app-sandbox* ]] || { echo "App must be sandboxed" >&2; exit 1; }
[[ "$entitlements" != *get-task-allow* ]] || { echo "Release must not allow debugging" >&2; exit 1; }
[[ "$entitlements" != *network.client* && "$entitlements" != *network.server* ]] \
  || { echo "The app must not have network access; Sparkle downloads through its own service" >&2; exit 1; }
signature="$(codesign -d --verbose=2 "$app" 2>&1)"
[[ "$signature" == *"Authority=$app_identity"* ]] || { echo "Not signed with $app_identity" >&2; exit 1; }
[[ "$signature" == *"(runtime)"* ]] || { echo "Hardened runtime is off" >&2; exit 1; }

echo "▸ Notarizing the app"
ditto -c -k --sequesterRsrc --keepParent "$app" "$dist/notarize.zip"
notarize "$dist/notarize.zip"
xcrun stapler staple "$app"
xcrun stapler validate "$app"
spctl --assess --type execute --verbose "$app"
ditto -c -k --sequesterRsrc --keepParent "$app" "$dist/$name.zip"

echo "▸ Building the DMG"
staging="$(mktemp -d)"
ditto "$app" "$staging/Vaasi.app"
ln -s /Applications "$staging/Applications"
# hdiutil occasionally reports "Resource busy" on CI; retry a few times.
for attempt in 1 2 3; do
  hdiutil create -volname "Vaasi" -srcfolder "$staging" -ov -format UDZO "$dist/$name.dmg" >/dev/null && break
  [[ $attempt -eq 3 ]] && exit 1
  sleep 5
done
codesign --sign "$app_identity" --timestamp ${keychain_flag[@]+"${keychain_flag[@]}"} "$dist/$name.dmg"
notarize "$dist/$name.dmg"
xcrun stapler staple "$dist/$name.dmg"
xcrun stapler validate "$dist/$name.dmg"

echo "▸ Building the PKG"
pkg_root="$(mktemp -d)"
components="$(mktemp -d)/components.plist"
ditto "$app" "$pkg_root/Vaasi.app"
pkgbuild --analyze --root "$pkg_root" "$components" >/dev/null
/usr/libexec/PlistBuddy -c "Set :0:BundleIsRelocatable false" "$components"
pkgbuild --root "$pkg_root" --component-plist "$components" --identifier com.praveenjuge.vaasi \
  --install-location /Applications --version "$version" "$dist/unsigned.pkg" >/dev/null
productsign --sign "$installer_identity" ${keychain_flag[@]+"${keychain_flag[@]}"} "$dist/unsigned.pkg" "$dist/$name.pkg" >/dev/null
rm -f "$dist/unsigned.pkg"
[[ "$(pkgutil --check-signature "$dist/$name.pkg")" == *"Developer ID Installer"* ]]
notarize "$dist/$name.pkg"
xcrun stapler staple "$dist/$name.pkg"
xcrun stapler validate "$dist/$name.pkg"

echo "▸ Signing the update feed"
tools="$derived/SourcePackages/artifacts/sparkle/Sparkle/bin"
feed="$(mktemp -d)"
cp "$dist/$name.zip" "$feed/"
feed_args=(--maximum-versions 1 --maximum-deltas 0 \
  --download-url-prefix "https://github.com/praveenjuge/vaasi/releases/download/v$version/" -o "$dist/appcast.xml")
if [[ -n "${SPARKLE_PRIVATE_KEY:-}" ]]; then
  printf '%s' "$SPARKLE_PRIVATE_KEY" | "$tools/generate_appcast" --ed-key-file - "${feed_args[@]}" "$feed"
else
  "$tools/generate_appcast" --account vaasi "${feed_args[@]}" "$feed"
fi
python3 -I - "$version" "$dist/appcast.xml" <<'PY'
import sys, xml.etree.ElementTree as ET
version, path = sys.argv[1], sys.argv[2]
ns = {"s": "http://www.andymatuschak.org/xml-namespaces/sparkle"}
items = ET.parse(path).findall("./channel/item")
assert len(items) == 1, "feed must list exactly this release"
item = items[0]
assert item.findtext("s:version", namespaces=ns) == version
assert item.findtext("s:shortVersionString", namespaces=ns) == version
enclosure = item.find("enclosure")
assert enclosure.attrib["url"] == f"https://github.com/praveenjuge/vaasi/releases/download/v{version}/Vaasi-{version}.zip"
assert enclosure.attrib["{%s}edSignature" % ns["s"]]
assert int(enclosure.attrib["length"]) > 0
print("appcast ok")
PY

rm -f "$dist/notarize.zip"
echo "▸ Done"
ls -lh "$dist/$name.zip" "$dist/$name.dmg" "$dist/$name.pkg" "$dist/appcast.xml"
