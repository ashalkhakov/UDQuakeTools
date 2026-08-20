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
    UDDirectoryNode.m \
    UDGame.m \
    UDGameDetectionService.m \
    ../UDFormats/UDCodecRegistry.m \
    ../UDFormats/UDDaikatanaPAKCodec.m \
    ../UDFormats/UDPAK2Codec.m \
    ../UDFormats/UDPAKCodec.m \
    ../UDFormats/UDPAKEntrySource.m \
    ../UDFormats/UDPK3Codec.m \
    ../UDFormats/UDPK3ZIPEntrySource.m \
    ../UDFormats/UDPK4Codec.m \
    ../UDFormats/UDStagedFileSource.m \
    idToken.m \
    idLexer.m \
    idParser.m \
    unzip.c \
    ioapi.c \
    compat.m \
    idStr.m \
    idFile.m \
    idFileSystem.m \
    UDWorkspace.m \
    UDWorkspaceManager.m \
    MD5.m \
    idDeclManager.m \
    UDDeclManagedObjects.m \
    UDDeclIncrementalStore.m

UDCore_INCLUDE_DIRS = -I../UDFormats

UDCore_HEADER_FILES_DIR = .
UDCore_HEADER_FILES = \
    UDArchive.h \
    UDArchiveEditor.h \
    UDArchiveEntry.h \
    UDArchiveMutation.h \
    UDContentSource.h \
    UDDirectoryNode.h \
    UDGame.h \
    UDGameDetectionService.h \
    idToken.h \
    idLexer.h \
    idParser.h \
    idStr.h \
    idFile.h \
    idFileSystem.h \
    UDWorkspace.h \
    UDWorkspaceManager.h \
    MD5.h \
    idDeclManager.h \
    UDDeclManagedObjects.h \
    UDDeclIncrementalStore.h

# CoreData is provided by FreeCoreData on GNUstep
# (https://github.com/ashalkhakov/FreeCoreData — install it before building).
ADDITIONAL_NATIVE_LIBS += CoreData

ADDITIONAL_LDFLAGS += -ldispatch -lBlocksRuntime -lzip

include $(GNUSTEP_MAKEFILES)/library.make
