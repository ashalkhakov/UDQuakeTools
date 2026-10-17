#import "UDBaseEditorViewController.h"
@class UDImageFileDocument;

NS_ASSUME_NONNULL_BEGIN

/** Editor view controller for image files. */
@interface UDImageViewerViewController : UDBaseEditorViewController

@property (nonatomic, strong, nullable) UDImageFileDocument *document;

@end

NS_ASSUME_NONNULL_END
