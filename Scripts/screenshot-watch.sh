#!/bin/bash
# Takes the pictures UDScreenshotTests asks for on macOS, where the test runner
# has no Screen Recording permission (a terminal given it can):
#   Scripts/screenshot-watch.sh <folder> &
#   TEST_RUNNER_UD_SCREENSHOTS=<folder> xcodebuild ... -only-testing:QuarryTests/UDScreenshotTests test
# For each <scene>.window the test writes (a window's number), the window alone,
# without its shadow, as quarry-<scene>-macos.png. Stops after 15 minutes.
set -u
folder=$1
end=$((SECONDS + 900))
while [ $SECONDS -lt $end ]; do
  for request in "$folder"/*.window; do
    [ -e "$request" ] || continue
    scene=$(basename "$request" .window)
    picture="$folder/quarry-$scene-macos.png"
    [ -e "$picture" ] && continue
    screencapture -o -x -l"$(cat "$request")" "$picture.tmp.png" && mv "$picture.tmp.png" "$picture"
  done
  sleep 0.5
done
