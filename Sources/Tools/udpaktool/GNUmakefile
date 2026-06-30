TOOL_NAME = udpaktool

OBJC_RUNTIME_LIB = ng
RUNTIME_VERSION = gnustep-2.0
GS_WITH_ARC = 1

include $(GNUSTEP_MAKEFILES)/common.make

udpaktool_OBJC_FILES = \
    main.m \
    ../../UDCore/UDArchive.m \
    ../../UDCore/UDArchiveEntry.m \
    ../../UDCore/UDVFSMount.m \
    ../../UDCore/UDVirtualFileSystem.m \
    ../../UDFormats/UDCodecRegistry.m \
    ../../UDFormats/UDPAKCodec.m \
    ../../UDFormats/UDPAKEntrySource.m \
    ../../UDFormats/UDPAK2Codec.m \
    ../../UDFormats/UDDaikatanaPAKCodec.m \
    ../../UDFormats/UDPK3Codec.m \
    ../../UDFormats/UDPK3ZIPEntrySource.m \
    ../../UDFormats/UDPK4Codec.m

udpaktool_INCLUDE_DIRS = \
    -I../../UDCore \
    -I../../UDFormats

udpaktool_LIBRARIES = gnustep-base

ADDITIONAL_LDFLAGS += -lzip

include $(GNUSTEP_MAKEFILES)/tool.make
