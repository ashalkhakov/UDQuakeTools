LIBRARY_NAME = UDCore

OBJC_RUNTIME_LIB = ng
RUNTIME_VERSION = gnustep-2.0
GS_WITH_ARC = 1

include $(GNUSTEP_MAKEFILES)/common.make

UDCORE_DIR = .
include UDCore.include.make

UDCore_C_FILES = \
    Framework/unzip.c \
    Framework/ioapi.c

UDCore_OBJC_FILES = \
    Scripts/UDScriptEvents.m Scripts/UDScriptIndex.m \
    Archives/UDArchive.m \
    Archives/UDArchiveEditor.m \
    Archives/UDArchiveEntry.m \
    Archives/UDArchiveMutation.m \
    Archives/UDDirectoryNode.m \
    Workspace/UDGame.m \
    Workspace/UDGameDetectionService.m \
    ../UDFormats/UDCodecRegistry.m \
    ../UDFormats/UDDaikatanaPAKCodec.m \
    ../UDFormats/UDPAK2Codec.m \
    ../UDFormats/UDPAKCodec.m \
    ../UDFormats/UDPAKEntrySource.m \
    ../UDFormats/UDPK3Codec.m \
    ../UDFormats/UDPK3ZIPEntrySource.m \
    ../UDFormats/UDPK4Codec.m \
    ../UDFormats/UDStagedFileSource.m \
    idLib/idToken.m \
    idLib/idLexer.m \
    idLib/idParser.m \
    idLib/compat.m \
    idLib/idStr.m \
    Framework/idFile.m \
    Framework/idFileSystem.m \
    Workspace/UDWorkspace.m \
    Workspace/UDWorkspaceManager.m \
    idLib/MD5.m \
    Framework/idDeclManager.m \
    idLib/UDBitMsg.m \
    Workspace/UDCrashReporter.m \
    Decls/UDDeclCodec.m \
    Decls/UDDeclBase.m \
    Decls/UDDeclRawText.m \
    Decls/UDDeclElement.m \
    Decls/UDDeclTable.m \
    Decls/UDDeclSkin.m \
    Decls/UDDeclEntityDef.m \
    Decls/UDDeclSound.m \
    Decls/UDDeclFX.m \
    Decls/UDDeclAF.m \
    Renderer/UDMD5Mesh.m \
    Scripts/UDSourceTokens.m \
    Decls/UDDeclMaterial.m \
    Renderer/UDParticleModel.m \
    Renderer/UDSoftwareRenderer.m \
    Renderer/UDFXModel.m \
    Renderer/UDARBProgram.m \
    idLib/idMath.m \
    idLib/idDict.m \
    idLib/idStrPool.m \
    idLib/idLangDict.m \
    Framework/idCVarSystem.m \
    UI/idWinVar.m \
    UI/idRegExp.m \
    UI/idGuiScript.m \
    UI/idWindow.m \
    GUIEditor/rvGEWindowWrapper.m \
    GUIEditor/rvGEWorkspace.m \
    GUIEditor/rvGEOptions.m \
    GUIEditor/rvGEModifier.m \
    GUIEditor/rvGESelectionMgr.m \
    GUIEditor/UDOverlay.m \
    UI/idSimpleWindow.m \
    Renderer/idGuiModel.m \
    UI/idDeviceContext.m \
    UI/idUserInterface.m \
    UI/idSliderWindow.m \
    UI/idEditWindow.m \
    UI/idChoiceWindow.m \
    UI/idListWindow.m \
    UI/idBindWindow.m \
    UI/idFieldWindow.m \
    UI/idMarkerWindow.m \
    UI/idRenderWindow.m \
    Renderer/UDMaterialParser.m \
    Renderer/UDImageProgram.m \
    Decls/UDDeclPDA.m \
    Decls/UDDeclParticle.m \
    Decls/UDDeclIncrementalStore.m \
    Archives/UDZipWriter.m \
    Decls/UDDeclTextChecker.m \
    UniformTypeIdentifiersGNUstep/UniformTypeIdentifiers.m

UDCore_INCLUDE_DIRS = $(UDCORE_INCLUDE_DIRS) -I../UDFormats

UDCore_HEADER_FILES_DIR = .
UDCore_HEADER_FILES = \
    Scripts/UDScriptEvents.h Scripts/UDScriptIndex.h \
    Archives/UDArchive.h \
    Archives/UDArchiveEditor.h \
    Archives/UDArchiveEntry.h \
    Archives/UDArchiveMutation.h \
    Archives/UDContentSource.h \
    Archives/UDDirectoryNode.h \
    Workspace/UDGame.h \
    Workspace/UDGameDetectionService.h \
    idLib/idToken.h \
    idLib/idLexer.h \
    idLib/idParser.h \
    idLib/idStr.h \
    Framework/idFile.h \
    Framework/idFileSystem.h \
    Workspace/UDWorkspace.h \
    Workspace/UDWorkspaceManager.h \
    idLib/MD5.h \
    Framework/idDeclManager.h \
    Workspace/UDCrashReporter.h \
    Decls/UDDeclManagedObjects.h \
    Decls/UDDeclBase.h \
    Decls/UDDeclRawText.h \
    Decls/UDDeclElement.h \
    Decls/UDDeclTable.h \
    Decls/UDDeclSkin.h \
    Decls/UDDeclEntityDef.h \
    Decls/UDDeclSound.h \
    Decls/UDDeclFX.h \
    Decls/UDDeclAF.h \
    Renderer/UDMD5Mesh.h \
    Scripts/UDSourceTokens.h \
    Decls/UDDeclMaterial.h \
    Renderer/UDParticleModel.h \
    Renderer/UDSoftwareRenderer.h \
    Renderer/UDFXModel.h \
    Renderer/UDARBProgram.h \
    idLib/idMath.h \
    idLib/idDict.h \
    idLib/idStrPool.h \
    idLib/idLangDict.h \
    Framework/idCVarSystem.h \
    UI/idWinVar.h \
    UI/idRegExp.h \
    UI/idGuiScript.h \
    UI/idWindow.h \
    GUIEditor/rvGEWindowWrapper.h \
    GUIEditor/rvGEWorkspace.h \
    GUIEditor/rvGEOptions.h \
    GUIEditor/rvGEModifier.h \
    GUIEditor/rvGESelectionMgr.h \
    GUIEditor/UDOverlay.h \
    Renderer/idGuiModel.h \
    UI/idDeviceContext.h \
    UI/idUserInterface.h \
    UI/idSliderWindow.h \
    UI/idEditWindow.h \
    UI/idChoiceWindow.h \
    UI/idListWindow.h \
    UI/idBindWindow.h \
    UI/idFieldWindow.h \
    UI/idMarkerWindow.h \
    UI/idRenderWindow.h \
    Renderer/UDMaterialParser.h \
    Renderer/UDImageProgram.h \
    Decls/UDDeclPDA.h \
    Decls/UDDeclParticle.h \
    Decls/UDDeclIncrementalStore.h \
    Archives/UDZipWriter.h \
    Decls/UDDeclTextChecker.h

# CoreData is provided by FreeCoreData on GNUstep
# (https://github.com/ashalkhakov/FreeCoreData — install it before building).
ADDITIONAL_NATIVE_LIBS += CoreData

ADDITIONAL_LDFLAGS += -ldispatch -lBlocksRuntime -lz -lgnustep-corebase

include $(GNUSTEP_MAKEFILES)/library.make

# NOTE: UniformTypeIdentifiersGNUstep/ is the GNUstep compatibility shim for Apple's
# UniformTypeIdentifiers framework (UTType, UTTypeImage, and the legacy
# UTTypeConformsTo/UTTypeCreatePreferredIdentifierForTag C calls). The
# DeclBrowser sources keep their ordinary
#   #import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
# line: on macOS the system framework resolves it, on GNUstep the
# -I../UDCore include path finds this shim directory instead. The .m
# compiles to nothing on macOS (guarded by !defined(__APPLE__)), so it is
# NOT part of the Xcode project on purpose.
#
# ZIP archives need only zlib (-lz): Framework/unzip.c/ioapi.c (the minizip reader
# ported with the Doom 3 file system) read them and UDZipWriter writes them.
#
# -lgnustep-corebase is required because Framework/idFileSystem.m/idLexer.m call
# CFStringLowercase/CFStringTrimWhitespace (fine at library link, surfaces as
# undefined symbols when linking the apps). idLib/UDBitMsg.m had gone missing from
# the source list (Framework/idDeclManager.m references the class) — same symptom.
