#!/bin/zsh
# Build a universal DisplayKeeper.app (and the CLI) into dist/.
# Signing: set SIGN_IDENTITY="Developer ID Application: …" or leave unset for ad-hoc.
# Notarizing: also set NOTARY_PROFILE to a `xcrun notarytool store-credentials` profile name.
set -euo pipefail
cd ${0:A:h}/..
version=${VERSION:-$(git describe --tags --always 2>/dev/null | sed 's/^v//' || echo 0.0.0)}
build=$(git rev-list --count HEAD 2>/dev/null || echo 1)

swift build -c release --arch arm64 --arch x86_64
bin=$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)

rm -rf dist && mkdir -p dist
app=dist/DisplayKeeper.app
mkdir -p $app/Contents/{MacOS,Resources}
cp $bin/DisplayKeeper $app/Contents/MacOS/
cp $bin/display-keeper $app/Contents/Resources/
sed -e "s/__VERSION__/$version/" -e "s/__BUILD__/$build/" Resources/Info.plist > $app/Contents/Info.plist

identity=${SIGN_IDENTITY:--}
codesign --force --options runtime --timestamp=none --sign "$identity" $app/Contents/Resources/display-keeper
codesign --force --options runtime --sign "$identity" $app

(cd dist && ditto -c -k --keepParent DisplayKeeper.app DisplayKeeper-$version.zip)

if [[ -n ${NOTARY_PROFILE:-} ]]; then
  xcrun notarytool submit dist/DisplayKeeper-$version.zip --keychain-profile $NOTARY_PROFILE --wait
  xcrun stapler staple $app
  rm dist/DisplayKeeper-$version.zip
  (cd dist && ditto -c -k --keepParent DisplayKeeper.app DisplayKeeper-$version.zip)
fi

shasum -a 256 dist/*.zip
