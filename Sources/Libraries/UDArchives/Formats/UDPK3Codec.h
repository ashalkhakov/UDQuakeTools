#import <Foundation/Foundation.h>
#import "UDArchiveCodec.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * Codec for Quake III Arena PK3 archives.
 *
 * PK3 files are standard ZIP archives with a .pk3 extension.  Entry data
 * may be stored uncompressed (method 0) or deflate-compressed (method 8).
 * Reading goes through the vendored minizip unzip.c (UDPK3ZIPEntrySource)
 * and writing through UDZipWriter; both need only zlib.
 *
 * Format identifier: com.udquake.pk3
 */
@interface UDPK3Codec : NSObject <UDArchiveCodec>
@end

NS_ASSUME_NONNULL_END
