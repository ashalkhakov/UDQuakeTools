LIBRARY_NAME = UDArchives

OBJC_RUNTIME_LIB = ng
RUNTIME_VERSION = gnustep-2.0
GS_WITH_ARC = 1

include $(GNUSTEP_MAKEFILES)/common.make

UDLIBS_DIR = ..
include $(UDLIBS_DIR)/Libraries.make

UDArchives_OBJC_FILES = \
    UDArchive.m \
    UDArchiveEditor.m \
    UDArchiveEntry.m \
    UDArchiveMutation.m \
    UDDirectoryNode.m \
    Formats/UDCodecRegistry.m \
    Formats/UDDaikatanaPAKCodec.m \
    Formats/UDPAK2Codec.m \
    Formats/UDPAKCodec.m \
    Formats/UDPAKEntrySource.m \
    Formats/UDPK3Codec.m \
    Formats/UDPK3ZIPEntrySource.m \
    Formats/UDPK4Codec.m \
    Formats/UDStagedFileSource.m \
    UDZipWriter.m

UDArchives_INCLUDE_DIRS = $(call ud_own_includes,UDArchives)

UDArchives_HEADER_FILES_DIR = .
UDArchives_HEADER_FILES = \
    UDArchive.h \
    UDArchiveEditor.h \
    UDArchiveEntry.h \
    UDArchiveMutation.h \
    UDContentSource.h \
    UDDirectoryNode.h \
    UDZipWriter.h \
    Formats/UDCodecRegistry.h \
    Formats/UDPK4Codec.h \
    Formats/UDArchiveCodec.h \
    Formats/UDDaikatanaPAKCodec.h \
    Formats/UDPAK2Codec.h \
    Formats/UDPK3Codec.h \
    Formats/UDPAKCodec.h \
    Formats/UDStagedFileSource.h \
    Formats/UDPK3ZIPEntrySource.h \
    Formats/UDPAKEntrySource.h

ADDITIONAL_LIB_DIRS += $(call ud_own_lib_dirs,UDArchives)
UDArchives_LIBRARIES_DEPEND_UPON += $(call ud_own_libs,UDArchives)

# Core Data on GNUstep is FreeCoreData.
ADDITIONAL_NATIVE_LIBS += CoreData

# idFileSystem and idLexer call CFString's functions (gnustep-corebase);
# the archives read zip (minizip) and write it (UDZipWriter) with zlib.
$(LIBRARY_NAME)_LIBRARIES_DEPEND_UPON += $(UD_SYSTEM_LIBS)

include $(GNUSTEP_MAKEFILES)/library.make
