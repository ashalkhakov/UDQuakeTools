#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

/** NSDocument subclass for image files. */
@interface UDImageFileDocument : NSDocument

@property (nonatomic, strong, nullable) NSImage *image;

@end

NS_ASSUME_NONNULL_END
