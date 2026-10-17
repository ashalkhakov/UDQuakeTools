# UDGUIEditor's unit tests.
BUNDLE_NAME = UDGUIEditorTests

OBJC_RUNTIME_LIB = ng
RUNTIME_VERSION = gnustep-2.0
GS_WITH_ARC = 1

include $(GNUSTEP_MAKEFILES)/common.make

UDLIBS_DIR = ../../Sources/Libraries
include $(UDLIBS_DIR)/Libraries.make

UDGUIEditorTests_OBJC_FILES = \
    rvGEWorkspaceTests.m

UDGUIEditorTests_INCLUDE_DIRS = \
    $(UDLIBS_INCLUDE_DIRS)

include ../UnitTests.make
