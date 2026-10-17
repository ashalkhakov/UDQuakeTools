# UDUI's unit tests.
BUNDLE_NAME = UDUITests

OBJC_RUNTIME_LIB = ng
RUNTIME_VERSION = gnustep-2.0
GS_WITH_ARC = 1

include $(GNUSTEP_MAKEFILES)/common.make

UDLIBS_DIR = ../../Sources/Libraries
include $(UDLIBS_DIR)/Libraries.make

UDUITests_OBJC_FILES = \
    idUserInterfaceTests.m

UDUITests_INCLUDE_DIRS = \
    $(UDLIBS_INCLUDE_DIRS)

include ../UnitTests.make
