#import <Foundation/Foundation.h>
#import "UDContentSource.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * UDContentSource that reads a single entry from a ZIP archive, through the
 * minizip unzip.c that the Doom 3 file system uses.
 *
 * The entry is addressed by its central directory position (as recorded by
 * unzGetCurrentFileInfoPosition while listing the archive), the same way
 * idFileSystem addresses files in a pk4. The archive file is opened and
 * closed for every read so that multiple sources can coexist without
 * keeping the file descriptor open permanently. Both stored (method 0) and
 * deflate-compressed (method 8) entries are supported, and the entry's
 * CRC-32 is checked.
 *
 * @note Because ZIP DEFLATE streams are not seekable, @c readRange:error:
 * decompresses the entire entry and slices the result.  For workloads that
 * repeatedly read small ranges of large entries, consider calling
 * @c readAll:error: once and caching the resulting @c NSData.
 */
@interface UDPK3ZIPEntrySource : NSObject <UDContentSource> {
    NSURL *_fileURL;
    unsigned long _centralDirectoryPosition;
    uint64_t _uncompressedSize;
}

- (instancetype)initWithFileURL:(NSURL *)fileURL
       centralDirectoryPosition:(unsigned long)centralDirectoryPosition
               uncompressedSize:(uint64_t)uncompressedSize NS_DESIGNATED_INITIALIZER;

@end

NS_ASSUME_NONNULL_END
