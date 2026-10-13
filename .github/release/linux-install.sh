#!/bin/bash
# UDCore, the launcher and Decl Browser into the prefix's System domain,
# where gnustep-release-actions' appimage takes them from.
set -eo pipefail
# GNUstep.sh reads unset variables (ZSH_VERSION), so set -u comes after it.
. "$PREFIX/System/Library/Makefiles/GNUstep.sh"
set -u
make -C Sources/UDCore install GNUSTEP_INSTALLATION_DOMAIN=SYSTEM
for app in UDLauncher DeclBrowser; do
  make -C "Sources/$app" install GNUSTEP_INSTALLATION_DOMAIN=SYSTEM
done
