#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * Custom NSDocumentController that suppresses AppKit's default
 * per-document window creation for file documents, routing them
 * into the workspace tab area instead.
 *
 * For workspace documents (.ideworkspace) the default behavior is
 * preserved (each workspace gets its own window).
 */
@interface UDAppDocumentController : NSDocumentController

@end

NS_ASSUME_NONNULL_END

