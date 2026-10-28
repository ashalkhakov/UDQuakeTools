LIBRARY_NAME = UDRenderer

OBJC_RUNTIME_LIB = ng
RUNTIME_VERSION = gnustep-2.0
GS_WITH_ARC = 1

include $(GNUSTEP_MAKEFILES)/common.make

UDLIBS_DIR = ..
include $(UDLIBS_DIR)/Libraries.make

UDRenderer_OBJC_FILES = \
    UDMD5Mesh.m \
    UDParticleModel.m \
    UDSoftwareRenderer.m \
    UDFXModel.m \
    UDARBProgram.m \
    idGuiModel.m

UDRenderer_INCLUDE_DIRS = $(call ud_own_includes,UDRenderer)

UDRenderer_HEADER_FILES_DIR = .
UDRenderer_HEADER_FILES = \
    UDMD5Mesh.h \
    UDParticleModel.h \
    UDSoftwareRenderer.h \
    UDFXModel.h \
    UDARBProgram.h \
    idGuiModel.h

ADDITIONAL_LIB_DIRS += $(call ud_own_lib_dirs,UDRenderer)
UDRenderer_LIBRARIES_DEPEND_UPON += $(call ud_own_libs,UDRenderer)

# Core Data on GNUstep is FreeCoreData.
ADDITIONAL_NATIVE_LIBS += CoreData

# idFileSystem and idLexer call CFString's functions (gnustep-corebase);
# the archives read zip (minizip) and write it (UDZipWriter) with zlib.
$(LIBRARY_NAME)_LIBRARIES_DEPEND_UPON += $(UD_SYSTEM_LIBS)

include $(GNUSTEP_MAKEFILES)/library.make
