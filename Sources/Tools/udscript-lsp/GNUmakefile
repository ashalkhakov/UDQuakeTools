TOOL_NAME = udscript-lsp

OBJC_RUNTIME_LIB = ng
RUNTIME_VERSION = gnustep-2.0
GS_WITH_ARC = 1

include $(GNUSTEP_MAKEFILES)/common.make

udscript-lsp_OBJC_FILES = main.m

udscript-lsp_INCLUDE_DIRS = -I../../UDCore

# It ships in Decl Browser, beside its executable (Decl Browser's
# GNUmakefile copies it there), not on its own.
STANDARD_INSTALL = no

# UDCore's decl layer is Core Data, which on GNUstep is FreeCoreData; the
# library does not pull it in by itself, so whatever links UDCore links it.
ADDITIONAL_NATIVE_LIBS += CoreData

# UDCore from the tree, built first (the root GNUmakefile).
ADDITIONAL_LIB_DIRS += -L../../UDCore/$(GNUSTEP_OBJ_DIR_NAME)
ADDITIONAL_LDFLAGS += -lUDCore

include $(GNUSTEP_MAKEFILES)/tool.make
