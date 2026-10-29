LIBRARY_NAME = UDImages

OBJC_RUNTIME_LIB = ng
RUNTIME_VERSION = gnustep-2.0
GS_WITH_ARC = 1

include $(GNUSTEP_MAKEFILES)/common.make

UDLIBS_DIR = ..
include $(UDLIBS_DIR)/Libraries.make

UDImages_OBJC_FILES = \
    UDImageProgram.m

UDImages_INCLUDE_DIRS = $(call ud_own_includes,UDImages)

UDImages_HEADER_FILES_DIR = .
UDImages_HEADER_FILES = \
    UDImageProgram.h

ADDITIONAL_LIB_DIRS += $(call ud_own_lib_dirs,UDImages)
UDImages_LIBRARIES_DEPEND_UPON += $(call ud_own_libs,UDImages)

# Core Data on GNUstep is FreeCoreData.
ADDITIONAL_NATIVE_LIBS += CoreData

# idFileSystem and idLexer call CFString's functions (gnustep-corebase);
# the archives read zip (minizip) and write it (UDZipWriter) with zlib.
$(LIBRARY_NAME)_LIBRARIES_DEPEND_UPON += $(UD_SYSTEM_LIBS)

include $(GNUSTEP_MAKEFILES)/library.make
