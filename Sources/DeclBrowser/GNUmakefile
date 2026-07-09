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

DeclBrowser_RESOURCE_FILES = \
    MainMenu.xib \
    UDDeclBrowserWindow.xib \
    DeclBrowser-Info.plist

ADDITIONAL_LIB_DIRS += -L$(GNUSTEP_SYSTEM_LIBRARIES)
ADDITIONAL_LDFLAGS += -lUDCore -lzip -ldispatch -lBlocksRuntime

include $(GNUSTEP_MAKEFILES)/application.make
