#import "UDWorkspaceWindowController.h"
#import "UDWorkspaceDocument.h"
#import "UDDeclBrowser.h"
#import "UDEditorTabManager.h"
#import "UDWorkspace.h"
#import "UDBaseEditorViewController.h"
#import "UDBaseDocument.h"
#import "UDDeclDocument.h"
#import "UDDeclItem.h"
#import "idDeclManager.h"

@interface UDWorkspaceWindowController ()
@property (nonatomic, strong) UDEditorTabManager *tabManager;
@end

@implementation UDWorkspaceWindowController

- (instancetype)init {
    self = [super initWithWindowNibName:@"UDWorkspaceWindow"];
    return self;
}

- (void)windowDidLoad {
    [super windowDidLoad];
    
    self.declBrowser = [[UDDeclBrowser alloc] initWithWorkspace:self.workspace];
    self.declBrowser.delegate = self;

    [self.declBrowser attachToOutlineViews:self.outlineView searchOutline:self.searchOutlineView];
    [self.declBrowser reset];          // builds the full tree

    self.tabManager = [[UDEditorTabManager alloc] initWithTabView:self.tabView workspace:self.workspace];
}

-(UDWorkspace *)workspace {
    return ((UDWorkspaceDocument *)self.document).workspace;
}

#pragma mark - Undo

// The standard Core Data undo wiring: the window hands the CURRENT tab's
// document undo manager to the responder chain, so Edit > Undo / Redo in
// the main menu operate on the active editor. For decl documents that is
// their private editing context's undo manager — Core Data registers every
// managed object change with it automatically; the forms themselves need no
// undo code at all. (This controller is the window's delegate, wired in
// UDWorkspaceWindow.xib.)
- (NSUndoManager *)windowWillReturnUndoManager:(NSWindow *)window {
    NSUndoManager *undoManager = [self.tabManager selectedEditor].editorDocument.undoManager;
    return undoManager ?: [self.document undoManager];
}

#pragma mark - Saving (File menu)

// The window controller sits in the responder chain BEFORE the workspace
// document, so it owns the File menu save actions — VSCode-style:
//   Save       (Cmd-S)        the current tab's document only
//   Save All   (Opt-Cmd-S)    every dirty open tab
//   Save As…   (Shift-Cmd-S)  the current decl under a new name, as a new decl

- (IBAction)saveDocument:(id)sender {
    UDBaseDocument *document = [self.tabManager selectedEditor].editorDocument;
    if (document == nil) {
        return;
    }

    // Commit any in-flight field editing before saving.
    [self.window makeFirstResponder:nil];

    NSError *error = nil;
    if (![document ud_save:&error]) {
        [self presentError:error];
    }
}

- (IBAction)saveAllDocuments:(id)sender {
    [self.window makeFirstResponder:nil];

    for (UDBaseEditorViewController *editor in [self.tabManager allEditors]) {
        UDBaseDocument *document = editor.editorDocument;
        if (document == nil || !document.isDocumentEdited) {
            continue;
        }
        NSError *error = nil;
        if (![document ud_save:&error]) {
            [self presentError:error];
        }
    }
}

- (IBAction)saveDocumentAs:(id)sender {
    UDBaseEditorViewController *editor = [self.tabManager selectedEditor];
    UDBaseDocument *document = editor.editorDocument;
    if (![document isKindOfClass:[UDDeclDocument class]]) {
        NSBeep();
        return;
    }

    UDDeclDocument *declDocument = (UDDeclDocument *)document;
    if (declDocument.declObject == nil) {
        NSBeep(); // legacy raw-text decl types don't support Save As yet
        return;
    }

    [self.window makeFirstResponder:nil];

    declType_t type = declDocument.declType;
    NSString *typeName = [self.workspace.declManager declNameFromType:type];
    NSString *originalName = declDocument.declObject.name;

    NSString *newName = [self _runSaveAsPromptForTypeName:typeName type:type originalName:originalName];
    if (newName == nil) {
        return; // cancelled
    }

    NSError *error = nil;
    UDDeclBase *newDecl = [declDocument saveAsNewDeclNamed:newName error:&error];
    if (newDecl == nil) {
        [self presentError:error];
        return;
    }

    // The buffer's content now lives in the new decl: re-open the editor on
    // it (the original tab reverted to its last saved state) and refresh the
    // browser tree so the new decl shows up.
    NSString *oldPath = editor.item.path;
    if (oldPath.length > 0) {
        [self.tabManager closeTabForPath:oldPath];
    }
    UDDeclItem *newItem = [[UDDeclItem alloc] initWithType:type declName:newName path:newName];
    [self.tabManager openEditorForWorkspaceItem:newItem];
    [self.declBrowser reset];
}

/// Asks for the new decl name. Returns nil on cancel; keeps asking while the
/// name is empty or already taken.
- (NSString *)_runSaveAsPromptForTypeName:(NSString *)typeName
                                      type:(declType_t)type
                              originalName:(NSString *)originalName {
    NSTextField *nameField = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 280, 24)];
    nameField.stringValue = originalName ?: @"";

    while (YES) {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = [NSString stringWithFormat:@"Save %@ “%@” As", typeName, originalName];
        alert.informativeText = @"The current content is saved as a new decl with this name, in the same file. The original decl keeps its last saved state.";
        [alert addButtonWithTitle:@"Save"];
        [alert addButtonWithTitle:@"Cancel"];
        alert.accessoryView = nameField;
        alert.window.initialFirstResponder = nameField;

        if ([alert runModal] != NSAlertFirstButtonReturn) {
            return nil;
        }

        NSString *candidate = [nameField.stringValue stringByTrimmingCharactersInSet:
                               [NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (candidate.length == 0) {
            continue;
        }
        if ([candidate caseInsensitiveCompare:originalName] == NSOrderedSame ||
            [self.workspace.declManager findDeclWithoutParsing:type name:candidate makeDefault:NO] != nil) {
            NSAlert *taken = [[NSAlert alloc] init];
            taken.messageText = @"Name already in use";
            taken.informativeText = [NSString stringWithFormat:@"A %@ decl named “%@” already exists. Choose a different name.", typeName, candidate];
            [taken runModal];
            continue;
        }
        return candidate;
    }
}

- (BOOL)validateMenuItem:(NSMenuItem *)menuItem {
    SEL action = menuItem.action;

    if (action == @selector(saveDocument:)) {
        UDBaseDocument *document = [self.tabManager selectedEditor].editorDocument;
        return document != nil && document.isDocumentEdited;
    }
    if (action == @selector(saveAllDocuments:)) {
        for (UDBaseEditorViewController *editor in [self.tabManager allEditors]) {
            if (editor.editorDocument.isDocumentEdited) {
                return YES;
            }
        }
        return NO;
    }
    if (action == @selector(saveDocumentAs:)) {
        UDBaseDocument *document = [self.tabManager selectedEditor].editorDocument;
        return [document isKindOfClass:[UDDeclDocument class]] &&
               ((UDDeclDocument *)document).declObject != nil;
    }
    return YES;
}

//
// text editing
//

- (void)textDidChange:(NSNotification *)notification {
#if 0
    id selected = /* currently selected decl */;
    if (selected) {
        [self.document setText:self.textView.string forDecl:selected];
        [self.document updateChangeCount:NSChangeDone];
    }
#endif
}

- (IBAction)nameFilterChanged:(NSSearchField *)sender {
    NSString *name = sender.stringValue;
    
    [self.declBrowser findByName:(name.length ? name : @"*")];
}

- (IBAction)textContainsFilterChanged:(NSSearchField *)sender {
    NSString *name = sender.stringValue;
    
    [self.declBrowser findContaining:name ?: @""];
}

#pragma mark - UDDeclBrowserDelegate

- (void)declBrowser:(UDDeclBrowser *)browser didSelectResource:(UDWorkspaceItem *)resource {
    if (resource.kind == UDWorkspaceItemKindGroup) {
        return;
    }

    [self.tabManager openEditorForWorkspaceItem:resource];
}

- (void)declBrowserDidClearSelection:(UDDeclBrowser *)browser {
    // TODO: do something about it?
}

@end
