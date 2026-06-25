include $(GNUSTEP_MAKEFILES)/common.make

CC = clang

TOOL_NAME = udquaketools-tests

udquaketools-tests_OBJC_FILES = \
    TestMain.m \
    UDArchiveEntryTests.m \
    UDPAKCodecTests.m \
    ../Sources/UDCore/UDArchive.m \
    ../Sources/UDCore/UDArchiveEntry.m \
    ../Sources/UDFormats/UDCodecRegistry.m \
    ../Sources/UDFormats/UDPAKCodec.m \
    ../Sources/UDFormats/UDPAKEntrySource.m

udquaketools-tests_INCLUDE_DIRS = \
    -I../Sources/UDCore \
    -I../Sources/UDFormats

udquaketools-tests_LIBRARIES = objc gnustep-base
ADDITIONAL_OBJCFLAGS += -I/usr/lib/gcc/x86_64-linux-gnu/13/include
ADDITIONAL_LDFLAGS += -L/usr/lib/gcc/x86_64-linux-gnu/13

.PHONY: run-tests
run-tests: all
	./obj/udquaketools-tests

include $(GNUSTEP_MAKEFILES)/tool.make
