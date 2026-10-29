LIBRARY_NAME = UDDecls

OBJC_RUNTIME_LIB = ng
RUNTIME_VERSION = gnustep-2.0
GS_WITH_ARC = 1

include $(GNUSTEP_MAKEFILES)/common.make

UDLIBS_DIR = ..
include $(UDLIBS_DIR)/Libraries.make

UDDecls_OBJC_FILES = \
    UDDeclCodec.m \
    UDDeclBase.m \
    UDDeclRawText.m \
    UDDeclElement.m \
    UDDeclTable.m \
    UDDeclSkin.m \
    UDDeclEntityDef.m \
    UDDeclSound.m \
    UDDeclFX.m \
    UDDeclAF.m \
    UDDeclMaterial.m \
    UDMaterialParser.m \
    UDDeclPDA.m \
    UDDeclParticle.m \
    UDDeclIncrementalStore.m \
    UDDeclTextChecker.m

UDDecls_INCLUDE_DIRS = $(call ud_own_includes,UDDecls)

UDDecls_HEADER_FILES_DIR = .
UDDecls_HEADER_FILES = \
    UDDeclManagedObjects.h \
    UDDeclBase.h \
    UDDeclRawText.h \
    UDDeclElement.h \
    UDDeclTable.h \
    UDDeclSkin.h \
    UDDeclEntityDef.h \
    UDDeclSound.h \
    UDDeclFX.h \
    UDDeclAF.h \
    UDDeclMaterial.h \
    UDMaterialParser.h \
    UDDeclPDA.h \
    UDDeclParticle.h \
    UDDeclIncrementalStore.h \
    UDDeclTextChecker.h

ADDITIONAL_LIB_DIRS += $(call ud_own_lib_dirs,UDDecls)
UDDecls_LIBRARIES_DEPEND_UPON += $(call ud_own_libs,UDDecls)

# Core Data on GNUstep is FreeCoreData.
ADDITIONAL_NATIVE_LIBS += CoreData

# idFileSystem and idLexer call CFString's functions (gnustep-corebase);
# the archives read zip (minizip) and write it (UDZipWriter) with zlib.
$(LIBRARY_NAME)_LIBRARIES_DEPEND_UPON += $(UD_SYSTEM_LIBS)

include $(GNUSTEP_MAKEFILES)/library.make
