/*
 * SPDX-License-Identifier: GPL-2.0-or-later
 * UDStagedFileSource — UDContentSource backed by a local file on disk.
 *
 * Used when the user adds a real file from the file system into an archive
 * before the archive is saved.  The file at `fileURL` is read on demand;
 * its size is cached after the first query.
 */

#import <Foundation/Foundation.h>
#import "UDContentSource.h"

NS_ASSUME_NONNULL_BEGIN

@interface UDStagedFileSource : NSObject <UDContentSource> {
    NSURL    *_fileURL;
    uint64_t  _cachedLength;
    BOOL      _lengthLoaded;
}

- (instancetype)initWithFileURL:(NSURL *)fileURL NS_DESIGNATED_INITIALIZER;

@end

NS_ASSUME_NONNULL_END
