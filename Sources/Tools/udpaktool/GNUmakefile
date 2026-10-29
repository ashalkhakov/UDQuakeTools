TOOL_NAME = udpaktool

OBJC_RUNTIME_LIB = ng
RUNTIME_VERSION = gnustep-2.0
GS_WITH_ARC = 1

include $(GNUSTEP_MAKEFILES)/common.make

UDLIBS_DIR = ../../Libraries
include $(UDLIBS_DIR)/Libraries.make

udpaktool_OBJC_FILES = main.m

udpaktool_INCLUDE_DIRS = \
    $(UDLIBS_INCLUDE_DIRS)

# the libraries's decl layer is Core Data, which on GNUstep is FreeCoreData; the
# library does not pull it in by itself, so whatever links the libraries links it.
ADDITIONAL_NATIVE_LIBS += CoreData

# the libraries from the tree, built first (the root GNUmakefile).
ADDITIONAL_LIB_DIRS += $(UDLIBS_LIB_DIRS)
udpaktool_TOOL_LIBS += $(UDLIBS_LIBS)

include $(GNUSTEP_MAKEFILES)/tool.make
