TOOL_NAME = udscript-lsp

OBJC_RUNTIME_LIB = ng
RUNTIME_VERSION = gnustep-2.0
GS_WITH_ARC = 1

include $(GNUSTEP_MAKEFILES)/common.make

UDLIBS_DIR = ../../Libraries
include $(UDLIBS_DIR)/Libraries.make

udscript-lsp_OBJC_FILES = main.m UDScriptLanguageServer.m

udscript-lsp_INCLUDE_DIRS = $(UDLIBS_INCLUDE_DIRS) -I../../LSPServerKit

# It ships in Quarry, beside its executable (Quarry's
# GNUmakefile copies it there), not on its own.
STANDARD_INSTALL = no

# the libraries's decl layer is Core Data, which on GNUstep is FreeCoreData; the
# library does not pull it in by itself, so whatever links the libraries links it.
ADDITIONAL_NATIVE_LIBS += CoreData

# the libraries and LSPServerKit from the tree, built first (the root GNUmakefile).
ADDITIONAL_LIB_DIRS += $(UDLIBS_LIB_DIRS) -L../../LSPServerKit/$(GNUSTEP_OBJ_DIR_NAME)
ADDITIONAL_LDFLAGS += $(UDLIBS_LIBS) -lLSPServerKit

include $(GNUSTEP_MAKEFILES)/tool.make
