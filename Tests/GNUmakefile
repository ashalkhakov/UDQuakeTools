BUNDLE_NAME = UDQuakeToolsTests

OBJC_RUNTIME_LIB = ng
RUNTIME_VERSION = gnustep-2.0
GS_WITH_ARC = 1

include $(GNUSTEP_MAKEFILES)/common.make

UDQuakeToolsTests_OBJC_FILES = \
    UDArchiveEntryTests.m \
    UDArchiveEditorTests.m \
    UDArchiveWorkflowTests.m \
    UDPAKCodecTests.m \
    UDPK3CodecTests.m \
    UDGameDetectionTests.m \
    idFileSystemTests.m \
    idDeclManagerTests.m \
    UDDeclIncrementalStoreTests.m

UDQuakeToolsTests_INCLUDE_DIRS = \
    -I../Sources/UDCore \
    -I../Sources/UDFormats

# The incremental-store tests need the compiled data model in the test
# bundle's resources (Xcode does the same for the Mac test target).
UDQuakeToolsTests_XCDATAMODELD_FILES = ../Sources/UDCore/DeclModel.xcdatamodeld

# CoreData is provided by FreeCoreData on GNUstep
# (https://github.com/ashalkhakov/FreeCoreData — install it before building).
ADDITIONAL_NATIVE_LIBS += CoreData

ADDITIONAL_LIB_DIRS += -L$(GNUSTEP_SYSTEM_LIBRARIES)
ADDITIONAL_LDFLAGS += -lUDCore -lzip -lXCTest -lBlocksRuntime

XCTEST ?= xctest

.PHONY: run-tests
run-tests: all $(BUNDLE_NAME).bundle
	@echo "Running XCTest bundle: $(BUNDLE_NAME)"
	. $(GNUSTEP_MAKEFILES)/GNUstep.sh; \
	$(XCTEST) "$(BUNDLE_NAME).bundle"

# Compiles $(UDQuakeToolsTests_XCDATAMODELD_FILES) with momc and bundles
# the .momd; installed into $(GNUSTEP_MAKEFILES) by FreeCoreData. Included
# after the run-tests rule so run-tests stays the default goal.
include $(GNUSTEP_MAKEFILES)/coredata-model.make

include $(GNUSTEP_MAKEFILES)/bundle.make

