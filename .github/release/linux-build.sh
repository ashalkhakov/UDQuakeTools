#!/bin/bash
# FreeCoreData (beside this repository: the framework and momc), UDCore and
# the apps, on the stack in $PREFIX, passing their tests.
set -eo pipefail
# GNUstep.sh reads unset variables (ZSH_VERSION), so set -u comes after it.
. "$PREFIX/System/Library/Makefiles/GNUstep.sh"
set -u
(cd ../FreeCoreData
 make -j"$(nproc)" && make install
 make -C Tools/momc && make -C Tools/momc install)
make -C Sources/UDCore -j"$(nproc)" && make -C Sources/UDCore install
for app in UDLauncher DeclBrowser; do
  make -C "Sources/$app" -j"$(nproc)"
done
xvfb-run -a make -C Tests run-tests
