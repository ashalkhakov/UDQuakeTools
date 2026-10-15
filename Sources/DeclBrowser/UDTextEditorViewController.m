#import "UDTextEditorViewController.h"
#import "UDFileItem.h"
#import "UDDeclItem.h"
#import "UDTextFileDocument.h"
#import "UDDeclDocument.h"
#import "UDScriptEvents.h"
#import "UDWorkspace.h"
#import <UDCodeKit/UDCodeKit.h>

@interface UDTextEditorViewController () <UDDiagnosticTextViewDelegate>
@property (nonatomic, weak) IBOutlet NSView *editorHost;
@property (nonatomic, strong) UDEditorSession *session;
@property (nonatomic, strong) UDCodeEditorViewController *editor;

// A script's helpers, as Doom 3's script editor had them: the events of
// script/doom_events.script after a '.', an event's parameters from its '('
// to its ')', and an event's help on Option-click.
@property (nonatomic, strong, nullable) UDScriptEvents *scriptEvents;
@property (nonatomic, copy, nullable) NSArray<NSString *> *completionList;
@property (nonatomic, strong, nullable) UDHoverViewController *toolTip;
@property (nonatomic) NSInteger funcParmToolTipStart;   // after the '(', or -1
@property (nonatomic) unichar typedCharacter;           // what the edit typed, or 0
@property (nonatomic) NSUInteger typedIndex;
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
    // its changes; the editor's edits are undone through its undo manager,
    // from after the filling, which is no edit.
    [self.document setTextView:self.editor.textView];
    self.session.textStorage.textModel.undoManager = self.document.undoManager;
}

- (void)_embedEditorForLanguageOfURL:(nullable NSURL *)url {
    UDCodeDocument *text = [[UDCodeDocument alloc] initWithText:@"" fileURL:url];
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

    if ([text.languageMode.identifier isEqualToString:@"idscript"]) {
        self.scriptEvents = [UDScriptEvents eventsFromFileSystem:self.workspace.fileSystem];
        self.funcParmToolTipStart = -1;
        self.editor.textView.delegate = self;
    }
}

#pragma mark - Script helpers (SyntaxRichEditCtrl's OnChar and its callbacks)

static BOOL UDIsNameCharacter(unichar c) {
    return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '_';
}

/// The name that ends just before @a index (GetNameBeforeCurrentSelection).
- (NSString *)nameBeforeIndex:(NSUInteger)index ofText:(NSString *)text {
    NSUInteger start = index;
    while (start > 0 && UDIsNameCharacter([text characterAtIndex:start - 1])) start--;
    return [text substringWithRange:NSMakeRange(start, index - start)];
}

- (BOOL)textView:(NSTextView *)textView shouldChangeTextInRange:(NSRange)range replacementString:(nullable NSString *)string {
    self.typedCharacter = string.length == 1 ? [string characterAtIndex:0] : (string.length == 0 ? 0x08 : 0);
    self.typedIndex = range.location;
    return YES;
}

- (void)textDidChange:(NSNotification *)notification {
    NSTextView *textView = notification.object;
    unichar c = self.typedCharacter;
    self.typedCharacter = 0;
    if (c == 0) return;

    // The function parameter tool tip goes at its ')', or when the cursor
    // goes back before its '('.
    if (self.funcParmToolTipStart >= 0) {
        if (c == ')' || (c == 0x08 && (NSInteger)textView.selectedRange.location < self.funcParmToolTipStart)) {
            [self hideToolTip];
        }
    }

    if (c == '.' && self.funcParmToolTipStart < 0) {
        NSString *name = [self nameBeforeIndex:self.typedIndex ofText:textView.string];
        if (name.length > 0) {
            self.completionList = [self.scriptEvents membersOfObject:name];
            if (self.completionList.count > 0) {
                [(UDDiagnosticTextView *)textView showCompleteList:nil];
            }
        }
    } else if (c == '(') {
        NSString *name = [self nameBeforeIndex:self.typedIndex ofText:textView.string];
        NSString *parms = name.length > 0 ? [self.scriptEvents functionParmsForName:name] : nil;
        if (parms != nil) {
            [self showToolTip:parms atIndex:self.typedIndex inTextView:textView];
            self.funcParmToolTipStart = (NSInteger)self.typedIndex + 1;
        }
    }
}

- (NSArray<NSString *> *)textView:(NSTextView *)textView
                       completions:(NSArray<NSString *> *)words
               forPartialWordRange:(NSRange)charRange
               indexOfSelectedItem:(NSInteger *)index {
    if (self.completionList == nil) return words;
    NSString *partial = [textView.string substringWithRange:charRange];
    NSMutableArray<NSString *> *matches = [NSMutableArray array];
    for (NSString *member in self.completionList) {
        if (partial.length == 0 || [member rangeOfString:partial options:NSAnchoredSearch | NSCaseInsensitiveSearch].location == 0) {
            [matches addObject:member];
        }
    }
    return matches;
}

// Escape: the tool tip goes; otherwise the events again, after a '.'.
- (void)textViewRequestCompletion:(UDDiagnosticTextView *)textView {
    if (self.toolTip.isShown) {
        [self hideToolTip];
        return;
    }
    NSUInteger at = textView.selectedRange.location;
    NSString *partial = [self nameBeforeIndex:at ofText:textView.string];
    NSUInteger dot = at - partial.length;
    if (dot > 0 && [textView.string characterAtIndex:dot - 1] == '.') {
        self.completionList = [self.scriptEvents membersOfObject:[self nameBeforeIndex:dot - 1 ofText:textView.string]];
    } else {
        self.completionList = nil;
    }
    [textView showCompleteList:nil];
}

// Option-click: the event's help and parameters (OnToolTipNotify).
- (void)textView:(UDDiagnosticTextView *)textView requestTooltipAtIndex:(NSUInteger)characterIndex point:(NSPoint)point {
    NSString *text = textView.string;
    NSUInteger end = characterIndex;
    while (end < text.length && UDIsNameCharacter([text characterAtIndex:end])) end++;
    NSString *name = [self nameBeforeIndex:end ofText:text];
    NSString *tip = name.length > 0 ? [self.scriptEvents toolTipForName:name] : nil;
    if (tip != nil) {
        [self showToolTip:tip atIndex:end - name.length inTextView:textView];
    }
}

- (void)showToolTip:(NSString *)text atIndex:(NSUInteger)index inTextView:(NSTextView *)textView {
    if (self.toolTip == nil) self.toolTip = [[UDHoverViewController alloc] init];
    [self.toolTip showText:text atCharacterIndex:index ofTextView:textView];
}

- (void)hideToolTip {
    [self.toolTip close];
    self.funcParmToolTipStart = -1;
}

@end
