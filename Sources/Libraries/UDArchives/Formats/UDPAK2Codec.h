#import <Foundation/Foundation.h>
#import "UDPAKCodec.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * Codec for Quake II PAK archives.
 *
 * The binary layout is identical to the Quake I format (magic "PACK",
 * 12-byte header, 64-byte directory entries).  This subclass provides a
 * distinct format identifier and tags every opened archive with
 * @c game = @c quake2 in its metadata so callers can distinguish it from
 * a plain Quake I archive.
 */
@interface UDPAK2Codec : UDPAKCodec
@end

NS_ASSUME_NONNULL_END
