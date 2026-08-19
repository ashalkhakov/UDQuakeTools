#import "UDTextEditorViewController.h"
#import "UDFileItem.h"
#import "UDDeclItem.h"
#import "UDTextFileDocument.h"
#import "UDDeclDocument.h"

@interface UDTextEditorViewController ()
@property (nonatomic, weak) IBOutlet NSScrollView *scrollView;
@property (nonatomic, weak) IBOutlet NSTextView   *textView;
@end

@implementation UDTextEditorViewController

- (instancetype)init {
    self = [super initWithNibName:@"UDTextEditorView" bundle:nil];
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    
    if (self.item == nil) {
        return;
    }

    switch (self.item.kind) {
        case UDWorkspaceItemKindFile: {
            UDFileItem *fileItem = (UDFileItem *)self.item;
            if (!fileItem || !fileItem.path) {
                return;
            }
            
            NSError *error = nil;
            
            // Open or create the backing document.
            self.document = [[UDTextFileDocument alloc] initWithPath:fileItem.path inWorkspace:self.workspace error:&error];
            if (error) {
                NSLog(@"UDTextEditorViewController: failed to open %@: %@", fileItem.path, error);
                return;
            }

            if (![self.document readFromURL:[NSURL URLWithString:@"http://localhost/unused.txt"] ofType:@"" error:&error]) {
                NSLog(@"UDTextEditorViewController: failed to open %@: %@", fileItem.path, error);
                return;
            }
            break;
        }
        case UDWorkspaceItemKindDecl: {
            UDDeclItem *declItem = (UDDeclItem *)self.item;
            NSError *error = nil;

            self.document = [[UDDeclDocument alloc] initWithType:declItem.type name:declItem.declName inWorkspace:self.workspace error:&error];
            if (self.document == nil) {
                NSLog(@"UDTextEditorViewController: failed to open decl of type %@ name %@: %@", [self.workspace.declManager declTypeName:declItem.type], declItem.declName, error);
                return;
            }

            if (![self.document readFromURL:[NSURL URLWithString:@"http://localhost/unused.txt"] ofType:@"" error:&error]) {
                NSLog(@"UDTextEditorViewController: failed to read decl of type %@ name %@: %@", [self.workspace.declManager declTypeName:declItem.type], declItem.declName, error);
            }
            break;
        }
        default:
            return; // should never happen
    }

    // Give the document a reference to our text view so it can manage undo.
    [self.document setTextView:self.textView];
}

@end
