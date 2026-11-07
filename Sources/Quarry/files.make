# The extension's sources and resources, relative to Sources/Quarry: the
# bundle's (its GNUmakefile) and its tests' (Tests/Extension), which compile
# them in, each with its own prefix ($(QUARRY_DIR)/).
QUARRY_OBJC_FILES = \
    Compat/UniformTypeIdentifiersGNUstep/UniformTypeIdentifiers.m \
    Extension/UQExtension.m \
    Extension/UQProject.m \
    Extension/UQDeclDocument.m \
    Extension/UQEditorHost.m \
    Extension/UQGuiDocument.m \
    Extension/UQPakDocument.m \
    Extension/UQCommands.m \
    Extension/UQRunning.m \
    Window/UDNewDeclWindowController.m \
    ../PakManager/UDArchiveDocument.m \
    ../PakManager/UDArchiveBrowserController.m \
    ../PakManager/UDFileActionService.m \
    ../PakManager/UDTextPreviewController.m \
    Model/UDDeclItem.m \
    Model/UDFileItem.m \
    Model/UDFolder.m \
    Model/UDPathTree.m \
    Model/UDWorkspaceItem.m \
    Model/UDWorkspaceProject.m \
    Documents/UDBaseDocument.m \
    Documents/UDDeclDocument.m \
    Documents/UDImageFileDocument.m \
    Documents/UDTextFileDocument.m \
    Editors/UDBaseEditorViewController.m \
    Editors/UDTextEditorViewController.m \
    Editors/UDImageViewerViewController.m \
    Editors/UDTopClipView.m \
    Editors/UDReferencePicker.m \
    Editors/UDExpressionTextStorage.m \
    Editors/UDExpressionEditor.m \
    Editors/UDDeclEditorViewController.m \
    Editors/Decls/UDPDAEditorViewController.m \
    Editors/Decls/UDTableEditorViewController.m \
    Editors/Decls/UDSkinEditorViewController.m \
    Editors/Decls/UDEntityDefEditorViewController.m \
    Editors/Decls/UDSoundEditorViewController.m \
    Editors/Decls/UDParticleEditorViewController.m \
    Editors/Decls/UDFXEditorViewController.m \
    Editors/Decls/UDAFEditorViewController.m \
    Editors/Decls/UDMaterialEditorViewController.m \
    Preview/UDParticlePreview.m \
    Preview/UDTransportController.m \
    Preview/UDFXTimelineView.m \
    GUIEditor/UDGuiPlayer.m \
    GUIEditor/UDGuiEditorOptionsController.m \
    GUIEditor/UDGuiItemPropertiesController.m \
    GUIEditor/UDGuiScriptsController.m \
    GUIEditor/UDGuiView.m \
    GUIEditor/UDGuiGLView.m \
    GUIEditor/UDGuiEditorViewController.m \
    Scripts/UDScriptServer.m \
    Scripts/UDScriptDebugger.m \
    Window/UDTabBadge.m \
    Window/UDTextPromptPanel.m \
    ThirdParty/DMTabBar/DMTabBar.m \
    ThirdParty/DMTabBar/DMTabBarItem.m

# The grammars, the extension's own modes (UDCodeExtension/Resources/LanguageInfo.plist).
QUARRY_C_FILES = \
    ../../tree-sitter-idscript/src/parser.c \
    ../../tree-sitter-iddecl/src/parser.c

QUARRY_RESOURCE_FILES = \
    Resources/UQEditorHost.xib \
    Resources/UQEditorMenus.xib \
    Resources/UDNewDecl.xib \
    ../PakManager/UDArchiveBrowser.xib \
    Resources/UDPDAEditorView.xib \
    Resources/UDTableEditorView.xib \
    Resources/UDSkinEditorView.xib \
    Resources/UDEntityDefEditorView.xib \
    Resources/UDSoundEditorView.xib \
    Resources/UDParticleEditorView.xib \
    Resources/UDGuiViewerView.xib \
    Resources/UDTransportBar.xib \
    Resources/UDGuiEditorOptions.xib \
    Resources/UDReferencePicker.xib \
    Resources/UDExpressionEditor.xib \
    Resources/UDFXEditorView.xib \
    Resources/UDAFEditorView.xib \
    Resources/UDMaterialEditorView.xib \
    Resources/UDPDAAudioEditorView.xib \
    Resources/UDPDAEmailEditorView.xib \
    Resources/UDPDAVideoEditorView.xib \
    Resources/en.lproj/UDImageViewerView.xib \
    en.lproj/UDTextEditorView.xib \
    ../../UDCodeExtension/Resources/LanguageInfo.plist \
    ../../UDCodeExtension/Resources/highlights-idscript.scm \
    ../../UDCodeExtension/Resources/highlights-iddecl.scm
