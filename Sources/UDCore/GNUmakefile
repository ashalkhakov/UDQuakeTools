LIBRARY_NAME = UDCore

OBJC_RUNTIME_LIB = ng
RUNTIME_VERSION = gnustep-2.0
GS_WITH_ARC = 1

include $(GNUSTEP_MAKEFILES)/common.make

UDCore_C_FILES = \
    unzip.c \
    ioapi.c

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
    compat.m \
    idStr.m \
    idFile.m \
    idFileSystem.m \
    UDWorkspace.m \
    UDWorkspaceManager.m \
    MD5.m \
    idDeclManager.m \
    UDBitMsg.m \
    UDDeclManagedObjects.m \
    UDDeclIncrementalStore.m \
    UniformTypeIdentifiers/UniformTypeIdentifiers.m

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

ADDITIONAL_LDFLAGS += -ldispatch -lBlocksRuntime -lzip -lgnustep-corebase

include $(GNUSTEP_MAKEFILES)/library.make

# NOTE: UniformTypeIdentifiers/ is the GNUstep compatibility shim for Apple's
# UniformTypeIdentifiers framework (UTType, UTTypeImage, and the legacy
# UTTypeConformsTo/UTTypeCreatePreferredIdentifierForTag C calls). The
# DeclBrowser sources keep their ordinary
#   #import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
# line: on macOS the system framework resolves it, on GNUstep the
# -I../UDCore include path finds this shim directory instead. The .m
# compiles to nothing on macOS (guarded by !defined(__APPLE__)), so it is
# NOT part of the Xcode project on purpose.
#
# -lgnustep-corebase is required because idFileSystem.m/idLexer.m call
# CFStringLowercase/CFStringTrimWhitespace (fine at library link, surfaces as
# undefined symbols when linking the apps). UDBitMsg.m had gone missing from
# the source list (idDeclManager.m references the class) — same symptom.
