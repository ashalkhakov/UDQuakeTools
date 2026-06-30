BUNDLE_NAME = UDQuakeToolsTests

OBJC_RUNTIME_LIB = ng
RUNTIME_VERSION = gnustep-2.0
GS_WITH_ARC = 1

include $(GNUSTEP_MAKEFILES)/common.make

UDQuakeToolsTests_OBJC_FILES = \
    UDAssetIndexTests.m \
    UDArchiveEntryTests.m \
    UDArchiveEditorTests.m \
    UDArchiveWorkflowTests.m \
    UDVirtualFileSystemTests.m \
    UDPAKCodecTests.m \
    UDPK3CodecTests.m \
    UDGameDetectionTests.m \
    ../Sources/UDCore/UDGame.m \
    ../Sources/UDCore/UDGameDetectionService.m \
    ../Sources/UDCore/UDArchive.m \
    ../Sources/UDCore/UDAssetIndex.m \
    ../Sources/UDCore/UDArchiveEntry.m \
    ../Sources/UDCore/UDArchiveEditor.m \
    ../Sources/UDCore/UDArchiveMutation.m \
    ../Sources/UDCore/UDDirectoryNode.m \
    ../Sources/UDCore/UDVFSMount.m \
    ../Sources/UDCore/UDVirtualFileSystem.m \
    ../Sources/UDFormats/UDCodecRegistry.m \
    ../Sources/UDFormats/UDPAKCodec.m \
    ../Sources/UDFormats/UDPAK2Codec.m \
    ../Sources/UDFormats/UDDaikatanaPAKCodec.m \
    ../Sources/UDFormats/UDPAKEntrySource.m \
    ../Sources/UDFormats/UDStagedFileSource.m \
    ../Sources/UDFormats/UDPK3Codec.m \
    ../Sources/UDFormats/UDPK3ZIPEntrySource.m \
    ../Sources/UDFormats/UDPK4Codec.m

UDQuakeToolsTests_INCLUDE_DIRS = \
    -I../Sources/UDCore \
    -I../Sources/UDFormats

ADDITIONAL_LDFLAGS += -lzip -lXCTest

XCTEST ?= xctest

.PHONY: run-tests
run-tests: all $(BUNDLE_NAME).bundle
	@echo "Running XCTest bundle: $(BUNDLE_NAME)"
	. $(GNUSTEP_MAKEFILES)/GNUstep.sh; \
	$(XCTEST) "$(BUNDLE_NAME).bundle"

include $(GNUSTEP_MAKEFILES)/bundle.make

