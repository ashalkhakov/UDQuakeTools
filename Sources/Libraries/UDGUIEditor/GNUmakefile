LIBRARY_NAME = UDGUIEditor

OBJC_RUNTIME_LIB = ng
RUNTIME_VERSION = gnustep-2.0
GS_WITH_ARC = 1

include $(GNUSTEP_MAKEFILES)/common.make

UDLIBS_DIR = ..
include $(UDLIBS_DIR)/Libraries.make

UDGUIEditor_OBJC_FILES = \
    rvGEWindowWrapper.m \
    rvGEWorkspace.m \
    rvGEOptions.m \
    rvGEModifier.m \
    rvGESelectionMgr.m \
    rvGETransformer.m \
    UDOverlay.m

UDGUIEditor_INCLUDE_DIRS = $(call ud_own_includes,UDGUIEditor)

UDGUIEditor_HEADER_FILES_DIR = .
UDGUIEditor_HEADER_FILES = \
    rvGEWindowWrapper.h \
    rvGEWorkspace.h \
    rvGEOptions.h \
    rvGEModifier.h \
    rvGESelectionMgr.h \
    rvGETransformer.h \
    UDOverlay.h

ADDITIONAL_LIB_DIRS += $(call ud_own_lib_dirs,UDGUIEditor)
UDGUIEditor_LIBRARIES_DEPEND_UPON += $(call ud_own_libs,UDGUIEditor)

# Core Data on GNUstep is FreeCoreData.
ADDITIONAL_NATIVE_LIBS += CoreData

# idFileSystem and idLexer call CFString's functions (gnustep-corebase);
# the archives read zip (minizip) and write it (UDZipWriter) with zlib.
ADDITIONAL_LDFLAGS += -ldispatch -lBlocksRuntime -lz -lgnustep-corebase

include $(GNUSTEP_MAKEFILES)/library.make
