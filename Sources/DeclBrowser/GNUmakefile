APP_NAME = DeclBrowser

OBJC_RUNTIME_LIB = ng
RUNTIME_VERSION = gnustep-2.0
GS_WITH_ARC = 1

include $(GNUSTEP_MAKEFILES)/common.make

# Source list synced with the Xcode DeclBrowser target (2026-08-20).
DeclBrowser_OBJC_FILES = \
    main.m \
    AppDelegate.m \
    UDAppDocumentController.m \
    UDBaseEditorViewController.m \
    UDDeclBrowser.m \
    UDDeclItem.m \
    UDFileItem.m \
    UDFolder.m \
    UDImageViewerViewController.m \
    UDPDAEditorViewController.m \
    UDPathTree.m \
    UDProject.m \
    UDTextEditorViewController.m \
    UDWorkspaceItem.m \
    Documents/UDBaseDocument.m \
    Documents/UDDeclDocument.m \
    Documents/UDImageFileDocument.m \
    Documents/UDTextFileDocument.m \
    Documents/UDWorkspaceDocument.m \
    Window/UDEditorTabManager.m \
    Window/UDTabBarView.m \
    Window/UDTabItemView.m \
    Window/UDTextPromptPanel.m \
    Window/UDWorkspaceSettingsWindowController.m \
    Window/UDWorkspaceWindowController.m

DeclBrowser_INCLUDE_DIRS = \
    -I. \
    -IDocuments \
    -IWindow \
    -I../UDCore \
    -I../UDFormats

# The data model is compiled to DeclModel.momd by FreeCoreData's momc via
# coredata-model.make (included below), which adds the .momd to the app's
# resources automatically.
DeclBrowser_XCDATAMODELD_FILES = ../UDCore/DeclModel.xcdatamodeld

DeclBrowser_RESOURCE_FILES = \
    Resources/Base.lproj/MainMenu.xib \
    Resources/Base.lproj/UDWorkspaceWindow.xib \
    Resources/UDPDAEditorView.xib \
    Resources/UDPDAAudioEditorView.xib \
    Resources/UDPDAEmailEditorView.xib \
    Resources/UDPDAVideoEditorView.xib \
    Resources/UDWorkspaceSettings.xib \
    Resources/UDTabItemView.xib \
    Resources/en.lproj/UDImageViewerView.xib \
    en.lproj/UDTextEditorView.xib \
    UDWorkspaceDocumentWindow.xib \
    UDDeclBrowserWindow.xib \
    DeclBrowser-Info.plist

# CoreData is provided by FreeCoreData on GNUstep
# (https://github.com/ashalkhakov/FreeCoreData — install it before building).
ADDITIONAL_NATIVE_LIBS += CoreData

ADDITIONAL_LIB_DIRS += -L$(GNUSTEP_SYSTEM_LIBRARIES)
# -rdynamic: export the executable's own symbols so UDCrashReporter's
# backtrace (installed in main.m on Linux) resolves app frames by name.
ADDITIONAL_LDFLAGS += -lUDCore -lzip -ldispatch -lBlocksRuntime -rdynamic

# Compiles $(DeclBrowser_XCDATAMODELD_FILES) with momc and bundles the
# resulting .momd; installed into $(GNUSTEP_MAKEFILES) by FreeCoreData.
include $(GNUSTEP_MAKEFILES)/coredata-model.make

include $(GNUSTEP_MAKEFILES)/application.make
