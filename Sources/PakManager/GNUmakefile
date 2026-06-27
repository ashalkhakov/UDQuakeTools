APP_NAME = PakManager

OBJC_RUNTIME_LIB = ng
RUNTIME_VERSION = gnustep-2.0
GS_WITH_ARC = 1

include $(GNUSTEP_MAKEFILES)/common.make

PakManager_OBJC_FILES = \
    main.m \
    UDAppDelegate.m \
    UDArchiveDocument.m \
    UDArchiveBrowserController.m \
    UDTextPreviewController.m \
    UDFileActionService.m \
    ../UDCore/UDGame.m \
    ../UDCore/UDGameDetectionService.m \
    ../UDCore/UDArchive.m \
    ../UDCore/UDArchiveEntry.m \
    ../UDCore/UDDirectoryNode.m \
    ../UDCore/UDArchiveMutation.m \
    ../UDCore/UDArchiveEditor.m \
    ../UDFormats/UDCodecRegistry.m \
    ../UDFormats/UDPAKCodec.m \
    ../UDFormats/UDPAKEntrySource.m \
    ../UDFormats/UDStagedFileSource.m \
    ../UDFormats/UDPAK2Codec.m \
    ../UDFormats/UDDaikatanaPAKCodec.m \
    ../UDFormats/UDPK3Codec.m \
    ../UDFormats/UDPK3ZIPEntrySource.m \
    ../UDFormats/UDPK4Codec.m

PakManager_INCLUDE_DIRS = \
    -I../UDCore \
    -I../UDFormats

PakManager_RESOURCE_FILES = \
    UDArchiveDocument.xib \
    PakManager-Info.plist

ADDITIONAL_LDFLAGS += -lzip

include $(GNUSTEP_MAKEFILES)/application.make
