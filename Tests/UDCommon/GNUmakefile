# UDCommon's unit tests.
BUNDLE_NAME = UDCommonTests

OBJC_RUNTIME_LIB = ng
RUNTIME_VERSION = gnustep-2.0
GS_WITH_ARC = 1

include $(GNUSTEP_MAKEFILES)/common.make

UDLIBS_DIR = ../../Sources/Libraries
include $(UDLIBS_DIR)/Libraries.make

UDCommonTests_OBJC_FILES = \
    idFileSystemTests.m \
    idDeclManagerTests.m \
    idDeclFileWriteTests.m \
    ../Support/UDZipFixture.m

UDCommonTests_INCLUDE_DIRS = \
    $(UDLIBS_INCLUDE_DIRS) \
    -I../Support

include ../UnitTests.make
