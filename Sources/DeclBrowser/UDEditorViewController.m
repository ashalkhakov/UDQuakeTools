#import "UDEditorViewController.h"
#import "idDeclManager.h"

@implementation UDEditorViewController

- (instancetype)initWithDecl:(idDecl *)decl {
    // Load from a specific XIB for the editor if we have one
    self = [super initWithNibName:@"UDEditorViewController" bundle:nil];
    if (self) {
        _decl = decl;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    
    // Populate the text view with the decl's source code
    NSMutableData *buffer = [[NSMutableData alloc] initWithLength:[_decl textLength]+1];
    [_decl text:buffer];
    NSString *sourceCode = [[NSString alloc] initWithData:buffer encoding:NSUTF8StringEncoding];
    if (sourceCode) {
        [self.textView setString:sourceCode];
    }
}

@end
