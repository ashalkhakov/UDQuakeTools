#import <Cocoa/Cocoa.h>

@interface UDNavigatorViewController : NSViewController <NSOutlineViewDataSource, NSOutlineViewDelegate>

@property (nonatomic, weak) IBOutlet NSOutlineView *outlineView;

@end
