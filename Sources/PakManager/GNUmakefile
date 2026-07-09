APP_NAME = PakManager

OBJC_RUNTIME_LIB = ng
RUNTIME_VERSION = gnustep-2.0
GS_WITH_ARC = 1
PakManager_APPLICATION_ICON = PakManager.png

include $(GNUSTEP_MAKEFILES)/common.make

PakManager_OBJC_FILES = \
    main.m \
    UDAppDelegate.m \
    UDArchiveDocument.m \
    UDArchiveBrowserController.m \
    UDTextPreviewController.m \
    UDFileActionService.m

PakManager_INCLUDE_DIRS = \
    -I../UDCore \
    -I../UDFormats

PakManager_LIBRARIES = UDCore

PakManager_RESOURCE_FILES = \
    MainMenu.xib \
    UDArchiveDocument.xib \
    PakManager.png \
    PakManager-Info.plist

ADDITIONAL_LDFLAGS += -lzip -ldispatch -lBlocksRuntime

include $(GNUSTEP_MAKEFILES)/application.make
