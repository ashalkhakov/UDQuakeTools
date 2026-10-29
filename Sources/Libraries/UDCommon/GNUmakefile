LIBRARY_NAME = UDCommon

OBJC_RUNTIME_LIB = ng
RUNTIME_VERSION = gnustep-2.0
GS_WITH_ARC = 1

include $(GNUSTEP_MAKEFILES)/common.make

UDLIBS_DIR = ..
include $(UDLIBS_DIR)/Libraries.make

UDCommon_C_FILES = \
    unzip.c \
    ioapi.c

UDCommon_OBJC_FILES = \
    UDGame.m \
    idFile.m \
    idLangDict+Common.m \
    idFileSystem.m \
    idDeclManager.m \
    idCVarSystem.m

UDCommon_INCLUDE_DIRS = $(call ud_own_includes,UDCommon)

UDCommon_HEADER_FILES_DIR = .
UDCommon_HEADER_FILES = \
    UDGame.h \
    idFile.h \
    idLangDict+Common.h \
    UDEngineSettings.h \
    idFileSystem.h \
    idDeclManager.h \
    idCVarSystem.h

ADDITIONAL_LIB_DIRS += $(call ud_own_lib_dirs,UDCommon)
UDCommon_LIBRARIES_DEPEND_UPON += $(call ud_own_libs,UDCommon)

# Core Data on GNUstep is FreeCoreData.
ADDITIONAL_NATIVE_LIBS += CoreData

# idFileSystem and idLexer call CFString's functions (gnustep-corebase);
# the archives read zip (minizip) and write it (UDZipWriter) with zlib.
$(LIBRARY_NAME)_LIBRARIES_DEPEND_UPON += $(UD_SYSTEM_LIBS)

include $(GNUSTEP_MAKEFILES)/library.make
