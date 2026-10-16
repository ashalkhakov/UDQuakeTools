#import "UDTextEditorViewController.h"
#import "UDFileItem.h"
#import "UDDeclItem.h"
#import "UDTextFileDocument.h"
#import "UDDeclDocument.h"
#import "UDWorkspace.h"
#import "UDScriptServer.h"
#import "UDWorkspaceWindowController.h"
#import "UDDeclTextChecker.h"
#import "UDDeclManagedObjects.h"
#import <UDCodeKit/UDCodeKit.h>

@interface UDTextEditorViewController () <UDDiagnosticTextViewDelegate>
@property (nonatomic, weak) IBOutlet NSView *editorHost;
@property (nonatomic, strong) UDEditorSession *session;
@property (nonatomic, strong) UDCodeEditorViewController *editor;

// A script's helpers, as Doom 3's script editor had them, from the
// workspace's script language server: the events after a '.', an event's
// parameters from its '(' to its ')', and a name's help on Option-click.
@property (nonatomic) BOOL isScript;
@property (nonatomic, strong, nullable) LSPClient *scriptServer;
@property (nonatomic, copy, nullable) NSURL *scriptURL;
@property (nonatomic, copy, nullable) NSArray<NSString *> *completionList;
// What each completion inserts, by its label: the server's snippet, as placeholders.
@property (nonatomic, copy, nullable) NSDictionary<NSString *, NSString *> *completionInsertTexts;
@property (nonatomic) NSUInteger toolTipIndex;          // where the requested tool tip goes
@property (nonatomic) NSUInteger completionWordStart;   // where the word asked about begins
@property (nonatomic) BOOL completionAsked;             // a completion request is out
@property (nonatomic) BOOL hoverShowing;
// What the server is being asked for is still wanted when it answers: the
// parameters until their ')' (typed before the answer, say), the hover
// until the mouse leaves the name.
@property (nonatomic) BOOL parmsWanted;
@property (nonatomic) BOOL hoverWanted;                // the tool tip is the mouse's, not the parameters' 
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
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [_session close];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    
    if (self.item == nil) {
        return;
    }

    // The language a file's extension names; a decl's, the decl grammar,
    // whatever its file is called.
    NSURL *languageURL = nil;
    UDLanguageMode *languageMode = nil;
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
            languageMode = [[UDLanguageModeRegistry sharedRegistry] modeForIdentifier:@"iddecl"];

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

    [self _embedEditorForURL:languageURL languageMode:languageMode];

    // The document fills the editor's text view, saves from it, and counts
    // its changes; the editor's edits are undone through its undo manager,
    // from after the filling, which is no edit.
    [self.document setTextView:self.editor.textView];
    self.session.textStorage.textModel.undoManager = self.document.undoManager;
    if (self.item.kind == UDWorkspaceItemKindDecl) {
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_declTextDidChange:)
                                                     name:NSTextDidChangeNotification object:self.editor.textView];
    }

    // A script's tab opens it on the workspace's language server, by its
    // path in the file system, once its text is in.
    if (self.isScript && self.item.kind == UDWorkspaceItemKindFile) {
        self.scriptServer = [UDScriptServer clientForWorkspace:self.workspace];
        self.scriptURL = [UDScriptServer URLForPath:self.item.path];
        if (self.scriptServer != nil) {
            [self.session startLanguageServerWithClient:self.scriptServer documentURL:self.scriptURL];
        }
    }
}

- (NSTextView *)editorTextView {
    return self.editor.textView;
}

- (UDDiagnosticStore *)diagnosticStore {
    return self.session.document.diagnosticStore;
}

#pragma mark - Jump to Definition

- (IBAction)jumpToDefinition:(id)sender {
    UDLSPCoordinator *server = self.session.lspCoordinator;
    if (server == nil || [server definitionAtIndex:self.editor.textView.selectedRange.location
                                            target:self action:@selector(_definitionDidArrive:)] == 0) {
        NSBeep();
    }
}

- (BOOL)validateMenuItem:(NSMenuItem *)menuItem {
    if (menuItem.action == @selector(jumpToDefinition:)) {
        return self.session.lspCoordinator != nil;
    }
    if (menuItem.action == @selector(testDecl:)) {
        return self.item.kind == UDWorkspaceItemKindDecl && self.diagnosticStore != nil;
    }
    return YES;
}

#pragma mark - Test (DialogDeclEditor's)

static UDDiagnosticSource const UDDiagnosticSourceDeclTest = @"test";

- (IBAction)testDecl:(id)sender {
    if (self.item.kind != UDWorkspaceItemKindDecl || self.diagnosticStore == nil) {
        NSBeep();
        return;
    }
    // TestDecl's braces, and the lexer as the decl manager has it; then, as
    // OnBnClickedTest has the decl parse its new text, the type's parser.
    NSString *text = self.editor.textView.string;
    NSMutableArray<UDDeclTextProblem *> *problems =
        [[UDDeclTextChecker problemsInDeclText:text fileSystem:self.workspace.fileSystem] mutableCopy];
    BOOL bracesHold = YES;
    for (UDDeclTextProblem *problem in problems) {
        if (problem.isError) bracesHold = NO;
    }
    UDDeclBase *decl = [self.document isKindOfClass:[UDDeclDocument class]] ? ((UDDeclDocument *)self.document).declObject : nil;
    if (bracesHold && decl != nil) {
        [problems addObjectsFromArray:[[decl class] ud_problemsParsingText:text name:decl.name
                                                               declManager:self.workspace.declManager]];
    }

    NSMutableArray<UDDiagnosticItem *> *items = [NSMutableArray array];
    for (UDDeclTextProblem *problem in problems) {
        [items addObject:[[UDDiagnosticItem alloc] initWithLine:problem.line column:0 message:problem.message
                                                       severity:problem.isError ? UDDiagnosticSeverityError : UDDiagnosticSeverityWarning
                                                         source:UDDiagnosticSourceDeclTest]];
    }
    [self.diagnosticStore setDiagnostics:items forSource:UDDiagnosticSourceDeclTest];
}

/// What a Test found is the text's as it was: an edit takes it away.
- (void)_declTextDidChange:(NSNotification *)notification {
    [self.diagnosticStore clearSource:UDDiagnosticSourceDeclTest];
}

/// The definition's place: the first location, in its file's tab.
- (void)_definitionDidArrive:(LSPResponse *)response {
    id result = response.result;
    NSDictionary *location = [result isKindOfClass:[NSArray class]] ? [result firstObject] : result;
    if (![location isKindOfClass:[NSDictionary class]]) {
        NSBeep();
        return;
    }
    NSString *path = [UDScriptServer pathForURL:[NSURL URLWithString:location[@"uri"] ?: @""]];
    NSDictionary *start = location[@"range"][@"start"], *end = location[@"range"][@"end"];
    UDWorkspaceWindowController *windowController = self.view.window.windowController;
    if (path == nil || ![windowController isKindOfClass:[UDWorkspaceWindowController class]]) {
        NSBeep();
        return;
    }
    [windowController openFileAtPath:path
                                line:[start[@"line"] integerValue]
                           character:[start[@"character"] integerValue]
                              length:[end[@"character"] integerValue] - [start[@"character"] integerValue]];
}

- (void)selectLine:(NSInteger)line character:(NSInteger)character length:(NSInteger)length {
    NSTextView *textView = self.editor.textView;
    NSString *text = textView.string;
    NSUInteger index = 0;
    for (NSInteger i = 0; i < line && index < text.length; i++) {
        NSRange newline = [text rangeOfString:@"\n" options:NSLiteralSearch range:NSMakeRange(index, text.length - index)];
        if (newline.location == NSNotFound) break;
        index = NSMaxRange(newline);
    }
    NSRange range = NSMakeRange(MIN(index + (NSUInteger)MAX(character, 0), text.length), 0);
    range.length = MIN((NSUInteger)MAX(length, 0), text.length - range.location);
    [textView setSelectedRange:range];
    [textView scrollRangeToVisible:range];
    [textView.window makeFirstResponder:textView];
}

- (void)_embedEditorForURL:(nullable NSURL *)url languageMode:(nullable UDLanguageMode *)languageMode {
    UDCodeDocument *text = [[UDCodeDocument alloc] initWithText:@"" fileURL:url languageMode:languageMode];
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
        self.isScript = YES;
        self.funcParmToolTipStart = -1;
        self.editor.textView.delegate = self;
    }
}

#pragma mark - Script helpers (SyntaxRichEditCtrl's OnChar, asking the server)

static BOOL UDIsNameCharacter(unichar c) {
    return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '_';
}

/// The name that ends just before @a index (GetNameBeforeCurrentSelection).
- (NSString *)nameBeforeIndex:(NSUInteger)index ofText:(NSString *)text {
    NSUInteger start = index;
    while (start > 0 && UDIsNameCharacter([text characterAtIndex:start - 1])) start--;
    return [text substringWithRange:NSMakeRange(start, index - start)];
}

/// The server has the text as it is now: the edits LSPClient keeps until
/// the run loop idles go before a request about them.
- (void)sendPendingEdits {
    [self.scriptServer documentDidChange:self.scriptURL];
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
    if (self.funcParmToolTipStart >= 0 || self.parmsWanted) {
        NSInteger start = self.funcParmToolTipStart >= 0 ? self.funcParmToolTipStart : (NSInteger)self.toolTipIndex + 1;
        if (c == ')' || (c == 0x08 && (NSInteger)textView.selectedRange.location < start)) {
            [self hideToolTip];
        }
    }

    if (c == '.' && self.funcParmToolTipStart < 0) {
        if ([self nameBeforeIndex:self.typedIndex ofText:textView.string].length > 0) {
            [self requestCompletionAtIndex:self.typedIndex + 1];
        }
    } else if (UDIsNameCharacter(c)) {
        // A name being typed: what it can be, as Xcode offers it (the list,
        // once shown, narrows as the name goes on).
        NSString *name = [self nameBeforeIndex:self.typedIndex + 1 ofText:textView.string];
        unichar first = [name characterAtIndex:0];
        if (!(first >= '0' && first <= '9') && !self.completionAsked &&
            ![(UDDiagnosticTextView *)textView isShowingCompletions]) {
            [self requestCompletionAtIndex:self.typedIndex + 1];
        }
    } else if (c == '(') {
        [self sendPendingEdits];
        UDPosition p = [self.session.textStorage.textModel getPositionAt:(NSInteger)self.typedIndex + 1];
        self.toolTipIndex = self.typedIndex;
        self.parmsWanted = YES;
        [self.scriptServer sendRequest:@"textDocument/signatureHelp"
                                params:@{ @"textDocument": @{ @"uri": self.scriptURL.absoluteString },
                                          @"position": @{ @"line": @(p.line - 1), @"character": @(p.column - 1) } }
                                target:self action:@selector(_signatureHelpDidArrive:)];
    }
}

- (void)_signatureHelpDidArrive:(LSPResponse *)response {
    NSDictionary *help = [response.result isKindOfClass:[NSDictionary class]] ? response.result : nil;
    NSString *parms = [[help[@"signatures"] firstObject] objectForKey:@"label"];
    if (![parms isKindOfClass:[NSString class]] || !self.parmsWanted) return;
    [self showToolTip:parms atIndex:self.toolTipIndex inTextView:self.editor.textView];
    self.hoverShowing = NO;
    self.funcParmToolTipStart = (NSInteger)self.toolTipIndex + 1;
}

- (void)requestCompletionAtIndex:(NSUInteger)index {
    NSString *text = self.editor.textView.string;
    self.completionWordStart = index - [self nameBeforeIndex:index ofText:text].length;
    [self sendPendingEdits];
    self.completionAsked = [self.session.lspCoordinator completionAtIndex:index target:self
                                                                   action:@selector(_completionDidArrive:)] != 0;
}

- (void)_completionDidArrive:(LSPResponse *)response {
    self.completionAsked = NO;
    // An answer that comes after the caret left the word (typing on past
    // it: "wait(") is no longer wanted.
    NSString *text = self.editor.textView.string;
    NSUInteger caret = self.editor.textView.selectedRange.location;
    if (caret < self.completionWordStart || caret > text.length ||
        [self nameBeforeIndex:caret ofText:text].length != caret - self.completionWordStart) {
        return;
    }
    NSMutableArray<NSString *> *labels = [NSMutableArray array];
    NSMutableDictionary<NSString *, NSString *> *insertTexts = [NSMutableDictionary dictionary];
    for (LSPCompletionItem *item in response.result) {
        [labels addObject:item.label];
        NSString *insertText = [item.insertText isKindOfClass:[NSString class]] ? item.insertText : nil;
        if (insertText.length > 0) {
            BOOL snippet = [[(id)item.insertTextFormat description] integerValue] == 2;
            insertTexts[item.label] = snippet ? UDPlaceholderTextFromSnippet(insertText) : insertText;
        }
    }
    self.completionList = labels;
    self.completionInsertTexts = insertTexts;
    if (labels.count > 0) {
        [(UDDiagnosticTextView *)self.editor.textView showCompleteList:nil];
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

// A call, its arguments placeholders to fill in (Tab between them).
- (NSString *)textView:(UDDiagnosticTextView *)textView insertTextForCompletion:(NSString *)completion {
    return self.completionInsertTexts[completion];
}

// Escape: the tool tip goes; otherwise what the server offers here (the
// events, after a '.').
- (void)textViewRequestCompletion:(UDDiagnosticTextView *)textView {
    if (self.toolTip.isShown) {
        [self hideToolTip];
        return;
    }
    [self requestCompletionAtIndex:textView.selectedRange.location];
}

// The mouse resting on a name: its help (OnToolTipNotify), an event's or
// where it is declared; not over a function's parameters being typed.
- (void)textView:(UDDiagnosticTextView *)textView requestTooltipAtIndex:(NSUInteger)characterIndex point:(NSPoint)point {
    if (self.funcParmToolTipStart >= 0) return;
    NSString *text = textView.string;
    NSUInteger end = characterIndex;
    while (end < text.length && UDIsNameCharacter([text characterAtIndex:end])) end++;
    NSString *name = [self nameBeforeIndex:end ofText:text];
    if (name.length == 0) return;
    self.toolTipIndex = end - name.length;
    self.hoverWanted = YES;
    [self sendPendingEdits];
    [self.session.lspCoordinator hoverAtIndex:characterIndex target:self action:@selector(_hoverDidArrive:)];
}

- (void)_hoverDidArrive:(LSPResponse *)response {
    id contents = [response.result isKindOfClass:[NSDictionary class]] ? response.result[@"contents"] : nil;
    NSString *tip = [contents isKindOfClass:[NSDictionary class]] ? contents[@"value"] : contents;
    if ([tip isKindOfClass:[NSString class]] && tip.length > 0 && self.hoverWanted &&
        self.funcParmToolTipStart < 0 && !self.parmsWanted) {
        [self showToolTip:tip atIndex:self.toolTipIndex inTextView:self.editor.textView];
        self.hoverShowing = YES;
    }
}

// The mouse left the name: its help goes (the parameters' stays).
- (void)textViewHoverDidEnd:(UDDiagnosticTextView *)textView {
    self.hoverWanted = NO;
    if (self.hoverShowing) [self hideToolTip];
}

// The caret leaving the call (a click elsewhere, before its '(', past its
// ')' or on another line): its parameters go.
- (void)textViewDidChangeSelection:(NSNotification *)notification {
    if (self.funcParmToolTipStart < 0) return;
    NSTextView *textView = notification.object;
    NSUInteger caret = textView.selectedRange.location, start = (NSUInteger)self.funcParmToolTipStart;
    NSString *text = textView.string;
    if (caret < start || caret > text.length) {
        [self hideToolTip];
        return;
    }
    NSInteger depth = 1;                        // inside the call's '('
    for (NSUInteger i = start; i < caret; i++) {
        unichar c = [text characterAtIndex:i];
        if (c == '\n' || (c == ')' && --depth == 0)) {
            [self hideToolTip];
            return;
        }
        if (c == '(') depth++;
    }
}

- (void)showToolTip:(NSString *)text atIndex:(NSUInteger)index inTextView:(NSTextView *)textView {
    if (self.toolTip == nil) self.toolTip = [[UDHoverViewController alloc] init];
    [self.toolTip showText:text atCharacterIndex:index ofTextView:textView];
}

- (void)hideToolTip {
    [self.toolTip close];
    self.funcParmToolTipStart = -1;
    self.hoverShowing = NO;
    self.parmsWanted = NO;
}

@end
