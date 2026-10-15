#!/bin/bash
# The AppImage on a clean Ubuntu, as gnustep-release-actions' appimage-test
# runs it (.github/release/appimage.conf, SMOKE_SCRIPT)
#   Scripts/appimage-smoke.sh <UDQuakeTools AppImage>
# Proof each app in the image starts and stays up, with its interface: the
# launcher, Decl Browser and Pak Manager, against a virtual display. An app whose nib
# failed to load stays up too, as an icon with no window; GNUstep says so on
# stderr, which is read back.
set -euo pipefail
image=$1
log=$(mktemp)
for app in "" declbrowser pakmanager; do
  timeout 90 xvfb-run -a "$image" $app > "$log" 2>&1 &
  pid=$!
  sleep 25
  if kill -0 $pid 2>/dev/null; then
    echo "${app:-launcher}: up after 25s"
    kill $pid 2>/dev/null || true
    wait $pid 2>/dev/null || true
  else
    status=0; wait $pid || status=$?
    cat "$log"
    echo "::error::${app:-launcher} exited on its own with status $status"
    exit 1
  fi
  if grep -qE "Failed to load Xib|could not load nib|failed to load MainMenu" "$log"; then
    cat "$log"
    echo "::error::${app:-launcher} started without its interface"
    exit 1
  fi
done
