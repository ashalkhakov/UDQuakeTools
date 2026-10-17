APP_NAME = PakManager

OBJC_RUNTIME_LIB = ng
RUNTIME_VERSION = gnustep-2.0
GS_WITH_ARC = 1
PakManager_APPLICATION_ICON = PakManager.png

include $(GNUSTEP_MAKEFILES)/common.make

UDLIBS_DIR = ../Libraries
include $(UDLIBS_DIR)/Libraries.make

PakManager_OBJC_FILES = \
    ../UDUpdater/UDUpdater.m \
    main.m \
    UDAppDelegate.m \
    UDArchiveDocument.m \
    UDArchiveBrowserController.m \
    UDTextPreviewController.m \
    UDFileActionService.m

PakManager_INCLUDE_DIRS = \
    -I../UDUpdater \
    $(UDLIBS_INCLUDE_DIRS)

PakManager_RESOURCE_FILES = \
    MainMenu.xib \
    UDArchiveDocument.xib \
    PakManager.png \
    PakManager-Info.plist

# the libraries's decl layer is Core Data, which on GNUstep is FreeCoreData; the
# library does not pull it in by itself, so whatever links the libraries links it.
ADDITIONAL_NATIVE_LIBS += CoreData

# the libraries from the tree beside this one, built first (the root GNUmakefile).
ADDITIONAL_LIB_DIRS += $(UDLIBS_LIB_DIRS)
ADDITIONAL_LDFLAGS += $(UDLIBS_LIBS) -ldispatch -lBlocksRuntime

include $(GNUSTEP_MAKEFILES)/application.make
