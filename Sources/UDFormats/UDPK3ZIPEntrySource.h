#import <Foundation/Foundation.h>
#import "UDContentSource.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * UDContentSource that reads a single entry from a ZIP archive using libzip.
 *
 * The archive file is opened and closed for every read so that multiple
 * sources can coexist without keeping the file descriptor open permanently.
 * Both stored (method 0) and deflate-compressed (method 8) entries are
 * supported transparently by libzip.
 *
 * @note Because ZIP DEFLATE streams are not seekable, @c readRange:error:
 * decompresses the entire entry and slices the result.  For workloads that
 * repeatedly read small ranges of large entries, consider calling
 * @c readAll:error: once and caching the resulting @c NSData.
 */
@interface UDPK3ZIPEntrySource : NSObject <UDContentSource> {
    NSURL *_fileURL;
    uint64_t _entryIndex;
    uint64_t _uncompressedSize;
}

- (instancetype)initWithFileURL:(NSURL *)fileURL
                     entryIndex:(uint64_t)entryIndex
               uncompressedSize:(uint64_t)uncompressedSize NS_DESIGNATED_INITIALIZER;

@end

NS_ASSUME_NONNULL_END
