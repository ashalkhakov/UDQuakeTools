#import "UDImageViewerViewController.h"
#import "UDFileItem.h"
#import "UDImageFileDocument.h"

@interface UDImageViewerViewController ()
@property (nonatomic, weak) IBOutlet NSImageView *imageView;
@end

@implementation UDImageViewerViewController

- (instancetype)init {
    self = [super initWithNibName:@"UDImageViewerView" bundle:nil];
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    UDFileItem *fileItem = self.item != nil && self.item.kind == UDWorkspaceItemKindFile ? (UDFileItem *)self.item : nil;
    if (!fileItem || !fileItem.path) { return; }

    NSURL *url = [NSURL fileURLWithPath:fileItem.path];
    NSError *error = nil;

    self.document = [[UDImageFileDocument alloc] initWithContentsOfURL:url
                                                                ofType:@"public.image"
                                                                 error:&error];
    if (error) {
        NSLog(@"ImageViewerViewController: failed to open %@: %@", url, error);
        return;
    }

    self.imageView.image = self.document.image;
}

@end
