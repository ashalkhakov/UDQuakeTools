LIBRARY_NAME = UDCore

OBJC_RUNTIME_LIB = ng
RUNTIME_VERSION = gnustep-2.0
GS_WITH_ARC = 1

include $(GNUSTEP_MAKEFILES)/common.make

# All non-GUI UDCore sources (FormContainerView.m requires AppKit and is
# kept with the GuiEd app that uses it).
UDCore_OBJC_FILES = \
    UDArchive.m \
    UDArchiveEditor.m \
    UDArchiveEntry.m \
    UDArchiveMutation.m \
    UDAssetIndex.m \
    UDDeclLexer.m \
    UDDeclManager.m \
    UDDeclModel.m \
    UDDeclParser.m \
    UDDeclPersistence.m \
    UDDeclType.m \
    UDDirectoryNode.m \
    UDGame.m \
    UDGameDetectionService.m \
    UDGuiDocumentCodec.m \
    UDGuiEditorService.m \
    UDGuiEditorViewModel.m \
    UDGuiEventsProcessingService.m \
    UDGuiModel.m \
    UDVFSMount.m \
    UDVirtualFileSystem.m \
    ../UDFormats/UDCodecRegistry.m \
    ../UDFormats/UDDaikatanaPAKCodec.m \
    ../UDFormats/UDPAK2Codec.m \
    ../UDFormats/UDPAKCodec.m \
    ../UDFormats/UDPAKEntrySource.m \
    ../UDFormats/UDPK3Codec.m \
    ../UDFormats/UDPK3ZIPEntrySource.m \
    ../UDFormats/UDPK4Codec.m \
    ../UDFormats/UDStagedFileSource.m

UDCore_INCLUDE_DIRS = -I../UDFormats

UDCore_HEADER_FILES_DIR = .
UDCore_HEADER_FILES = \
    UDArchive.h \
    UDArchiveEditor.h \
    UDArchiveEntry.h \
    UDArchiveMutation.h \
    UDAssetIndex.h \
    UDContentSource.h \
    UDDeclManager.h \
    UDDeclModel.h \
    UDDeclParser.h \
    UDDeclPersistence.h \
    UDDeclType.h \
    UDDirectoryNode.h \
    UDGame.h \
    UDGameDetectionService.h \
    UDGuiDocumentCodec.h \
    UDGuiEditorService.h \
    UDGuiEditorViewModel.h \
    UDGuiEventsProcessingService.h \
    UDGuiModel.h \
    UDVFSMount.h \
    UDVirtualFileSystem.h

ADDITIONAL_LDFLAGS += -ldispatch -lBlocksRuntime -lzip

include $(GNUSTEP_MAKEFILES)/library.make
