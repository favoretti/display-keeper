#!/bin/zsh
# Regenerate Resources/AppIcon.icns from scripts/render-icon.swift.
set -euo pipefail
cd ${0:A:h}/..
set_dir=$(mktemp -d)/AppIcon.iconset
mkdir -p $set_dir
for px in 16 32 128 256 512; do
  swift scripts/render-icon.swift $set_dir/icon_${px}x${px}.png $px
  swift scripts/render-icon.swift $set_dir/icon_${px}x${px}@2x.png $((px * 2))
done
iconutil -c icns $set_dir -o Resources/AppIcon.icns
swift scripts/render-icon.swift docs/icon.png 512
