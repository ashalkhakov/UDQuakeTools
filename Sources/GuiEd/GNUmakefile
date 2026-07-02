APP_NAME = GuiEd

OBJC_RUNTIME_LIB = ng
RUNTIME_VERSION = gnustep-2.0
GS_WITH_ARC = 1

include $(GNUSTEP_MAKEFILES)/common.make

GuiEd_OBJC_FILES = \
    main.m \
    UDGuiEdAppDelegate.m \
    UDGuiEdDocument.m \
    UDInspectableOutlineView.m \
    UDInspectableTableView.m \
    UDGuiEdDocumentWindowController.m \
    ../UDCore/UDDeclLexer.m \
    ../UDCore/UDDeclParser.m \
    ../UDCore/UDDeclModel.m \
    ../UDCore/UDDeclType.m \
    ../UDCore/UDGuiModel.m \
    ../UDCore/UDGuiDocumentCodec.m \
    ../UDCore/UDGuiEditorService.m \
    ../UDCore/UDGuiEditorViewModel.m

GuiEd_INCLUDE_DIRS = \
    -I../UDCore

GuiEd_RESOURCE_FILES = \
    MainMenu.xib \
    UDGuiEdDocument.xib \
    GuiEd-Info.plist

include $(GNUSTEP_MAKEFILES)/application.make