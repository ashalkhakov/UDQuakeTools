# UDScripts's unit tests.
BUNDLE_NAME = UDScriptsTests

OBJC_RUNTIME_LIB = ng
RUNTIME_VERSION = gnustep-2.0
GS_WITH_ARC = 1

include $(GNUSTEP_MAKEFILES)/common.make

UDLIBS_DIR = ../../Sources/Libraries
include $(UDLIBS_DIR)/Libraries.make

UDScriptsTests_OBJC_FILES = \
    UDScriptDebuggerConnectionTests.m \
    UDScriptEventsTests.m \
    UDScriptIndexTests.m \
    ../Support/UDFakeScriptDebugger.m

UDScriptsTests_INCLUDE_DIRS = \
    $(UDLIBS_INCLUDE_DIRS) \
    -I../Support

# the debugger connection's tests wait on its dispatch queue
TESTS_LIBS = -ldispatch

include ../UnitTests.make
