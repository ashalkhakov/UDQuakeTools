include $(GNUSTEP_MAKEFILES)/common.make

CC = clang
GCC_LIB_DIR = $(shell dirname $(shell gcc -print-libgcc-file-name))

TOOL_NAME = udpaktool

udpaktool_OBJC_FILES = \
    main.m \
    ../../UDCore/UDArchive.m \
    ../../UDCore/UDArchiveEntry.m \
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

udpaktool_LIBRARIES = objc gnustep-base
ADDITIONAL_OBJCFLAGS += -I$(GCC_LIB_DIR)/include
ADDITIONAL_LDFLAGS += -L$(GCC_LIB_DIR) -lzip

include $(GNUSTEP_MAKEFILES)/tool.make
