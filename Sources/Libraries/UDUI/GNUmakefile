LIBRARY_NAME = UDUI

OBJC_RUNTIME_LIB = ng
RUNTIME_VERSION = gnustep-2.0
GS_WITH_ARC = 1

include $(GNUSTEP_MAKEFILES)/common.make

UDLIBS_DIR = ..
include $(UDLIBS_DIR)/Libraries.make

UDUI_OBJC_FILES = \
    idWinVar.m \
    idRegExp.m \
    idGuiScript.m \
    idWindow.m \
    idSimpleWindow.m \
    idDeviceContext.m \
    idUserInterface.m \
    idSliderWindow.m \
    idEditWindow.m \
    idChoiceWindow.m \
    idListWindow.m \
    idBindWindow.m \
    idFieldWindow.m \
    idMarkerWindow.m \
    idRenderWindow.m

UDUI_INCLUDE_DIRS = $(call ud_own_includes,UDUI)

UDUI_HEADER_FILES_DIR = .
UDUI_HEADER_FILES = \
    idWindowEditorWrapper.h \
    idWinVar.h \
    idRegExp.h \
    idGuiScript.h \
    idWindow.h \
    idDeviceContext.h \
    idUserInterface.h \
    idSliderWindow.h \
    idEditWindow.h \
    idChoiceWindow.h \
    idListWindow.h \
    idBindWindow.h \
    idFieldWindow.h \
    idMarkerWindow.h \
    idRenderWindow.h

ADDITIONAL_LIB_DIRS += $(call ud_own_lib_dirs,UDUI)
UDUI_LIBRARIES_DEPEND_UPON += $(call ud_own_libs,UDUI)

# Core Data on GNUstep is FreeCoreData.
ADDITIONAL_NATIVE_LIBS += CoreData

# idFileSystem and idLexer call CFString's functions (gnustep-corebase);
# the archives read zip (minizip) and write it (UDZipWriter) with zlib.
$(LIBRARY_NAME)_LIBRARIES_DEPEND_UPON += $(UD_SYSTEM_LIBS)

include $(GNUSTEP_MAKEFILES)/library.make
