#!/usr/bin/env bash
#
# Rebuilds the README animation and the pub.dev screenshot from the widget.
#
#   bash tool/build_media.sh
#
# Needs ImageMagick and gifski:  brew install imagemagick gifski
set -euo pipefail

package_dir="$(cd "$(dirname "$0")/.." && pwd)"
cd "$package_dir"

media="build/media"
rm -rf "$media"
flutter test tool/render_media.dart

# Frames come out at 2x so the downscale can do the antialiasing, which keeps
# the caps smooth once the palette drops to 256 colours.
mkdir -p "$media/small"
for frame in "$media"/frames/*.png; do
  magick "$frame" -filter Lanczos -resize 320x320 -strip \
    "$media/small/$(basename "$frame")"
done

mkdir -p doc screenshots
gifski --fps 20 --quality 90 --width 320 \
  --output doc/woven_ring_chart.gif "$media"/small/*.png
cp "$media/screenshot.png" screenshots/woven_ring_chart.png

ls -lh doc/woven_ring_chart.gif screenshots/woven_ring_chart.png
