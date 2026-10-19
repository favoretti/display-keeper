#!/bin/zsh
# Build a universal DisplayKeeper.app (and the CLI) into dist/.
# Signing: set SIGN_IDENTITY="Developer ID Application: …" or leave unset for ad-hoc.
# Notarizing: also set NOTARY_PROFILE to a `xcrun notarytool store-credentials` profile name
# (and NOTARY_KEYCHAIN if that profile is not in the default keychain).
set -euo pipefail
cd ${0:A:h}/..
version=${VERSION:-$(git describe --tags --always 2>/dev/null | sed 's/^v//' || echo 0.0.0)}
build=$(git rev-list --count HEAD 2>/dev/null || echo 1)

swift build -c release --arch arm64 --arch x86_64
bin=$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)

rm -rf dist && mkdir -p dist
app=dist/DisplayKeeper.app
mkdir -p $app/Contents/{MacOS,Resources,Frameworks}
cp $bin/DisplayKeeper $app/Contents/MacOS/
cp $bin/display-keeper $app/Contents/Resources/
cp Resources/AppIcon.icns $app/Contents/Resources/
ditto $bin/Sparkle.framework $app/Contents/Frameworks/Sparkle.framework
sed -e "s/__VERSION__/$version/" -e "s/__BUILD__/$build/" Resources/Info.plist > $app/Contents/Info.plist

identity=${SIGN_IDENTITY:--}
# Notarization requires a secure timestamp; ad-hoc signatures can't have one.
timestamp=(--timestamp)
[[ $identity == - ]] && timestamp=(--timestamp=none)
sign() { codesign --force --options runtime $timestamp --sign "$identity" "$@" }
# Inside out, as Sparkle documents for Developer ID; --deep would drop the Downloader's entitlements.
sparkle=$app/Contents/Frameworks/Sparkle.framework/Versions/B
sign $sparkle/XPCServices/Installer.xpc
sign --preserve-metadata=entitlements $sparkle/XPCServices/Downloader.xpc
sign $sparkle/Autoupdate
sign $sparkle/Updater.app
sign $app/Contents/Frameworks/Sparkle.framework
sign $app/Contents/Resources/display-keeper
sign $app

(cd dist && ditto -c -k --keepParent DisplayKeeper.app DisplayKeeper-$version.zip)

if [[ -n ${NOTARY_PROFILE:-} ]]; then
  xcrun notarytool submit dist/DisplayKeeper-$version.zip --keychain-profile $NOTARY_PROFILE \
    ${NOTARY_KEYCHAIN:+--keychain $NOTARY_KEYCHAIN} --wait
  xcrun stapler staple $app
  rm dist/DisplayKeeper-$version.zip
  (cd dist && ditto -c -k --keepParent DisplayKeeper.app DisplayKeeper-$version.zip)
fi

shasum -a 256 dist/*.zip
