APP_NAME = DeclBrowser

OBJC_RUNTIME_LIB = ng
RUNTIME_VERSION = gnustep-2.0
GS_WITH_ARC = 1

include $(GNUSTEP_MAKEFILES)/common.make

DeclBrowser_OBJC_FILES = \
    main.m \
    UDDeclBrowserAppDelegate.m \
    UDDeclBrowserTreeModel.m \
    UDDeclBrowserViewModel.m \
    UDDeclBrowserWindowController.m \
    ../UDCore/UDAssetIndex.m \
    ../UDCore/UDDeclLexer.m \
    ../UDCore/UDDeclParser.m \
    ../UDCore/UDDeclModel.m \
    ../UDCore/UDDeclPersistence.m \
    ../UDCore/UDDeclType.m \
    ../UDCore/UDDeclManager.m \
    ../UDCore/UDGuiModel.m \
    ../UDCore/UDGuiDocumentCodec.m \
    ../UDCore/UDGuiEditorService.m \
    ../UDCore/UDGuiEventsProcessingService.m \
    ../UDCore/UDGuiEditorViewModel.m \
    ../UDCore/UDGame.m \
    ../UDCore/UDGameDetectionService.m \
    ../UDCore/UDArchive.m \
    ../UDCore/UDArchiveEntry.m \
    ../UDCore/UDDirectoryNode.m \
    ../UDCore/UDArchiveMutation.m \
    ../UDCore/UDArchiveEditor.m \
    ../UDCore/UDVFSMount.m \
    ../UDCore/UDVirtualFileSystem.m \
    ../UDFormats/UDCodecRegistry.m \
    ../UDFormats/UDPAKCodec.m \
    ../UDFormats/UDPAKEntrySource.m \
    ../UDFormats/UDStagedFileSource.m \
    ../UDFormats/UDPAK2Codec.m \
    ../UDFormats/UDDaikatanaPAKCodec.m \
    ../UDFormats/UDPK3Codec.m \
    ../UDFormats/UDPK3ZIPEntrySource.m \
    ../UDFormats/UDPK4Codec.m

DeclBrowser_INCLUDE_DIRS = \
    -I../UDCore \
    -I../UDFormats

DeclBrowser_RESOURCE_FILES = \
    MainMenu.xib \
    UDDeclBrowserWindow.xib \
    DeclBrowser-Info.plist

ADDITIONAL_LDFLAGS += -lzip -ldispatch -lBlocksRuntime

include $(GNUSTEP_MAKEFILES)/application.make
