APP_NAME = PakManager

OBJC_RUNTIME_LIB = ng
RUNTIME_VERSION = gnustep-2.0
GS_WITH_ARC = 1
PakManager_APPLICATION_ICON = PakManager.png

include $(GNUSTEP_MAKEFILES)/common.make

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
    -I../UDCore \
    -I../UDFormats

PakManager_RESOURCE_FILES = \
    MainMenu.xib \
    UDArchiveDocument.xib \
    PakManager.png \
    PakManager-Info.plist

# UDCore's decl layer is Core Data, which on GNUstep is FreeCoreData; the
# library does not pull it in by itself, so whatever links UDCore links it.
ADDITIONAL_NATIVE_LIBS += CoreData

# UDCore from the tree beside this one, built first (the root GNUmakefile).
ADDITIONAL_LIB_DIRS += -L../UDCore/$(GNUSTEP_OBJ_DIR_NAME)
ADDITIONAL_LDFLAGS += -lUDCore -ldispatch -lBlocksRuntime

include $(GNUSTEP_MAKEFILES)/application.make
