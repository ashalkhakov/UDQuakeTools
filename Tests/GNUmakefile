include $(GNUSTEP_MAKEFILES)/common.make

CC = clang
GCC_LIB_DIR = $(shell dirname $(shell gcc -print-libgcc-file-name))

TOOL_NAME = udquaketools-tests

udquaketools-tests_OBJC_FILES = \
    TestMain.m \
    UDArchiveEntryTests.m \
    UDPAKCodecTests.m \
    UDPK3CodecTests.m \
    ../Sources/UDCore/UDArchive.m \
    ../Sources/UDCore/UDArchiveEntry.m \
    ../Sources/UDFormats/UDCodecRegistry.m \
    ../Sources/UDFormats/UDPAKCodec.m \
    ../Sources/UDFormats/UDPAKEntrySource.m \
    ../Sources/UDFormats/UDPK3Codec.m \
    ../Sources/UDFormats/UDPK3ZIPEntrySource.m \
    ../Sources/UDFormats/UDPK4Codec.m

udquaketools-tests_INCLUDE_DIRS = \
    -I../Sources/UDCore \
    -I../Sources/UDFormats

udquaketools-tests_LIBRARIES = objc gnustep-base
ADDITIONAL_OBJCFLAGS += -I$(GCC_LIB_DIR)/include
ADDITIONAL_LDFLAGS += -L$(GCC_LIB_DIR) -lzip

.PHONY: run-tests
run-tests: all
	./obj/udquaketools-tests

include $(GNUSTEP_MAKEFILES)/tool.make
