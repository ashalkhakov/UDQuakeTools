# The libraries' unit tests, a bundle each (Tests/<library>), and
# LSPServerKit's; Quarry's are Tests/Quarry's, run on their own.
include $(GNUSTEP_MAKEFILES)/common.make

SUBPROJECTS = UDCommon UDArchives UDDecls UDUI UDGUIEditor UDScripts UDWorkspace LSPServerKit

include $(GNUSTEP_MAKEFILES)/aggregate.make

# Every bundle's, each to the end; failing if any failed.
.PHONY: run-tests
run-tests:
	@failed=; for b in $(SUBPROJECTS); do $(MAKE) -C $$b run-tests || failed="$$failed $$b"; done; \
	if [ -n "$$failed" ]; then echo "Failed:$$failed"; exit 1; fi
