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

include $(GNUSTEP_MAKEFILES)/bundle.make

