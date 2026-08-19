APP_NAME = DeclBrowser

OBJC_RUNTIME_LIB = ng
RUNTIME_VERSION = gnustep-2.0
GS_WITH_ARC = 1

include $(GNUSTEP_MAKEFILES)/common.make

DeclBrowser_OBJC_FILES = \
    main.m \
    UDDeclBrowserAppDelegate.m \
    UDDeclBrowserTreeModel.m \
    UDDeclBrowserViewModel.m \
    UDDeclBrowserWindowController.m

DeclBrowser_INCLUDE_DIRS = \
    -I../UDCore \
    -I../UDFormats

# DeclModel.xcdatamodeld is bundled uncompiled: FreeCoreData's
# NSManagedObjectModel reads the .xcdatamodel XML directly (there is no momc
# on GNUstep), and UDDeclIncrementalStore falls back to it at runtime.
DeclBrowser_RESOURCE_FILES = \
    MainMenu.xib \
    UDDeclBrowserWindow.xib \
    DeclBrowser-Info.plist \
    ../UDCore/DeclModel.xcdatamodeld

# CoreData is provided by FreeCoreData on GNUstep
# (https://github.com/ashalkhakov/FreeCoreData — install it before building).
ADDITIONAL_NATIVE_LIBS += CoreData

ADDITIONAL_LIB_DIRS += -L$(GNUSTEP_SYSTEM_LIBRARIES)
ADDITIONAL_LDFLAGS += -lUDCore -lzip -ldispatch -lBlocksRuntime

include $(GNUSTEP_MAKEFILES)/application.make
