#import <Foundation/Foundation.h>
#import "UDPAKCodec.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * Codec for Daikatana PAK archives.
 *
 * Daikatana ships PAK files using the same binary layout as Quake I/II
 * ("PACK" magic, 12-byte header, 64-byte directory entries).  This
 * subclass provides a distinct format identifier and tags every opened
 * archive with @c game = @c daikatana in its metadata.
 */
@interface UDDaikatanaPAKCodec : UDPAKCodec
@end

NS_ASSUME_NONNULL_END
