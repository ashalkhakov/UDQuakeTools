# QuarryTests — the Quarry app, driven through its own windows.
#
#   xvfb-run -a make run-tests              (the root GNUmakefile's make check
#   UD_DOOM3_PATH=<install> ... run-tests    runs it too, under Xvfb)
#
# The Doom 3 cases look for a retail install at $UD_DOOM3_PATH (default
# /Volumes/ExtraSSD/games/DOOM 3) and check nothing when there is none.

BUNDLE_NAME = QuarryTests
# Built and run, never installed.
QuarryTests_STANDARD_INSTALL = no

OBJC_RUNTIME_LIB = ng
RUNTIME_VERSION = gnustep-2.0
GS_WITH_ARC = 1

include $(GNUSTEP_MAKEFILES)/common.make

UDLIBS_DIR = ../../Sources/Libraries
include $(UDLIBS_DIR)/Libraries.make
QUARRY_DIR = ../../Sources/Quarry
include $(QUARRY_DIR)/Quarry.include.make

APP_DIR = ../../Sources/Quarry

# The app's objects are compiled in directly (no host app): every .m of the
# Quarry target but main.m, whose main() would collide with the test
# runner's, and the app delegate with the updater it starts, which the cases
# never use. Keep in sync with $(APP_DIR)/GNUmakefile.
QuarryTests_OBJC_FILES = \
    $(APP_DIR)/Compat/UniformTypeIdentifiersGNUstep/UniformTypeIdentifiers.m \
    UDQuarryTestCase.m \
    UDPDAEditorTests.m \
    UDTableSkinEditorTests.m \
    UDDeclEditorTests.m \
    UDDoom3WorkspaceTests.m \
    UDPakInstallTests.m \
    UDGuiViewerTests.m \
    UDScriptDebuggerTests.m \
    $(wildcard $(UD_SYSTEM_DIR)/*.m) \
    UDScreenshotTests.m \
    ../Support/UDFakeScriptDebugger.m \
    $(APP_DIR)/App/UDAppDocumentController.m \
    $(APP_DIR)/Editors/UDBaseEditorViewController.m \
    $(APP_DIR)/App/UDDeclBrowser.m \
    $(APP_DIR)/Model/UDDeclItem.m \
    $(APP_DIR)/Model/UDFileItem.m \
    $(APP_DIR)/Model/UDFolder.m \
    $(APP_DIR)/Editors/UDImageViewerViewController.m \
    $(APP_DIR)/Editors/UDTopClipView.m \
    $(APP_DIR)/Editors/UDReferencePicker.m \
    $(APP_DIR)/Editors/UDExpressionTextStorage.m \
    $(APP_DIR)/Editors/UDExpressionEditor.m \
    $(APP_DIR)/Editors/Decls/UDPDAEditorViewController.m \
    $(APP_DIR)/Editors/UDDeclEditorViewController.m \
    $(APP_DIR)/Editors/Decls/UDTableEditorViewController.m \
    $(APP_DIR)/Editors/Decls/UDSkinEditorViewController.m \
    $(APP_DIR)/Editors/Decls/UDEntityDefEditorViewController.m \
    $(APP_DIR)/Editors/Decls/UDSoundEditorViewController.m \
    $(APP_DIR)/Editors/Decls/UDParticleEditorViewController.m \
    $(APP_DIR)/Editors/Decls/UDFXEditorViewController.m \
    $(APP_DIR)/Editors/Decls/UDAFEditorViewController.m \
    $(APP_DIR)/Editors/Decls/UDMaterialEditorViewController.m \
    $(APP_DIR)/Preview/UDParticlePreview.m \
    $(APP_DIR)/GUIEditor/UDGuiPlayer.m \
    $(APP_DIR)/GUIEditor/UDGuiEditorOptionsController.m \
    $(APP_DIR)/GUIEditor/UDGuiItemPropertiesController.m \
    $(APP_DIR)/GUIEditor/UDGuiScriptsController.m \
    $(APP_DIR)/Preview/UDTransportController.m \
    $(APP_DIR)/GUIEditor/UDGuiView.m \
    $(APP_DIR)/GUIEditor/UDGuiGLView.m \
    $(APP_DIR)/Window/UDTabBadge.m \
    $(APP_DIR)/ThirdParty/DMTabBar/DMTabBar.m \
    $(APP_DIR)/ThirdParty/DMTabBar/DMTabBarItem.m \
    $(APP_DIR)/GUIEditor/UDGuiEditorViewController.m \
    $(APP_DIR)/Preview/UDFXTimelineView.m \
    $(APP_DIR)/Model/UDPathTree.m \
    $(APP_DIR)/Model/UDWorkspaceProject.m \
    $(APP_DIR)/Scripts/UDScriptServer.m \
    $(APP_DIR)/Scripts/UDScriptDebugger.m \
    $(APP_DIR)/Editors/UDTextEditorViewController.m \
    $(APP_DIR)/Model/UDWorkspaceItem.m \
    $(APP_DIR)/Documents/UDBaseDocument.m \
    $(APP_DIR)/Documents/UDDeclDocument.m \
    $(APP_DIR)/Documents/UDImageFileDocument.m \
    $(APP_DIR)/Documents/UDTextFileDocument.m \
    $(APP_DIR)/Documents/UDWorkspaceDocument.m \
    $(APP_DIR)/Window/UDEditorTabManager.m \
    $(APP_DIR)/Window/UDTextPromptPanel.m \
    $(APP_DIR)/Window/UDWorkspaceSettingsWindowController.m \
    $(APP_DIR)/Window/UDNewDeclWindowController.m \
    $(APP_DIR)/Window/UDWorkspaceOpeningController.m \
    $(APP_DIR)/Window/UDWorkspaceWindowController.m

QuarryTests_INCLUDE_DIRS = \
    -I. \
    -I../Support \
    $(QUARRY_INCLUDE_DIRS) \
    $(UDLIBS_INCLUDE_DIRS)

# The app loads its nibs with -bundleForClass:, which resolves to this
# bundle (where its classes now live) rather than to Quarry.app.
QuarryTests_RESOURCE_FILES = \
    $(APP_DIR)/Resources/Base.lproj/UDWorkspaceWindow.xib \
    $(APP_DIR)/Resources/UDPDAEditorView.xib \
    $(APP_DIR)/Resources/UDTableEditorView.xib \
    $(APP_DIR)/Resources/UDSkinEditorView.xib \
    $(APP_DIR)/Resources/UDEntityDefEditorView.xib \
    $(APP_DIR)/Resources/UDSoundEditorView.xib \
    $(APP_DIR)/Resources/UDParticleEditorView.xib \
    $(APP_DIR)/Resources/UDGuiViewerView.xib \
    $(APP_DIR)/Resources/UDTransportBar.xib \
    $(APP_DIR)/Resources/UDGuiEditorOptions.xib \
    $(APP_DIR)/Resources/UDReferencePicker.xib \
    $(APP_DIR)/Resources/UDExpressionEditor.xib \
    $(APP_DIR)/Resources/UDFXEditorView.xib \
    $(APP_DIR)/Resources/UDAFEditorView.xib \
    $(APP_DIR)/Resources/UDMaterialEditorView.xib \
    $(APP_DIR)/Resources/UDPDAAudioEditorView.xib \
    $(APP_DIR)/Resources/UDPDAEmailEditorView.xib \
    $(APP_DIR)/Resources/UDPDAVideoEditorView.xib \
    $(APP_DIR)/Resources/UDWorkspaceSettings.xib \
    $(APP_DIR)/Resources/UDNewDecl.xib \
    $(APP_DIR)/Resources/UDWorkspaceOpening.xib \
    $(APP_DIR)/Resources/en.lproj/UDImageViewerView.xib \
    $(APP_DIR)/en.lproj/UDTextEditorView.xib

QuarryTests_XCDATAMODELD_FILES = ../../Sources/Libraries/UDDecls/DeclModel.xcdatamodeld
QuarryTests_NEEDS_GUI = yes

# CoreData is provided by FreeCoreData on GNUstep.
ADDITIONAL_NATIVE_LIBS += CoreData
# the libraries from the tree, built first (the root GNUmakefile).
ADDITIONAL_LIB_DIRS += $(UDLIBS_LIB_DIRS)
QuarryTests_BUNDLE_LIBS += $(UDLIBS_LIBS) -lUDCodeKit -lUDPieceTable -lLSPKit -lXCTest -ldispatch $(UD_BLOCKS_LIBS)

# The GUI viewer draws with GL (UDGuiGLView) where the stack's backend has
# GLX and GL's headers are here (libgl-dev); without them it draws in
# software.
ifneq ($(wildcard /usr/include/GL/glx.h),)
ADDITIONAL_CPPFLAGS += -DUD_HAVE_GL
ADDITIONAL_LDFLAGS += -lGL
endif

XCTEST ?= xctest

# Bounded: a modal editor waiting for an event that never comes would
# otherwise hang the run (the cases abort their own modals after 20s).
TEST_TIMEOUT ?= 900

.PHONY: run-tests
run-tests: all $(BUNDLE_NAME).bundle
	. $(GNUSTEP_MAKEFILES)/GNUstep.sh; \
	LD_LIBRARY_PATH="$(UDLIBS_LD_PATH):$(CURDIR)/../../Sources/LSPServerKit/$(GNUSTEP_OBJ_DIR_NAME)$${LD_LIBRARY_PATH:+:$$LD_LIBRARY_PATH}" \
	PATH="$(UDLIBS_LD_PATH):$(CURDIR)/../../Sources/LSPServerKit/$(GNUSTEP_OBJ_DIR_NAME):$$PATH" \
	UD_PLUGINS_PATH="$(GNUSTEP_LOCAL_LIBRARY)/Bundles/UDCodeKit:$(CURDIR)/../../tree-sitter-idscript:$(CURDIR)/../../tree-sitter-iddecl" \
	UD_SCRIPT_LSP="$(CURDIR)/../../Sources/Tools/udscript-lsp/$(GNUSTEP_OBJ_DIR_NAME)/udscript-lsp" \
	UD_SCRIPT_DAP="$(CURDIR)/../../Sources/Tools/udscript-dap/$(GNUSTEP_OBJ_DIR_NAME)/udscript-dap" \
	timeout -s ABRT $(TEST_TIMEOUT) $(XCTEST) "$(BUNDLE_NAME).bundle"

include $(GNUSTEP_MAKEFILES)/coredata-model.make

include $(GNUSTEP_MAKEFILES)/bundle.make
