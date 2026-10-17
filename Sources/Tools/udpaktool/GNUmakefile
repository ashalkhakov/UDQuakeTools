TOOL_NAME = udpaktool

OBJC_RUNTIME_LIB = ng
RUNTIME_VERSION = gnustep-2.0
GS_WITH_ARC = 1

include $(GNUSTEP_MAKEFILES)/common.make

UDCORE_DIR = ../../UDCore
include $(UDCORE_DIR)/UDCore.include.make

udpaktool_OBJC_FILES = main.m

udpaktool_INCLUDE_DIRS = \
    $(UDCORE_INCLUDE_DIRS) \
    -I../../UDFormats

# UDCore's decl layer is Core Data, which on GNUstep is FreeCoreData; the
# library does not pull it in by itself, so whatever links UDCore links it.
ADDITIONAL_NATIVE_LIBS += CoreData

# UDCore from the tree, built first (the root GNUmakefile).
ADDITIONAL_LIB_DIRS += -L../../UDCore/$(GNUSTEP_OBJ_DIR_NAME)
ADDITIONAL_LDFLAGS += -lUDCore

include $(GNUSTEP_MAKEFILES)/tool.make
