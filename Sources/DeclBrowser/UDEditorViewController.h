#import <Cocoa/Cocoa.h>

@class idDecl;

@interface UDEditorViewController : NSViewController

@property (nonatomic, strong, readonly) idDecl *decl;
@property (nonatomic, weak) IBOutlet NSTextView *textView;

- (instancetype)initWithDecl:(idDecl *)decl;

@end
