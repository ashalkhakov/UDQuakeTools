# OBJC_RUNTIME_LIB = ng
# RUNTIME_VERSION = gnustep-2.0
# GS_WITH_ARC = 1

include $(GNUSTEP_MAKEFILES)/common.make

CC = clang
GCC_LIB_DIR = $(shell dirname $(shell gcc -print-libgcc-file-name))

TOOL_NAME = udquaketools-tests

udquaketools-tests_OBJC_FILES = \
    TestMain.m \
    UDArchiveEntryTests.m \
    UDPAKCodecTests.m \
    UDPK3CodecTests.m \
    UDGameDetectionTests.m \
    ../Sources/UDCore/UDGame.m \
    ../Sources/UDCore/UDGameDetectionService.m \
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
# ADDITIONAL_OBJCFLAGS += -I$(GCC_LIB_DIR)/include
ADDITIONAL_OBJCFLAGS += -I/usr/local/include/GNUstep
ADDITIONAL_LDFLAGS += -L/usr/local/lib -Wl,-rpath,/usr/local/lib -L$(GCC_LIB_DIR) -lzip -lgnustep-base
ADDITIONAL_TOOL_LIBS += -lgnustep-base

.PHONY: run-tests
run-tests: all
	./obj/udquaketools-tests

include $(GNUSTEP_MAKEFILES)/tool.make
