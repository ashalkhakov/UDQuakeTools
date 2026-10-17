# DeclBrowserTests — the Decl Browser app, driven through its own windows.
#
#   xvfb-run -a make run-tests              (the root GNUmakefile's make check
#   UD_DOOM3_PATH=<install> ... run-tests    runs it too, under Xvfb)
#
# The Doom 3 cases look for a retail install at $UD_DOOM3_PATH (default
# /Volumes/ExtraSSD/games/DOOM 3) and check nothing when there is none.

BUNDLE_NAME = DeclBrowserTests
# Built and run, never installed.
DeclBrowserTests_STANDARD_INSTALL = no

OBJC_RUNTIME_LIB = ng
RUNTIME_VERSION = gnustep-2.0
GS_WITH_ARC = 1

include $(GNUSTEP_MAKEFILES)/common.make

APP_DIR = ../../Sources/DeclBrowser

# The app's objects are compiled in directly (no host app): every .m of the
# DeclBrowser target but main.m, whose main() would collide with the test
# runner's, and the app delegate with the updater it starts, which the cases
# never use. Keep in sync with $(APP_DIR)/GNUmakefile.
DeclBrowserTests_OBJC_FILES = \
    UDDeclBrowserTestCase.m \
    UDPDAEditorTests.m \
    UDTableSkinEditorTests.m \
    UDDeclEditorTests.m \
    UDDoom3WorkspaceTests.m \
    UDPakInstallTests.m \
    UDGuiViewerTests.m \
    $(APP_DIR)/UDAppDocumentController.m \
    $(APP_DIR)/UDBaseEditorViewController.m \
    $(APP_DIR)/UDDeclBrowser.m \
    $(APP_DIR)/UDDeclItem.m \
    $(APP_DIR)/UDFileItem.m \
    $(APP_DIR)/UDFolder.m \
    $(APP_DIR)/UDImageViewerViewController.m \
    $(APP_DIR)/UDPDAEditorViewController.m \
    $(APP_DIR)/UDDeclEditorViewController.m \
    $(APP_DIR)/UDTableEditorViewController.m \
    $(APP_DIR)/UDSkinEditorViewController.m \
    $(APP_DIR)/UDEntityDefEditorViewController.m \
    $(APP_DIR)/UDSoundEditorViewController.m \
    $(APP_DIR)/UDParticleEditorViewController.m \
    $(APP_DIR)/UDFXEditorViewController.m \
    $(APP_DIR)/UDAFEditorViewController.m \
    $(APP_DIR)/UDMaterialEditorViewController.m \
    $(APP_DIR)/UDParticlePreview.m \
    $(APP_DIR)/UDGuiPlayer.m \
    $(APP_DIR)/UDTransportController.m \
    $(APP_DIR)/UDGuiView.m \
    $(APP_DIR)/UDGuiGLView.m \
    $(APP_DIR)/UDTabBadge.m \
    $(APP_DIR)/ThirdParty/DMTabBar/DMTabBar.m \
    $(APP_DIR)/ThirdParty/DMTabBar/DMTabBarItem.m \
    $(APP_DIR)/UDGuiEditorViewController.m \
    $(APP_DIR)/UDFXTimelineView.m \
    $(APP_DIR)/UDPathTree.m \
    $(APP_DIR)/UDProject.m \
    $(APP_DIR)/UDScriptServer.m \
    $(APP_DIR)/UDTextEditorViewController.m \
    $(APP_DIR)/UDWorkspaceItem.m \
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

DeclBrowserTests_INCLUDE_DIRS = \
    -I. \
    -I$(APP_DIR) \
    -I$(APP_DIR)/Documents \
    -I$(APP_DIR)/Window \
    -I$(APP_DIR)/ThirdParty/DMTabBar \
    -I../../Sources/UDCore \
    -I../../Sources/UDFormats

# The app loads its nibs with -bundleForClass:, which resolves to this
# bundle (where its classes now live) rather than to DeclBrowser.app.
DeclBrowserTests_RESOURCE_FILES = \
    $(APP_DIR)/Resources/Base.lproj/UDWorkspaceWindow.xib \
    $(APP_DIR)/Resources/UDPDAEditorView.xib \
    $(APP_DIR)/Resources/UDTableEditorView.xib \
    $(APP_DIR)/Resources/UDSkinEditorView.xib \
    $(APP_DIR)/Resources/UDEntityDefEditorView.xib \
    $(APP_DIR)/Resources/UDSoundEditorView.xib \
    $(APP_DIR)/Resources/UDParticleEditorView.xib \
    $(APP_DIR)/Resources/UDGuiViewerView.xib \
    $(APP_DIR)/Resources/UDTransportBar.xib \
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

DeclBrowserTests_XCDATAMODELD_FILES = ../../Sources/UDCore/DeclModel.xcdatamodeld
DeclBrowserTests_NEEDS_GUI = yes

# CoreData is provided by FreeCoreData on GNUstep.
ADDITIONAL_NATIVE_LIBS += CoreData
# UDCore from the tree, built first (the root GNUmakefile).
ADDITIONAL_LIB_DIRS += -L../../Sources/UDCore/$(GNUSTEP_OBJ_DIR_NAME)
ADDITIONAL_LDFLAGS += -lUDCore -lUDCodeKit -lUDPieceTable -lLSPKit -lXCTest -ldispatch -lBlocksRuntime

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
	LD_LIBRARY_PATH="$(CURDIR)/../../Sources/UDCore/$(GNUSTEP_OBJ_DIR_NAME):$(CURDIR)/../../Sources/LSPServerKit/$(GNUSTEP_OBJ_DIR_NAME)$${LD_LIBRARY_PATH:+:$$LD_LIBRARY_PATH}" \
	UD_PLUGINS_PATH="$(GNUSTEP_LOCAL_LIBRARY)/Bundles/UDCodeKit:$(CURDIR)/../../tree-sitter-idscript:$(CURDIR)/../../tree-sitter-iddecl" \
	UD_SCRIPT_LSP="$(CURDIR)/../../Sources/Tools/udscript-lsp/$(GNUSTEP_OBJ_DIR_NAME)/udscript-lsp" \
	timeout -s ABRT $(TEST_TIMEOUT) $(XCTEST) "$(BUNDLE_NAME).bundle"

include $(GNUSTEP_MAKEFILES)/coredata-model.make

include $(GNUSTEP_MAKEFILES)/bundle.make
