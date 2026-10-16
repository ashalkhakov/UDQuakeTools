APP_NAME = DeclBrowser

OBJC_RUNTIME_LIB = ng
RUNTIME_VERSION = gnustep-2.0
GS_WITH_ARC = 1

include $(GNUSTEP_MAKEFILES)/common.make

# Source list synced with the Xcode DeclBrowser target (2026-08-20).
DeclBrowser_OBJC_FILES = \
    ../UDUpdater/UDUpdater.m \
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
    UDDeclEditorViewController.m \
    UDTableEditorViewController.m \
    UDSkinEditorViewController.m \
    UDEntityDefEditorViewController.m \
    UDSoundEditorViewController.m \
    UDParticleEditorViewController.m \
    UDFXEditorViewController.m \
    UDAFEditorViewController.m \
    UDMaterialEditorViewController.m \
    UDPathTree.m \
    UDProject.m \
    UDScriptServer.m \
    UDTextEditorViewController.m \
    UDWorkspaceItem.m \
    Documents/UDBaseDocument.m \
    Documents/UDDeclDocument.m \
    Documents/UDImageFileDocument.m \
    Documents/UDTextFileDocument.m \
    Documents/UDWorkspaceDocument.m \
    Window/UDEditorTabManager.m \
    Window/UDTextPromptPanel.m \
    Window/UDWorkspaceSettingsWindowController.m \
    Window/UDNewDeclWindowController.m \
    Window/UDWorkspaceOpeningController.m \
    Window/UDWorkspaceWindowController.m

DeclBrowser_INCLUDE_DIRS = \
    -I. \
    -I../UDUpdater \
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
    Resources/UDTableEditorView.xib \
    Resources/UDSkinEditorView.xib \
    Resources/UDEntityDefEditorView.xib \
    Resources/UDSoundEditorView.xib \
    Resources/UDParticleEditorView.xib \
    Resources/UDFXEditorView.xib \
    Resources/UDAFEditorView.xib \
    Resources/UDMaterialEditorView.xib \
    Resources/UDPDAAudioEditorView.xib \
    Resources/UDPDAEmailEditorView.xib \
    Resources/UDPDAVideoEditorView.xib \
    Resources/UDWorkspaceSettings.xib \
    Resources/UDNewDecl.xib \
    Resources/UDWorkspaceOpening.xib \
    Resources/en.lproj/UDImageViewerView.xib \
    en.lproj/UDTextEditorView.xib \
    DeclBrowser-Info.plist

# CoreData is provided by FreeCoreData on GNUstep
# (https://github.com/ashalkhakov/FreeCoreData — install it before building).
ADDITIONAL_NATIVE_LIBS += CoreData

# UDCore from the tree beside this one, built first (the root GNUmakefile).
ADDITIONAL_LIB_DIRS += -L../UDCore/$(GNUSTEP_OBJ_DIR_NAME)
# -rdynamic: export the executable's own symbols so UDCrashReporter's
# backtrace (installed in main.m on Linux) resolves app frames by name.
# UDCodeKit (the editor, its tab bar) from the prefix, where its release
# archive is unpacked (.github/pins.env).
ADDITIONAL_LDFLAGS += -lUDCore -lUDCodeKit -lUDPieceTable -lLSPKit -ldispatch -lBlocksRuntime -rdynamic

# Compiles $(DeclBrowser_XCDATAMODELD_FILES) with momc and bundles the
# resulting .momd; installed into $(GNUSTEP_MAKEFILES) by FreeCoreData.
include $(GNUSTEP_MAKEFILES)/coredata-model.make

include $(GNUSTEP_MAKEFILES)/application.make

# The scripts' language server beside the executable, where
# -pathForAuxiliaryExecutable: finds it; the grammar bundles in the app's
# PlugIns, where UDCodeKit's language mode registry looks: UDCodeKit's, and
# this toolkit's idScript and decls.
UD_GRAMMARS = $(wildcard $(GNUSTEP_LOCAL_LIBRARY)/Bundles/UDCodeKit/*.bundle) \
    ../../tree-sitter-idscript/TreeSitterIdScript.bundle \
    ../../tree-sitter-iddecl/TreeSitterIdDecl.bundle
after-all::
	@mkdir -p $(GNUSTEP_BUILD_DIR)/DeclBrowser.app/PlugIns
	@for b in $(UD_GRAMMARS); do rm -rf $(GNUSTEP_BUILD_DIR)/DeclBrowser.app/PlugIns/`basename $$b`; \
	    cp -R $$b $(GNUSTEP_BUILD_DIR)/DeclBrowser.app/PlugIns/; done
	@cp ../Tools/udscript-lsp/$(GNUSTEP_OBJ_DIR_NAME)/udscript-lsp $(GNUSTEP_BUILD_DIR)/DeclBrowser.app/
