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

@class UDArchive;
@class UDArchiveEditor;
@protocol UDArchiveCodec;

NS_ASSUME_NONNULL_BEGIN

@interface UDArchiveDocument : NSDocument {
    UDArchive          *_archive;
    UDArchiveEditor    *_editor;
    id<UDArchiveCodec>  _codec;
}

@property (nonatomic, strong, nullable) UDArchive          *archive;
@property (nonatomic, strong, nullable) UDArchiveEditor    *editor;
@property (nonatomic, strong, nullable) id<UDArchiveCodec>  codec;

@end

NS_ASSUME_NONNULL_END
