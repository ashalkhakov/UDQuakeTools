#
# UDQuakeTools on GNUstep: UDCore, the launcher, Decl Browser (with the
# scripts' language server, udscript-lsp), Pak Manager and udpaktool, and
# their tests.
#
#   make            UDCore, the apps, udpaktool and the test bundles
#   make check      the tests (under Xvfb when there is no display): UDCore's,
#                   then Decl Browser's, which drive the app's own windows (and
#                   a retail Doom 3 when $UD_DOOM3_PATH names one)
#   make install    UDCore, the apps and udpaktool; not the test bundles
#
# On FreeCoreData installed (.github/pins.env's release).
#
ifeq ($(GNUSTEP_MAKEFILES),)
  $(error Set GNUSTEP_MAKEFILES (source GNUstep.sh).)
endif

include $(GNUSTEP_MAKEFILES)/common.make

PACKAGE_NAME = UDQuakeTools
SUBPROJECTS = Sources/UDCore Sources/LSPServerKit tree-sitter-idscript Sources/Tools/udscript-lsp Sources/UDLauncher Sources/DeclBrowser \
              Sources/PakManager Sources/Tools/udpaktool Tests Tests/DeclBrowser

include $(GNUSTEP_MAKEFILES)/aggregate.make

XVFB = $(if $(DISPLAY),,$(shell command -v xvfb-run >/dev/null 2>&1 && echo xvfb-run -a))
check::
	$(XVFB) $(MAKE) -C Tests run-tests
	$(XVFB) $(MAKE) -C Tests/DeclBrowser run-tests
