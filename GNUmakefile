#
# UDQuakeTools on GNUstep: the libraries, the launcher, Quarry (with the
# scripts' language server, udscript-lsp, and debug adapter, udscript-dap),
# Pak Manager and udpaktool, and
# their tests.
#
#   make            the libraries, the apps, udpaktool and the test bundles
#   make check      the tests (under Xvfb when there is no display): the libraries',
#                   then Quarry's, which drive the app's own windows (and
#                   a retail Doom 3 when $UD_DOOM3_PATH names one)
#   make install    the libraries, the apps and udpaktool; not the test bundles
#
# On FreeCoreData installed (.github/pins.env's release).
#
ifeq ($(GNUSTEP_MAKEFILES),)
  $(error Set GNUSTEP_MAKEFILES (source GNUstep.sh).)
endif

include $(GNUSTEP_MAKEFILES)/common.make

PACKAGE_NAME = UDQuakeTools
SUBPROJECTS = Sources/Libraries Sources/LSPServerKit tree-sitter-idscript tree-sitter-iddecl Sources/Tools/udscript-lsp Sources/Tools/udscript-dap Sources/UDLauncher Sources/Quarry \
              Sources/PakManager Sources/Tools/udpaktool Tests Tests/Quarry

include $(GNUSTEP_MAKEFILES)/aggregate.make

XVFB = $(if $(DISPLAY),,$(shell command -v xvfb-run >/dev/null 2>&1 && echo xvfb-run -a))
check::
	$(XVFB) $(MAKE) -C Tests run-tests
	$(XVFB) $(MAKE) -C Tests/Quarry run-tests
