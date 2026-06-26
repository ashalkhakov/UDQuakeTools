# OBJC_RUNTIME_LIB = ng
# RUNTIME_VERSION = gnustep-2.0
# GS_WITH_ARC = 1

include $(GNUSTEP_MAKEFILES)/common.make

CC = clang
GCC_LIB_DIR = $(shell dirname $(shell gcc -print-libgcc-file-name))

APP_NAME = UDArchivist

UDArchivist_OBJC_FILES = \
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

UDArchivist_INCLUDE_DIRS = \
    -I../UDCore \
    -I../UDFormats

UDArchivist_RESOURCE_FILES = \
    UDArchiveDocument.xib \
    UDArchivist-Info.plist

UDArchivist_LIBRARIES = objc gnustep-base gnustep-gui

ADDITIONAL_OBJCFLAGS += -I$(GCC_LIB_DIR)/include
ADDITIONAL_OBJCFLAGS += -I/usr/local/include/GNUstep -D__weak= -Dweak=assign -fblocks
ADDITIONAL_LDFLAGS   += -L/usr/local/lib -Wl,-rpath,/usr/local/lib -L$(GCC_LIB_DIR) -lzip -lgnustep-base -lBlocksRuntime
ADDITIONAL_APP_LIBS += -lgnustep-base

include $(GNUSTEP_MAKEFILES)/application.make
