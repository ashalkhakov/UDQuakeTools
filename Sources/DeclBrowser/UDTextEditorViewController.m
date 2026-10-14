#import "UDTextEditorViewController.h"
#import "UDFileItem.h"
#import "UDDeclItem.h"
#import "UDTextFileDocument.h"
#import "UDDeclDocument.h"
#import <UDCodeKit/UDCodeKit.h>

@interface UDTextEditorViewController ()
@property (nonatomic, weak) IBOutlet NSView *editorHost;
@property (nonatomic, strong) UDEditorSession *session;
@property (nonatomic, strong) UDCodeEditorViewController *editor;
@end

@implementation UDTextEditorViewController

- (instancetype)init {
    self = [super initWithNibName:@"UDTextEditorView" bundle:[NSBundle bundleForClass:[UDTextEditorViewController class]]];
    return self;
}

- (void)dealloc {
    [_session close];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    
    if (self.item == nil) {
        return;
    }

    // The language a file's extension names; a decl's text is plain.
    NSURL *languageURL = nil;
    switch (self.item.kind) {
        case UDWorkspaceItemKindFile: {
            UDFileItem *fileItem = (UDFileItem *)self.item;
            if (!fileItem || !fileItem.path) {
                return;
            }
            languageURL = [NSURL fileURLWithPath:fileItem.path];
            
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

    [self _embedEditorForLanguageOfURL:languageURL];

    // The document fills the editor's text view, saves from it, and counts
    // its changes; the editor's edits are undone through its undo manager.
    [self.document setTextView:self.editor.textView];
}

- (void)_embedEditorForLanguageOfURL:(nullable NSURL *)url {
    UDCodeDocument *text = [[UDCodeDocument alloc] initWithText:@"" fileURL:url];
    text.textModel.undoManager = self.document.undoManager;
    self.session = [[UDEditorSession alloc] initWithDocument:text];

    // The editor's view first, so its layout manager is attached before the
    // session's first parse.
    self.editor = [[UDCodeEditorViewController alloc] initWithTextStorage:self.session.textStorage];
    [self.editor configureForLanguageMode:text.languageMode];
    self.editor.view.frame = self.editorHost.bounds;
    self.editor.view.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [self.editorHost addSubview:self.editor.view];

#ifdef __APPLE__
    NSAppearanceName appearance = [NSApp.effectiveAppearance
        bestMatchFromAppearancesWithNames:@[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]];
    BOOL dark = [appearance isEqualToString:NSAppearanceNameDarkAqua];
#else
    BOOL dark = NO;          // GNUstep: no appearances; the light theme
#endif
    [self.session activateWithTheme:[[TreeSitterTheme alloc] initWithMode:dark]];
}

@end
