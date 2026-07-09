LIBRARY_NAME = UDFormats

OBJC_RUNTIME_LIB = ng
RUNTIME_VERSION = gnustep-2.0
GS_WITH_ARC = 1

include $(GNUSTEP_MAKEFILES)/common.make

UDFormats_OBJC_FILES = \
    UDCodecRegistry.m \
    UDDaikatanaPAKCodec.m \
    UDPAK2Codec.m \
    UDPAKCodec.m \
    UDPAKEntrySource.m \
    UDPK3Codec.m \
    UDPK3ZIPEntrySource.m \
    UDPK4Codec.m \
    UDStagedFileSource.m

UDFormats_HEADER_FILES_DIR = .
UDFormats_HEADER_FILES = \
    UDArchiveCodec.h \
    UDCodecRegistry.h \
    UDDaikatanaPAKCodec.h \
    UDPAK2Codec.h \
    UDPAKCodec.h \
    UDPAKEntrySource.h \
    UDPK3Codec.h \
    UDPK3ZIPEntrySource.h \
    UDPK4Codec.h \
    UDStagedFileSource.h

UDFormats_INCLUDE_DIRS = -I../UDCore

ADDITIONAL_LDFLAGS += -lzip

include $(GNUSTEP_MAKEFILES)/library.make
