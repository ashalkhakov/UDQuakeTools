# UQExtensionTests — UDCode's UDQuakeTools extension (Sources/Quarry,
# docs/UDCODE.md) against UDCode's SDK: its sources compiled in (their
# XIBs found in this bundle, as in UDQuakeTools.bundle), a Quarry project
# of a made-up game, its tree, its quarry: URLs read and saved.
#
#   xvfb-run -a make run-tests     (the root GNUmakefile's make check runs it too)

BUNDLE_NAME = UQExtensionTests
UQExtensionTests_STANDARD_INSTALL = no

OBJC_RUNTIME_LIB = ng
RUNTIME_VERSION = gnustep-2.0
GS_WITH_ARC = 1

include $(GNUSTEP_MAKEFILES)/common.make

UDLIBS_DIR = ../../Sources/Libraries
include $(UDLIBS_DIR)/Libraries.make
QUARRY_DIR = ../../Sources/Quarry
include $(QUARRY_DIR)/Quarry.include.make
include $(QUARRY_DIR)/files.make

UQExtensionTests_OBJC_FILES = \
    UQExtensionTests.m \
    $(addprefix $(QUARRY_DIR)/,$(QUARRY_OBJC_FILES))
UQExtensionTests_C_FILES = $(addprefix $(QUARRY_DIR)/,$(QUARRY_C_FILES))
UQExtensionTests_RESOURCE_FILES = $(addprefix $(QUARRY_DIR)/,$(QUARRY_RESOURCE_FILES))
UQExtensionTests_INCLUDE_DIRS = -I. $(QUARRY_INCLUDE_DIRS) $(UDLIBS_INCLUDE_DIRS)
UQExtensionTests_XCDATAMODELD_FILES = ../../Sources/Libraries/UDDecls/DeclModel.xcdatamodeld
UQExtensionTests_NEEDS_GUI = yes
ADDITIONAL_CFLAGS += -w

ADDITIONAL_LIB_DIRS += $(UDLIBS_LIB_DIRS)
UQExtensionTests_BUNDLE_LIBS += $(UDLIBS_LIBS) -lCoreData -lUDCodeKit -lUDPieceTable -lLSPKit -lXCTest -ldispatch $(UD_BLOCKS_LIBS)

XCTEST ?= xctest
TEST_TIMEOUT ?= 900

.PHONY: run-tests
run-tests: all $(BUNDLE_NAME).bundle
	. $(GNUSTEP_MAKEFILES)/GNUstep.sh; \
	LD_LIBRARY_PATH="$(UDLIBS_LD_PATH)$${LD_LIBRARY_PATH:+:$$LD_LIBRARY_PATH}" \
	PATH="$(UDLIBS_LD_PATH):$$PATH" \
	timeout -s ABRT $(TEST_TIMEOUT) $(XCTEST) "$(BUNDLE_NAME).bundle"

include $(GNUSTEP_MAKEFILES)/coredata-model.make

include $(GNUSTEP_MAKEFILES)/bundle.make
