LIBRARY_NAME = UDIdLib

OBJC_RUNTIME_LIB = ng
RUNTIME_VERSION = gnustep-2.0
GS_WITH_ARC = 1

include $(GNUSTEP_MAKEFILES)/common.make

UDLIBS_DIR = ..
include $(UDLIBS_DIR)/Libraries.make

UDIdLib_OBJC_FILES = \
    idToken.m \
    idLexer.m \
    idParser.m \
    compat.m \
    idStr.m \
    MD5.m \
    UDBitMsg.m \
    UDSourceTokens.m \
    idMath.m \
    idDict.m \
    idStrPool.m \
    idLangDict.m

UDIdLib_INCLUDE_DIRS = $(call ud_own_includes,UDIdLib)

UDIdLib_HEADER_FILES_DIR = .
UDIdLib_HEADER_FILES = \
    idToken.h \
    idLexer.h \
    idParser.h \
    idStr.h \
    idFileAccess.h \
    MD5.h \
    UDSourceTokens.h \
    idMath.h \
    idDict.h \
    idStrPool.h \
    idLangDict.h

ADDITIONAL_LIB_DIRS += $(call ud_own_lib_dirs,UDIdLib)
UDIdLib_LIBRARIES_DEPEND_UPON += $(call ud_own_libs,UDIdLib)

# idFileSystem and idLexer call CFString's functions (gnustep-corebase);
# the archives read zip (minizip) and write it (UDZipWriter) with zlib.
ADDITIONAL_LDFLAGS += -ldispatch -lBlocksRuntime -lz -lgnustep-corebase

include $(GNUSTEP_MAKEFILES)/library.make
