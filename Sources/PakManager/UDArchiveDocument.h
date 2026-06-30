/*
 * SPDX-License-Identifier: GPL-2.0-or-later
 * UDArchiveDocument — NSDocument subclass for idTech archive files.
 *
 * On open: selects the appropriate UDArchiveCodec from UDCodecRegistry,
 *          reads the archive, and wraps it in a UDArchiveEditor.
 * On save: delegates writing to the codec via writeEditedArchive:toURL:error:.
 * makeWindowControllers: creates a UDArchiveBrowserController.
 */

#import <AppKit/AppKit.h>

#import "../UDCore/UDGame.h"

@class UDArchive;
@class UDArchiveEditor;
@class UDVirtualFileSystem;
@protocol UDArchiveCodec;

NS_ASSUME_NONNULL_BEGIN

@interface UDArchiveDocument : NSDocument {
    UDArchive          *_archive;
    UDArchiveEditor    *_editor;
    id<UDArchiveCodec>  _codec;
    UDVirtualFileSystem *_virtualFileSystem;
    UDGame *_detectedGame;
}

@property (nonatomic, strong, nullable) UDArchive          *archive;
@property (nonatomic, strong, nullable) UDArchiveEditor    *editor;
@property (nonatomic, strong, nullable) id<UDArchiveCodec>  codec;
@property (nonatomic, strong, nullable) UDVirtualFileSystem *virtualFileSystem;
@property (nonatomic, strong, nullable) UDGame *detectedGame;

@end

NS_ASSUME_NONNULL_END
