LIBRARY_NAME = UDScripts

OBJC_RUNTIME_LIB = ng
RUNTIME_VERSION = gnustep-2.0
GS_WITH_ARC = 1

include $(GNUSTEP_MAKEFILES)/common.make

UDLIBS_DIR = ..
include $(UDLIBS_DIR)/Libraries.make

UDScripts_OBJC_FILES = \
    UDScriptDebuggerConnection.m \
    UDScriptEvents.m \
    UDScriptIndex.m \
    $(UD_SYSTEM_DIR)/UDDatagramSocket.m

UDScripts_INCLUDE_DIRS = $(call ud_own_includes,UDScripts)

UDScripts_HEADER_FILES_DIR = .
UDScripts_HEADER_FILES = \
    UDDatagramSocket.h \
    UDScriptDebuggerConnection.h \
    UDScriptEvents.h \
    UDScriptIndex.h

ADDITIONAL_LIB_DIRS += $(call ud_own_lib_dirs,UDScripts)
UDScripts_LIBRARIES_DEPEND_UPON += $(call ud_own_libs,UDScripts)
# UDScriptDebuggerConnection hears the game on a dispatch source.
UDScripts_LIBRARIES_DEPEND_UPON += -ldispatch $(UD_SOCKET_LIBS)

# Core Data on GNUstep is FreeCoreData.
ADDITIONAL_NATIVE_LIBS += CoreData

# idFileSystem and idLexer call CFString's functions (gnustep-corebase);
# the archives read zip (minizip) and write it (UDZipWriter) with zlib.
$(LIBRARY_NAME)_LIBRARIES_DEPEND_UPON += $(UD_SYSTEM_LIBS)

include $(GNUSTEP_MAKEFILES)/library.make
