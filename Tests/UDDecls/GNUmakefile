# UDDecls's unit tests.
BUNDLE_NAME = UDDeclsTests

OBJC_RUNTIME_LIB = ng
RUNTIME_VERSION = gnustep-2.0
GS_WITH_ARC = 1

include $(GNUSTEP_MAKEFILES)/common.make

UDLIBS_DIR = ../../Sources/Libraries
include $(UDLIBS_DIR)/Libraries.make

UDDeclsTests_OBJC_FILES = \
    UDDeclCodecTests.m \
    UDDeclTextCheckerTests.m \
    UDDeclIncrementalStoreTests.m

UDDeclsTests_INCLUDE_DIRS = \
    $(UDLIBS_INCLUDE_DIRS)

include ../UnitTests.make
