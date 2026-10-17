#import <Foundation/Foundation.h>
#import "UDPK3Codec.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * Codec for Doom 3 PK4 archives.
 *
 * PK4 files are standard ZIP archives with a .pk4 extension, identical in
 * binary layout to PK3.  This subclass provides a distinct format identifier
 * and tags every opened archive with @c game = @c doom3 in its metadata.
 *
 * Format identifier: com.udquake.pk4
 */
@interface UDPK4Codec : UDPK3Codec
@end

NS_ASSUME_NONNULL_END
