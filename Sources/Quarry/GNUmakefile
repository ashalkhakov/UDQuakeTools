APP_NAME = Quarry

OBJC_RUNTIME_LIB = ng
RUNTIME_VERSION = gnustep-2.0
GS_WITH_ARC = 1

include $(GNUSTEP_MAKEFILES)/common.make

UDLIBS_DIR = ../Libraries
QUARRY_DIR = .
include Quarry.include.make
include $(UDLIBS_DIR)/Libraries.make

# Source list synced with the Xcode Quarry target (2026-08-20).
Quarry_OBJC_FILES = \
    Compat/UniformTypeIdentifiersGNUstep/UniformTypeIdentifiers.m \
    ../UDUpdater/UDUpdater.m \
    App/main.m \
    App/AppDelegate.m \
    App/UDAppDocumentController.m \
    Editors/UDBaseEditorViewController.m \
    App/UDDeclBrowser.m \
    Model/UDDeclItem.m \
    Model/UDFileItem.m \
    Model/UDFolder.m \
    Editors/UDImageViewerViewController.m \
    Editors/Decls/UDPDAEditorViewController.m \
    Editors/UDDeclEditorViewController.m \
    Editors/Decls/UDTableEditorViewController.m \
    Editors/Decls/UDSkinEditorViewController.m \
    Editors/Decls/UDEntityDefEditorViewController.m \
    Editors/Decls/UDSoundEditorViewController.m \
    Editors/Decls/UDParticleEditorViewController.m \
    Editors/Decls/UDFXEditorViewController.m \
    Editors/Decls/UDAFEditorViewController.m \
    Editors/Decls/UDMaterialEditorViewController.m \
    Preview/UDParticlePreview.m \
    GUIEditor/UDGuiPlayer.m \
    Preview/UDTransportController.m \
    GUIEditor/UDGuiView.m \
    GUIEditor/UDGuiGLView.m \
    Window/UDTabBadge.m \
    ThirdParty/DMTabBar/DMTabBar.m \
    ThirdParty/DMTabBar/DMTabBarItem.m \
    GUIEditor/UDGuiEditorViewController.m \
    Preview/UDFXTimelineView.m \
    Model/UDPathTree.m \
    Model/UDProject.m \
    Scripts/UDScriptServer.m \
    Editors/UDTextEditorViewController.m \
    Model/UDWorkspaceItem.m \
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

Quarry_INCLUDE_DIRS = \
    $(QUARRY_INCLUDE_DIRS) \
    -I../UDUpdater \
    $(UDLIBS_INCLUDE_DIRS)

# The data model is compiled to DeclModel.momd by FreeCoreData's momc via
# coredata-model.make (included below), which adds the .momd to the app's
# resources automatically.
Quarry_XCDATAMODELD_FILES = ../Libraries/UDDecls/DeclModel.xcdatamodeld

Quarry_RESOURCE_FILES = \
    Resources/Base.lproj/MainMenu.xib \
    Resources/Base.lproj/UDWorkspaceWindow.xib \
    Resources/UDPDAEditorView.xib \
    Resources/UDTableEditorView.xib \
    Resources/UDSkinEditorView.xib \
    Resources/UDEntityDefEditorView.xib \
    Resources/UDSoundEditorView.xib \
    Resources/UDParticleEditorView.xib \
    Resources/UDGuiViewerView.xib \
    Resources/UDTransportBar.xib \
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
    Quarry-Info.plist

# CoreData is provided by FreeCoreData on GNUstep
# (https://github.com/ashalkhakov/FreeCoreData — install it before building).
ADDITIONAL_NATIVE_LIBS += CoreData

# the libraries from the tree beside this one, built first (the root GNUmakefile).
ADDITIONAL_LIB_DIRS += $(UDLIBS_LIB_DIRS)
# -rdynamic: export the executable's own symbols so UDCrashReporter's
# backtrace (installed in App/main.m on Linux) resolves app frames by name.
# UDCodeKit (the editor, its tab bar) from the prefix, where its release
# archive is unpacked (.github/pins.env).
ADDITIONAL_LDFLAGS += $(UDLIBS_LIBS) -lUDCodeKit -lUDPieceTable -lLSPKit -ldispatch -lBlocksRuntime -rdynamic

# The GUI viewer draws with GL (UDGuiGLView) where the stack's backend has
# GLX and GL's headers are here (libgl-dev); without them it draws in
# software.
ifneq ($(wildcard /usr/include/GL/glx.h),)
ADDITIONAL_CPPFLAGS += -DUD_HAVE_GL
ADDITIONAL_LDFLAGS += -lGL
endif

# Compiles $(Quarry_XCDATAMODELD_FILES) with momc and bundles the
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
	@mkdir -p $(GNUSTEP_BUILD_DIR)/Quarry.app/PlugIns
	@for b in $(UD_GRAMMARS); do rm -rf $(GNUSTEP_BUILD_DIR)/Quarry.app/PlugIns/`basename $$b`; \
	    cp -R $$b $(GNUSTEP_BUILD_DIR)/Quarry.app/PlugIns/; done
	@cp ../Tools/udscript-lsp/$(GNUSTEP_OBJ_DIR_NAME)/udscript-lsp $(GNUSTEP_BUILD_DIR)/Quarry.app/
