include $(GNUSTEP_MAKEFILES)/common.make

CC = clang
GCC_LIB_DIR = $(shell dirname $(shell gcc -print-libgcc-file-name))

BUNDLE_NAME = UDQuakeToolsTests

UDQuakeToolsTests_OBJC_FILES = \
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

UDQuakeToolsTests_INCLUDE_DIRS = \
    -I../Sources/UDCore \
    -I../Sources/UDFormats

UDQuakeToolsTests_LIBRARIES = objc gnustep-base XCTest

ADDITIONAL_OBJCFLAGS += -I$(GCC_LIB_DIR)/include -I/usr/local/include/GNUstep
ADDITIONAL_LDFLAGS += -L$(GCC_LIB_DIR) -L/usr/local/lib -Wl,-rpath,/usr/local/lib -lzip -lgnustep-base -lXCTest

XCTEST ?= xctest

.PHONY: run-tests
run-tests: all $(BUNDLE_NAME).bundle
	@echo "Running XCTest bundle: $(BUNDLE_NAME)"
	. $(GNUSTEP_MAKEFILES)/GNUstep.sh; \
	$(XCTEST) "$(BUNDLE_NAME).bundle"

include $(GNUSTEP_MAKEFILES)/bundle.make

