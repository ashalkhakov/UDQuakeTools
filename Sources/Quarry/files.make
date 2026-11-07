# The extension's sources and resources, relative to Sources/Quarry: the
# bundle's (its GNUmakefile) and its tests' (Tests/Extension), which compile
# them in, each with its own prefix ($(QUARRY_DIR)/).
QUARRY_OBJC_FILES = \
    Compat/UniformTypeIdentifiersGNUstep/UniformTypeIdentifiers.m \
    Extension/UQExtension.m \
    Extension/UQProject.m \
    Model/UDDeclItem.m \
    Model/UDFileItem.m \
    Model/UDFolder.m \
    Model/UDPathTree.m \
    Model/UDWorkspaceItem.m \
    Model/UDWorkspaceProject.m

# The grammars, the extension's own modes (UDCodeExtension/Resources/LanguageInfo.plist).
QUARRY_C_FILES = \
    ../../tree-sitter-idscript/src/parser.c \
    ../../tree-sitter-iddecl/src/parser.c

QUARRY_RESOURCE_FILES = \
    ../../UDCodeExtension/Resources/LanguageInfo.plist \
    ../../UDCodeExtension/Resources/highlights-idscript.scm \
    ../../UDCodeExtension/Resources/highlights-iddecl.scm
