#import "UDDeclEditorViewController.h"
#import "UDDeclItem.h"
#import "UDDeclDocument.h"
#import "UDDeclManagedObjects.h"
#import "UDWorkspace.h"
#import "idDeclManager.h"
#import <UDCodeKit/UDCodeKit.h>

@interface UDDeclEditorViewController ()
@property (nonatomic, strong, readwrite, nullable) UDDiagnosticStore *diagnosticStore;
@property (nonatomic, strong) NSMutableDictionary<NSString *, id> *diagnosticTargets;
// The source, while it is up: its session and editor, the text it was shown
// with, and the editor's views it covers.
@property (nonatomic, strong, nullable) UDEditorSession *sourceSession;
@property (nonatomic, strong, nullable) UDCodeEditorViewController *sourceEditor;
@property (nonatomic, copy, nullable) NSString *shownSourceText;
@property (nonatomic, copy, nullable) NSArray<NSView *> *coveredViews;
@end

static NSString *UDDiagnosticKey(UDDiagnosticItem *diagnostic) {
    return [NSString stringWithFormat:@"%ld:%@", (long)diagnostic.line, diagnostic.message];
}

@implementation UDDeclEditorViewController

- (void)setDocument:(UDDeclDocument *)document {
    _document = document;
    // No `viewLoaded` check: GNUstep's NSViewController doesn't have it, and
    // none is needed — the objectController outlet is nil until the view nib
    // has loaded (reading it does NOT trigger loading), so this assignment is
    // a harmless no-op before then; -viewDidLoad sets the content itself.
    if (document != nil) {
        self.objectController.content = document.declObject;
    }
}

- (__kindof UDDeclBase *)declObject {
    return self.document.declObject;
}

- (NSManagedObjectContext *)editingContext {
    return self.document.editingContext;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    if (self.item == nil || self.item.kind != UDWorkspaceItemKindDecl) {
        return;
    }

    UDDeclItem *declItem = (UDDeclItem *)self.item;
    NSError *error = nil;

    self.document = [[UDDeclDocument alloc] initWithType:declItem.type name:declItem.declName inWorkspace:self.workspace error:&error];
    if (self.document == nil) {
        NSLog(@"%@: failed to open decl of type %@ name %@: %@", [self class], [self.workspace.declManager declTypeName:declItem.type], declItem.declName, error);
        return;
    }

    if (![self.document readFromURL:[NSURL URLWithString:@"http://localhost/unused.txt"] ofType:@"" error:&error]) {
        NSLog(@"%@: failed to read decl of type %@ name %@: %@", [self class], [self.workspace.declManager declTypeName:declItem.type], declItem.declName, error);
    }

    self.objectController.content = self.declObject;
    self.diagnosticStore = [[UDDiagnosticStore alloc] init];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_editingContextDidChange:)
                                                 name:NSManagedObjectContextObjectsDidChangeNotification
                                               object:self.editingContext];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_editingContextDidSave:)
                                                 name:NSManagedObjectContextDidSaveNotification
                                               object:self.editingContext];
    [self declDidLoad];
    [self editingContextDidChange];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)_editingContextDidChange:(NSNotification *)notification {
    [self editingContextDidChange];
    if (self.showsSource) [self _refreshUneditedSource];
}

#pragma mark - The source

/// Saved from the source: what it shows is the decl now.
- (void)_editingContextDidSave:(NSNotification *)notification {
    if (self.showsSource) self.shownSourceText = self.sourceEditor.textView.string;
}

- (NSTextView *)sourceTextView {
    return self.sourceEditor.textView;
}

- (nullable NSString *)_currentDeclText:(NSError **)error {
    NSData *text = [self.declObject ud_currentText:error];
    if (text == nil) return nil;
    return [self.document editorTextFromFileText:[[NSString alloc] initWithData:text encoding:NSUTF8StringEncoding] ?: @""];
}

- (void)setShowsSource:(BOOL)showsSource {
    if (showsSource == _showsSource || self.declObject == nil) return;
    if (showsSource) {
        NSError *error = nil;
        NSString *text = [self _currentDeclText:&error];
        if (text == nil) {
            [self presentError:error];
            return;
        }
        [self _showSourceText:text];
    } else {
        if (![self _readSourceIntoDecl]) return;
        [self _hideSource];
    }
    _showsSource = showsSource;
}

- (void)_showSourceText:(NSString *)text {
    UDCodeDocument *code = [[UDCodeDocument alloc] initWithText:@"" fileURL:nil
        languageMode:[[UDLanguageModeRegistry sharedRegistry] modeForIdentifier:@"iddecl"]];
    self.sourceSession = [[UDEditorSession alloc] initWithDocument:code];
    self.sourceEditor = [[UDCodeEditorViewController alloc] initWithTextStorage:self.sourceSession.textStorage];
    [self.sourceEditor configureForLanguageMode:code.languageMode];

    self.coveredViews = self.view.subviews;
    for (NSView *view in self.coveredViews) view.hidden = YES;
    self.sourceEditor.view.frame = self.view.bounds;
    self.sourceEditor.view.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [self.view addSubview:self.sourceEditor.view];
#ifdef __APPLE__
    NSAppearanceName appearance = [NSApp.effectiveAppearance
        bestMatchFromAppearancesWithNames:@[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]];
    BOOL dark = [appearance isEqualToString:NSAppearanceNameDarkAqua];
#else
    BOOL dark = NO;          // GNUstep: no appearances; the light theme
#endif
    [self.sourceSession activateWithTheme:[[TreeSitterTheme alloc] initWithMode:dark]];

    // The document fills the text view, counts its edits, and saves from it
    // while it is up; its edits go on the document's undo stack.
    self.shownSourceText = text;
    self.document.textContent = text;
    [self.document setTextView:self.sourceEditor.textView];
    self.sourceSession.textStorage.textModel.undoManager = self.document.undoManager;
    [self.view.window makeFirstResponder:self.sourceEditor.textView];
}

/// The text read into the decl, when it was edited: one undoable edit,
/// which takes the text's own edits' place on the undo stack.
- (BOOL)_readSourceIntoDecl {
    NSString *text = self.sourceEditor.textView.string;
    if ([text isEqualToString:self.shownSourceText]) return YES;

    NSUndoManager *undoManager = self.document.undoManager;
    NSData *data = [[self.document fileTextFromEditorText:text] dataUsingEncoding:NSUTF8StringEncoding];
    // Text that does not parse changes nothing: the source stays up.
    NSError *error = nil;
    if ([[self.declObject class] ud_parseValuesFromText:data name:self.declObject.name fileName:nil lineNum:1
                                              fileSystem:self.workspace.fileSystem error:&error] == nil && error != nil) {
        [self presentError:error];
        return NO;
    }
    // The context's changes go on the undo stack as it processes them:
    // inside the group, so that they are one undo.
    [undoManager beginUndoGrouping];
    [self.declObject ud_applyText:data error:NULL];
    [self.editingContext processPendingChanges];
    [undoManager setActionName:@"Edit Source"];
    [undoManager endUndoGrouping];
    [undoManager removeAllActionsWithTarget:self.sourceSession.textStorage.textModel];
    [undoManager removeAllActionsWithTarget:self.sourceEditor.textView.textStorage];
    return YES;
}

- (void)_hideSource {
    [self.document setTextView:nil];
    [self.document.undoManager removeAllActionsWithTarget:self.sourceSession.textStorage.textModel];
    [self.sourceEditor.view removeFromSuperview];
    for (NSView *view in self.coveredViews) view.hidden = NO;
    [self.sourceSession close];
    self.sourceSession = nil;
    self.sourceEditor = nil;
    self.coveredViews = nil;
    self.shownSourceText = nil;
}

/// An undo past the text's edits, back into the editor's, or a save: the
/// text shows the decl as it is now, if it is as it was shown.
- (void)_refreshUneditedSource {
    NSTextView *textView = self.sourceEditor.textView;
    if (textView == nil || ![textView.string isEqualToString:self.shownSourceText]) return;
    NSString *text = [self _currentDeclText:NULL];
    if (text == nil || [text isEqualToString:self.shownSourceText]) return;
    NSUndoManager *undoManager = self.document.undoManager;
    [undoManager disableUndoRegistration];
    [textView.textStorage replaceCharactersInRange:NSMakeRange(0, textView.textStorage.length) withString:text];
    [undoManager enableUndoRegistration];
    self.shownSourceText = text;
}

- (NSInteger)lineOfDeclTextContaining:(NSString *)text {
    NSData *source = self.declObject.sourceText;
    NSString *declText = source != nil ? [[NSString alloc] initWithData:source encoding:NSUTF8StringEncoding] : nil;
    NSRange found = [declText rangeOfString:text options:NSCaseInsensitiveSearch];
    if (found.location == NSNotFound) return 1;
    NSInteger line = 1;
    for (NSUInteger i = 0; i < found.location; i++) {
        if ([declText characterAtIndex:i] == '\n') line++;
    }
    return line;
}

- (void)declDidLoad {
}

- (void)editingContextDidChange {
}

- (void)revealDiagnostic:(UDDiagnosticItem *)diagnostic {
}

- (void)setTarget:(id)target forDiagnostic:(UDDiagnosticItem *)diagnostic {
    if (self.diagnosticTargets == nil) self.diagnosticTargets = [NSMutableDictionary dictionary];
    self.diagnosticTargets[UDDiagnosticKey(diagnostic)] = target;
}

- (id)targetForDiagnostic:(UDDiagnosticItem *)diagnostic {
    return self.diagnosticTargets[UDDiagnosticKey(diagnostic)];
}

- (void)removeDiagnosticTargets {
    [self.diagnosticTargets removeAllObjects];
}

@end
