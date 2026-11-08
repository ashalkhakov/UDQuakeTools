#
# UDQuakeTools on GNUstep: the libraries, the tools (udscript-lsp,
# udscript-dap, udpaktool), UDCode's UDQuakeTools extension
# (Sources/Quarry: Quarry and Pak Manager in UDCode, docs/UDCODE.md), and
# their tests.
#
#   make            the libraries, the tools, the extension and the test bundles
#   make check      the tests (under Xvfb when there is no display): the
#                   libraries', the extension's, then Quarry's editors' (a
#                   retail Doom 3's cases when $UD_DOOM3_PATH names one)
#   make install    the libraries and the tools; the extension is packaged
#                   (Scripts/udcx.sh), not installed
#
# On the GNUstep stack (with its Core Data) and UDCode's SDK (.github/pins.env).
#
ifeq ($(GNUSTEP_MAKEFILES),)
  $(error Set GNUSTEP_MAKEFILES (source GNUstep.sh).)
endif

include $(GNUSTEP_MAKEFILES)/common.make

PACKAGE_NAME = UDQuakeTools
SUBPROJECTS = Sources/Libraries Sources/LSPServerKit Sources/Tools/udscript-lsp Sources/Tools/udscript-dap Sources/Tools/udpaktool \
              Sources/Quarry Tests Tests/Extension Tests/Quarry

include $(GNUSTEP_MAKEFILES)/aggregate.make

XVFB = $(if $(DISPLAY),,$(shell command -v xvfb-run >/dev/null 2>&1 && echo xvfb-run -a))
check::
	$(XVFB) $(MAKE) -C Tests run-tests
	$(XVFB) $(MAKE) -C Tests/Extension run-tests
	$(XVFB) $(MAKE) -C Tests/Quarry run-tests
