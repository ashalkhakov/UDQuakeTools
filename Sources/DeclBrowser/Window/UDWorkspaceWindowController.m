#import "UDWorkspaceWindowController.h"
#import "UDDeclManagedObjects.h"
#import "UDPDAEditorViewController.h"
#import "UDDeclEditorViewController.h"
#import "UDWorkspaceDocument.h"
#import "UDDeclBrowser.h"
#import "UDEditorTabManager.h"
#import "UDWorkspace.h"
#import "UDBaseEditorViewController.h"
#import "UDBaseDocument.h"
#import "UDDeclDocument.h"
#import "UDDeclItem.h"
#import "UDWorkspaceSettingsWindowController.h"
#import "UDNewDeclWindowController.h"
#import "UDWorkspaceOpeningController.h"
#import <UDCodeKit/UDTabBarView.h>
#import <UDCodeKit/UDErrorsViewController.h>
#import "UDTextPromptPanel.h"
#import "UDTextEditorViewController.h"
#import "UDFileItem.h"
#import "UDScriptServer.h"
#import "idDeclManager.h"

@interface UDWorkspaceWindowController ()
@property (nonatomic, strong) UDEditorTabManager *tabManager;
@property (nonatomic, weak) IBOutlet NSView *issuesHost;
@property (nonatomic, strong) UDErrorsViewController *issuesNavigator;
@property (nonatomic, strong, nullable) UDWorkspaceSettingsWindowController *settingsController;
// "Opening…", while the workspace restarts with new settings.
@property (nonatomic, strong, nullable) UDWorkspaceOpeningController *openingController;
@property (nonatomic, readonly, getter=isRestarting) BOOL restarting;
@end

@implementation UDWorkspaceWindowController

- (instancetype)init {
    self = [super initWithWindowNibName:@"UDWorkspaceWindow"];
    return self;
}

- (void)windowDidLoad {
    [super windowDidLoad];
    
    // GNUstep: harden every scroll view in the window against the
    // scroller-autohide layout recursion (see UDBaseEditorViewController.h).
    [self.window.contentView ud_disableScrollerAutohideRecursively];

    self.declBrowser = [[UDDeclBrowser alloc] initWithWorkspace:self.workspace];
    self.declBrowser.delegate = self;

    [self.declBrowser attachToOutlineViews:self.outlineView searchOutline:self.searchOutlineView];
    [self.declBrowser reset];          // builds the full tree

    // Xcode-like editor tabs: both the UDTabBarView strip and the tabless
    // NSTabView below it live in UDWorkspaceWindow.xib; the tab manager
    // drives them as one control (dirty dot, close/pin buttons,
    // drag-to-reorder, horizontal scrolling).
    self.tabManager = [[UDEditorTabManager alloc] initWithTabView:self.tabView
                                                            tabBar:self.tabBarView
                                                         workspace:self.workspace];

    // The Issues tab: UDCodeKit's navigator (UDCode's too), listing the open
    // tabs' diagnostics; a click goes to one.
    self.issuesNavigator = [[UDErrorsViewController alloc] init];
    self.issuesNavigator.delegate = self;
    self.issuesNavigator.view.frame = self.issuesHost.bounds;
    self.issuesNavigator.view.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [self.issuesHost addSubview:self.issuesNavigator.view];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_editorsDidChange:)
                                                 name:UDEditorTabManagerEditorsDidChangeNotification
                                               object:self.tabManager];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_selectedEditorDidChange:)
                                                 name:UDEditorTabManagerSelectionDidChangeNotification
                                               object:self.tabManager];
    [self _selectedEditorDidChange:nil];
}

#pragma mark - Editor | Source

/// The switch is the selected tab's: a structured editor's, shown as it is.
- (void)_selectedEditorDidChange:(NSNotification *)notification {
    UDBaseEditorViewController *editor = [self.tabManager selectedEditor];
    BOOL structured = [editor isKindOfClass:[UDDeclEditorViewController class]];
    self.representationControl.enabled = structured;
    self.representationControl.selectedSegment = structured && ((UDDeclEditorViewController *)editor).showsSource ? 1 : 0;
}

- (IBAction)showRepresentation:(id)sender {
    UDBaseEditorViewController *editor = [self.tabManager selectedEditor];
    if ([editor isKindOfClass:[UDDeclEditorViewController class]]) {
        ((UDDeclEditorViewController *)editor).showsSource = self.representationControl.selectedSegment == 1;
    }
    // As it is: the source stays up when its text does not parse.
    [self _selectedEditorDidChange:nil];
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

    // Commit any in-flight field editing before saving; the keyboard goes
    // back where it was.
    NSResponder *responder = [self _endEditing];

    NSError *error = nil;
    if (![document ud_save:&error]) {
        [self presentError:error];
    }
    [self.window makeFirstResponder:responder];
}

/// Ends the editing in progress (a field's), and says who had the keyboard:
/// the text view, the text field (not its field editor), ...
- (NSResponder *)_endEditing {
    NSResponder *responder = self.window.firstResponder;
    if ([responder isKindOfClass:[NSText class]] && ((NSText *)responder).isFieldEditor
        && [((NSText *)responder).delegate isKindOfClass:[NSResponder class]]) {
        responder = (NSResponder *)((NSText *)responder).delegate;
    }
    [self.window makeFirstResponder:nil];
    return responder;
}

- (IBAction)saveAllDocuments:(id)sender {
    NSResponder *responder = [self _endEditing];

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
    [self.window makeFirstResponder:responder];
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

    NSString *newName = [self _runNamePromptWithTitle:[NSString stringWithFormat:@"Save %@ \u201C%@\u201D As", typeName, originalName]
        message:@"The current content is saved as a new decl with this name, in the same file. The original decl keeps its last saved state."
        okButtonTitle:@"Save" typeName:typeName type:type initialValue:originalName];
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

/// Asks for a new decl's name. Returns nil on cancel; keeps asking while the
/// name is empty or already taken.
- (NSString *)_runNamePromptWithTitle:(NSString *)title
                              message:(NSString *)message
                        okButtonTitle:(NSString *)okButtonTitle
                             typeName:(NSString *)typeName
                                 type:(declType_t)type
                         initialValue:(NSString *)initialValue {
    NSString *value = initialValue ?: @"";

    while (YES) {
        NSString *entered = [UDTextPromptPanel runModalPromptWithTitle:title
                                                               message:message
                                                          initialValue:value
                                                         okButtonTitle:okButtonTitle];
        if (entered == nil) {
            return nil; // cancelled
        }
        value = entered; // re-show what the user typed if we loop

        NSString *candidate = [entered stringByTrimmingCharactersInSet:
                               [NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (candidate.length == 0) {
            continue;
        }
        if ([self.workspace.declManager findDeclWithoutParsing:type name:candidate makeDefault:NO] != nil) {
            NSAlert *taken = [[NSAlert alloc] init];
            taken.messageText = @"Name already in use";
            taken.informativeText = [NSString stringWithFormat:@"A %@ decl named “%@” already exists. Choose a different name.", typeName, candidate];
            [taken runModal];
            continue;
        }
        return candidate;
    }
}

#pragma mark - New PDA, New Skin

// File > New PDA…, New Skin…: a decl of its own name, in a file of its own
// (newpdas/<name>.pda, skins/<name>.skin: the type's folder, where the store
// puts a new decl), opened in its editor; Save writes the file.
- (IBAction)newPDA:(id)sender {
    [self _newDeclOfTypeName:@"pda" title:@"New PDA" fileName:@"newpdas/<name>.pda"];
}

- (IBAction)newSkin:(id)sender {
    [self _newDeclOfTypeName:@"skin" title:@"New Skin" fileName:@"skins/<name>.skin"];
}

- (void)_newDeclOfTypeName:(NSString *)typeName title:(NSString *)title fileName:(NSString *)fileName {
    idDeclManager *declManager = self.workspace.declManager;
    declType_t type = [declManager declTypeFromName:typeName];
    NSString *name = [self _runNamePromptWithTitle:title
        message:[NSString stringWithFormat:@"It gets a file of its own, %@, written when it is saved.", fileName]
        okButtonTitle:@"Create" typeName:typeName type:type
        initialValue:[declManager newName:type base:[typeName stringByAppendingString:@"_"]]];
    if (name == nil) return;

    NSError *error = nil;
    if (![self _createDeclOfTypeName:typeName named:name fileName:nil error:&error]) {
        [self presentError:error];
        return;
    }
    [self.declBrowser reset];
    [self.tabManager openEditorForWorkspaceItem:[[UDDeclItem alloc] initWithType:type declName:name path:name]];
}

#pragma mark - New Declaration

// File > New Declaration…: DialogDeclNew's type, name and file; the decl
// starts from its type's default definition, in that file (a new one, or
// one the decls already come from), and opens in its editor.
- (IBAction)newDecl:(id)sender {
    id selected = [self.outlineView itemAtRow:self.outlineView.selectedRow];
    NSString *typeName = [selected isKindOfClass:[UDDeclItem class]]
        ? [self.workspace.declManager declNameFromType:((UDDeclItem *)selected).type] : nil;
    UDNewDeclWindowController *dialog = [[UDNewDeclWindowController alloc] initWithDeclManager:self.workspace.declManager
                                                                                        typeName:typeName];
    if ([dialog runModal] != NSModalResponseOK) return;

    NSError *error = nil;
    if (![self _createDeclOfTypeName:dialog.typeName named:dialog.declName fileName:dialog.fileName error:&error]) {
        [self presentError:error];
        return;
    }
    declType_t type = [self.workspace.declManager declTypeFromName:dialog.typeName];
    [self.declBrowser reset];
    [self.tabManager openEditorForWorkspaceItem:[[UDDeclItem alloc] initWithType:type declName:dialog.declName path:dialog.declName]];
}

/// A new decl of @a typeName in @a fileName, or where the store puts one of
/// its type when that is nil.
- (BOOL)_createDeclOfTypeName:(NSString *)typeName named:(NSString *)name fileName:(NSString *)fileName error:(NSError **)error {
    NSManagedObjectContext *context = [self.workspace newDeclEditingContextWithError:error];
    if (context == nil) return NO;
    NSString *entityName = [UDDeclBase ud_entityNameForDeclTypeName:typeName
                                                              inModel:context.persistentStoreCoordinator.managedObjectModel];
    if (entityName == nil) return NO;
    UDDeclBase *decl = [NSEntityDescription insertNewObjectForEntityForName:entityName inManagedObjectContext:context];
    decl.name = name;
    if (fileName.length > 0) {
        NSFetchRequest *request = [NSFetchRequest fetchRequestWithEntityName:@"DeclFile"];
        request.predicate = [NSPredicate predicateWithFormat:@"fileName ==[c] %@", fileName];
        NSManagedObject *file = [[context executeFetchRequest:request error:NULL] firstObject];
        if (file == nil) {
            file = [NSEntityDescription insertNewObjectForEntityForName:@"DeclFile" inManagedObjectContext:context];
            [file setValue:fileName forKey:@"fileName"];
        }
        [decl setValue:file forKey:@"sourceFile"];
    }
    return [context save:error];
}

#pragma mark - Workspace settings

// File > Workspace Settings…: edit ALL workspace settings (paths, game,
// file system flags, decl options) in the tabbed settings window, a plain
// window (no modal session holding the menus); OK or Cancel come back to
// -_settingsDidFinish:. On OK the workspace is restarted in place: the new
// paths/game invalidate the loaded VFS and decls, so every tab is closed
// and the browser tree rebuilt.
- (IBAction)showWorkspaceSettings:(id)sender {
    if (self.settingsController != nil) {
        [self.settingsController showWindow:nil];
        return;
    }
    UDWorkspaceSettingsWindowController *settingsWC =
        [[UDWorkspaceSettingsWindowController alloc] initWithWindowNibName:@"UDWorkspaceSettings"];
    settingsWC.document = self.document;
    settingsWC.target = self;
    settingsWC.action = @selector(_settingsDidFinish:);
    self.settingsController = settingsWC;
    [settingsWC showWindow:nil];
}

- (void)_settingsDidFinish:(UDWorkspaceSettingsWindowController *)settingsWC {
    self.settingsController = nil;
    if (settingsWC.result != NSModalResponseOK) {
        return;
    }

    // Applying settings restarts the workspace, which discards any unsaved
    // editor changes — get the user's blessing first.
    BOOL hasDirtyEditors = NO;
    for (UDBaseEditorViewController *editor in [self.tabManager allEditors]) {
        if (editor.editorDocument.isDocumentEdited) {
            hasDirtyEditors = YES;
            break;
        }
    }
    if (hasDirtyEditors) {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"Apply settings and reload the workspace?";
        alert.informativeText = @"Some open editors have unsaved changes. Applying the new settings reloads the workspace and discards them.";
        [alert addButtonWithTitle:@"Apply and Discard"];
        [alert addButtonWithTitle:@"Cancel"];
        if ([alert runModal] != NSAlertFirstButtonReturn) {
            return; // nothing applied
        }
    }

    // Apply the scratch copy to the real workspace and restart it in place.
    UDWorkspace *workspace = self.workspace;
    [workspace applySettingsFromDictionary:settingsWC.scratchWorkspace.dictionaryRepresentation];
    [self.document updateChangeCount:NSChangeDone];

    [self.tabManager closeAllTabs];
    [self.declBrowser clear];
    [UDScriptServer stopForWorkspace:workspace];
    [workspace shutdown];

    // It starts again in the background, "Opening…" over the window, which
    // offers nothing meanwhile (its outline empty, its commands off).
    self.openingController = [[UDWorkspaceOpeningController alloc] initWithWorkspaceName:[(NSDocument *)self.document displayName]];
    [self.openingController showOverWindow:self.window];
    [workspace startupInBackgroundWithTarget:self action:@selector(_workspaceDidRestart:)];
}

- (void)_workspaceDidRestart:(UDWorkspace *)workspace {
    [self.openingController close];
    self.openingController = nil;
    if (workspace.startupError != nil) {
        [self presentError:workspace.startupError];
        return;
    }
    [self.declBrowser reset];
}

- (BOOL)isRestarting {
    return self.openingController != nil;
}

#pragma mark - Issues

/// The text tabs' stores, by their names, in the Issues navigator.
- (void)_editorsDidChange:(NSNotification *)notification {
    NSMutableArray<UDDiagnosticStore *> *stores = [NSMutableArray array];
    NSMutableArray<NSString *> *names = [NSMutableArray array];
    for (UDBaseEditorViewController *editor in [self.tabManager allEditors]) {
        // A script's errors, a PDA's missing references: any editor's store.
        if (![editor respondsToSelector:@selector(diagnosticStore)]) continue;
        UDDiagnosticStore *store = [(id)editor diagnosticStore];
        if (store == nil) continue;
        [stores addObject:store];
        [names addObject:editor.item.name ?: editor.item.path ?: @""];
    }
    [self.issuesNavigator setStores:stores displayNames:names];
}

- (void)errorsViewController:(UDErrorsViewController *)vc
         didSelectDiagnostic:(UDDiagnosticItem *)diagnostic
                     inStore:(UDDiagnosticStore *)store {
    for (UDBaseEditorViewController *editor in [self.tabManager allEditors]) {
        if ([editor isKindOfClass:[UDDeclEditorViewController class]] &&
            ((UDDeclEditorViewController *)editor).diagnosticStore == store) {
            [self.tabManager openEditorForWorkspaceItem:editor.item];
            [(UDDeclEditorViewController *)editor revealDiagnostic:diagnostic];
            return;
        }
        if (![editor isKindOfClass:[UDTextEditorViewController class]] ||
            ((UDTextEditorViewController *)editor).diagnosticStore != store) continue;
        [self.tabManager openEditorForWorkspaceItem:editor.item];
        // The diagnostic's line is 1-based, its column 0-based.
        [(UDTextEditorViewController *)editor selectLine:MAX(diagnostic.line - 1, 0)
                                               character:MAX(diagnostic.column, 0) length:0];
        return;
    }
}

#pragma mark - Test Declaration

- (IBAction)testDecl:(id)sender {
    UDBaseEditorViewController *editor = [self.tabManager selectedEditor];
    if ([editor isKindOfClass:[UDTextEditorViewController class]]) {
        [(UDTextEditorViewController *)editor testDecl:sender];
    } else {
        NSBeep();
    }
}

#pragma mark - Jump to Definition

- (IBAction)jumpToDefinition:(id)sender {
    UDBaseEditorViewController *editor = [self.tabManager selectedEditor];
    if ([editor isKindOfClass:[UDTextEditorViewController class]]) {
        [(UDTextEditorViewController *)editor jumpToDefinition:sender];
    } else {
        NSBeep();
    }
}

- (void)openFileAtPath:(NSString *)path line:(NSInteger)line character:(NSInteger)character length:(NSInteger)length {
    UDBaseEditorViewController *editor = [self.tabManager openEditorForWorkspaceItem:[[UDFileItem alloc] initWithPath:path]];
    if ([editor isKindOfClass:[UDTextEditorViewController class]]) {
        [(UDTextEditorViewController *)editor selectLine:line character:character length:length];
    }
}

- (void)windowWillClose:(NSNotification *)notification {
    [[NSNotificationCenter defaultCenter] removeObserver:self name:UDEditorTabManagerEditorsDidChangeNotification
                                                  object:self.tabManager];
    // The settings go with the workspace, unapplied.
    self.settingsController.target = nil;
    [self.settingsController close];
    self.settingsController = nil;
    [self.tabManager closeAllTabs];
    [UDScriptServer stopForWorkspace:self.workspace];
}

- (BOOL)validateMenuItem:(NSMenuItem *)menuItem {
    SEL action = menuItem.action;
    if (self.isRestarting) {
        return NO;
    }

    if (action == @selector(jumpToDefinition:) || action == @selector(testDecl:)) {
        UDBaseEditorViewController *editor = [self.tabManager selectedEditor];
        return [editor isKindOfClass:[UDTextEditorViewController class]] &&
               [(UDTextEditorViewController *)editor validateMenuItem:menuItem];
    }

    if (action == @selector(showWorkspaceSettings:)) {
        return self.workspace != nil;
    }
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
    if (action == @selector(newDecl:) || action == @selector(newPDA:) || action == @selector(newSkin:)) {
        return self.workspace.declManager != nil;
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
