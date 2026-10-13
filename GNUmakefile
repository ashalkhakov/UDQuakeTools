#
# UDQuakeTools on GNUstep: UDCore, the launcher and Decl Browser, and their
# tests (PakManager, GuiEd and udpaktool build on their own: make -C there).
#
#   make            UDCore, UDLauncher, DeclBrowser and the test bundle
#   make check      the tests (under Xvfb when there is no display)
#   make install    UDCore and the two apps; not the test bundle
#
# On FreeCoreData installed (.github/pins.env's release).
#
ifeq ($(GNUSTEP_MAKEFILES),)
  $(error Set GNUSTEP_MAKEFILES (source GNUstep.sh).)
endif

include $(GNUSTEP_MAKEFILES)/common.make

PACKAGE_NAME = UDQuakeTools
SUBPROJECTS = Sources/UDCore Sources/UDLauncher Sources/DeclBrowser Tests

include $(GNUSTEP_MAKEFILES)/aggregate.make

XVFB = $(if $(DISPLAY),,$(shell command -v xvfb-run >/dev/null 2>&1 && echo xvfb-run -a))
check::
	$(XVFB) $(MAKE) -C Tests run-tests
