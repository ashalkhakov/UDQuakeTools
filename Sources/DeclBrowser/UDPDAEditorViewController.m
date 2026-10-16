#import "UDPDAEditorViewController.h"
#import "UDDeclItem.h"
#import "UDDeclDocument.h"
#import "UDDeclManagedObjects.h"

/// The diagnostics' source: what the PDA references.
static UDDiagnosticSource const UDPDAReferencesSource = @"references";

/// The PDA's lists: relationship, decl type, what one is called.
static NSArray<NSArray<NSString *> *> *UDPDALists(void) {
    return @[ @[@"emails", @"email", @"Email"], @[@"audios", @"audio", @"Audio log"], @[@"videos", @"video", @"Video"] ];
}

@interface UDPDAEditorViewController ()
@property (nonatomic, strong, readwrite, nullable) UDDiagnosticStore *diagnosticStore;
/// Each diagnostic's list and child, for -revealDiagnostic:.
@property (nonatomic, strong) NSMapTable<UDDiagnosticItem *, NSArray *> *diagnosticTargets;
@end

@implementation UDPDAEditorViewController

- (instancetype)init {
    self = [super initWithNibName:@"UDPDAEditorView" bundle:[NSBundle bundleForClass:[UDPDAEditorViewController class]]];
    return self;
}

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

- (UDDeclPDA *)pda {
    return (UDDeclPDA *)self.document.declObject;
}

- (NSManagedObjectContext *)editingContext {
    return self.document.editingContext;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    if (self.item == nil) {
        return;
    }

    if (self.item.kind != UDWorkspaceItemKindDecl) {
        return;
    }

    UDDeclItem *declItem = (UDDeclItem *)self.item;
    NSError *error = nil;

    self.document = [[UDDeclDocument alloc] initWithType:declItem.type name:declItem.declName inWorkspace:self.workspace error:&error];
    if (self.document == nil) {
        NSLog(@"UDPDAEditorViewController: failed to open decl of type %@ name %@: %@", [self.workspace.declManager declTypeName:declItem.type], declItem.declName, error);
        return;
    }

    if (![self.document readFromURL:[NSURL URLWithString:@"http://localhost/unused.txt"] ofType:@"" error:&error]) {
        NSLog(@"UDPDAEditorViewController: failed to read decl of type %@ name %@: %@", [self.workspace.declManager declTypeName:declItem.type], declItem.declName, error);
    }

    // Child decl relationships are unordered sets; present them sorted by name.
    NSArray *byName = @[[NSSortDescriptor sortDescriptorWithKey:@"name" ascending:YES selector:@selector(caseInsensitiveCompare:)]];
    self.audioArrayController.sortDescriptors = byName;
    self.emailArrayController.sortDescriptors = byName;
    self.videoArrayController.sortDescriptors = byName;

    self.objectController.content = self.pda;

    self.diagnosticStore = [[UDDiagnosticStore alloc] init];
    self.diagnosticTargets = [NSMapTable strongToStrongObjectsMapTable];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_editingContextDidChange:)
                                                 name:NSManagedObjectContextObjectsDidChangeNotification
                                               object:self.editingContext];
    [self checkReferences];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - References

- (void)_editingContextDidChange:(NSNotification *)notification {
    [self checkReferences];
}

/// The line of the PDA's text that names @a name, 1-based (1 when none).
- (NSInteger)_lineNaming:(NSString *)name {
    NSData *source = self.pda.sourceText;
    NSString *text = source != nil ? [[NSString alloc] initWithData:source encoding:NSUTF8StringEncoding] : nil;
    NSRange found = [text rangeOfString:[NSString stringWithFormat:@"\"%@\"", name] options:NSCaseInsensitiveSearch];
    if (found.location == NSNotFound) return 1;
    NSInteger line = 1;
    for (NSUInteger i = 0; i < found.location; i++) {
        if ([text characterAtIndex:i] == '\n') line++;
    }
    return line;
}

/// A child the PDA names but no decl defines: not one added here and not
/// saved yet, nor one the decl manager has.
- (void)checkReferences {
    UDDeclPDA *pda = self.pda;
    idDeclManager *declManager = self.workspace.declManager;
    if (pda == nil || declManager == nil || self.diagnosticStore == nil) return;

    NSMutableArray<UDDiagnosticItem *> *items = [NSMutableArray array];
    [self.diagnosticTargets removeAllObjects];
    for (NSArray<NSString *> *list in UDPDALists()) {
        declType_t type = [declManager declTypeFromName:list[1]];
        for (UDDeclBase *child in [pda valueForKey:list[0]]) {
            if (child.objectID.isTemporaryID) continue;
            // A decl no file defines has no values: its name is in its ID.
            NSString *name = [(NSIncrementalStore *)child.objectID.persistentStore referenceObjectForObjectID:child.objectID];
            if (![name isKindOfClass:[NSString class]] || name.length == 0) continue;
            if ([declManager declByName:name type:type forceParse:NO error:NULL] != nil) continue;
            UDDiagnosticItem *item = [[UDDiagnosticItem alloc] initWithLine:[self _lineNaming:name] column:0
                message:[NSString stringWithFormat:@"%@ \u201C%@\u201D is not defined", list[2], name]
                severity:UDDiagnosticSeverityError source:UDPDAReferencesSource];
            [items addObject:item];
            [self.diagnosticTargets setObject:@[list[0], child] forKey:item];
        }
    }
    [self.diagnosticStore setDiagnostics:items forSource:UDPDAReferencesSource];
}

- (void)revealDiagnostic:(UDDiagnosticItem *)diagnostic {
    NSArray *target = [self.diagnosticTargets objectForKey:diagnostic];
    if (target == nil) return;
    [self.tabView selectTabViewItemWithIdentifier:target[0]];
    NSArrayController *controller = [target[0] isEqualToString:@"emails"] ? self.emailArrayController
        : [target[0] isEqualToString:@"audios"] ? self.audioArrayController : self.videoArrayController;
    [controller setSelectedObjects:@[target[1]]];
}

// Runs a modal child-editor session (a sheet) on a child of the editing
// context: the sheet's edits stay there until OK saves them into the editing
// context, in one undo group named for it; Cancel just lets the child go,
// and the editing context never saw them.
- (NSModalResponse)runModalEditSession:(NSModalResponse (^)(NSManagedObjectContext *sheetContext))session
                            actionName:(NSString *)actionName {
    NSManagedObjectContext *context = self.editingContext;
    NSManagedObjectContext *sheetContext = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSMainQueueConcurrencyType];
    sheetContext.parentContext = context;

    NSModalResponse result = session(sheetContext);
    if (result != NSModalResponseOK || !sheetContext.hasChanges) {
        return result;
    }

    NSUndoManager *undoManager = context.undoManager;
    [context processPendingChanges];
    [undoManager beginUndoGrouping];
    [undoManager setActionName:actionName];
    NSError *error = nil;
    if (![sheetContext save:&error]) {
        NSLog(@"UDPDAEditorViewController: %@ did not reach the PDA: %@", actionName, error);
    }
    [context processPendingChanges];
    [undoManager endUndoGrouping];
    return result;
}

- (IBAction)generateId:(id)sender {
    self.pda.ident = [NSString stringWithFormat:@"%d-%02X", 1000+(rand()%8999), (rand()%255)];
}

/**
 * Inserts a new child decl (email/audio/video) into @a context, a sheet's.
 * The incremental store turns the insert into an idDeclManager
 * createNewDecl once it is saved down to the store. The child starts out in
 * the same source file as the PDA itself.
 */
- (__kindof UDDeclBase *)createChildDeclWithTypeName:(NSString *)typeName subname:(NSString *)subname
                                           inContext:(NSManagedObjectContext *)context {
    UDDeclPDA *pda = self.pda;
    idDeclManager *declManager = self.workspace.declManager;

    if (!pda) {
        return nil;
    }

    NSString *entityName = [UDDeclBase ud_entityNameForDeclTypeName:typeName
                                                              inModel:context.persistentStoreCoordinator.managedObjectModel];
    if (entityName == nil) {
        return nil;
    }

    // Search for an unused name.
    declType_t type = [declManager declTypeFromName:typeName];
    NSString *base = [NSString stringWithFormat:@"%@_%@_", pda.name, subname];
    NSString *name = [declManager newName:type base:base];

    UDDeclBase *child = [NSEntityDescription insertNewObjectForEntityForName:entityName
                                                        inManagedObjectContext:context];
    child.name = name;
    child.sourceFile = [(UDDeclPDA *)[context objectWithID:pda.objectID] sourceFile];
    return child;
}

/// A new child of @a typeName, edited in its sheet (@a open) and, on OK,
/// added to the PDA's @a relationship: all in one sheet context.
- (void)addChildOfType:(NSString *)typeName relationship:(NSString *)relationship
            actionName:(NSString *)actionName open:(NSModalResponse (^)(id child))open {
    [self runModalEditSession:^NSModalResponse(NSManagedObjectContext *sheetContext) {
        UDDeclBase *child = [self createChildDeclWithTypeName:typeName subname:typeName inContext:sheetContext];
        if (child == nil) {
            return NSModalResponseCancel;
        }
        NSModalResponse result = open(child);
        if (result == NSModalResponseOK) {
            [[[sheetContext objectWithID:self.pda.objectID] mutableSetValueForKey:relationship] addObject:child];
        }
        return result;
    } actionName:actionName];
}

/// @a child, as it is in a sheet context, edited in its sheet (@a open).
- (void)editChild:(UDDeclBase *)child actionName:(NSString *)actionName open:(NSModalResponse (^)(id child))open {
    [self runModalEditSession:^NSModalResponse(NSManagedObjectContext *sheetContext) {
        return open([sheetContext objectWithID:child.objectID]);
    } actionName:actionName];
}

/**
 * Detaches the array controller's selected child decls from one of the
 * PDA's to-many relationships. Used instead of -[NSArrayController remove:]:
 * Apple's contentSet binding routes that removal through the model, but
 * GNUstep's array controller mutates its content collection in place — and
 * the content here is the relationship's (immutable) set, which raises and
 * leaves the app wedged mid-event. Editing the model directly behaves
 * identically on both platforms (and the decl itself stays in its source
 * file either way).
 */
- (void)detachSelectedFrom:(NSArrayController *)controller relationship:(NSString *)key {
    NSArray *selected = controller.selectedObjects;
    if (selected.count == 0) {
        return;
    }
    NSMutableSet *set = [self.pda mutableSetValueForKey:key];
    for (id object in selected) {
        [set removeObject:object];
    }
}

- (IBAction)addOrRemoveAudioLog:(NSSegmentedControl *)sender {
    if (sender.selectedSegment == 0) {
        [self addChildOfType:@"audio" relationship:@"audios" actionName:@"Add Audio Log"
                        open:^NSModalResponse(id child) { return [self openAudioEditor:child]; }];
    } else {
        [self detachSelectedFrom:self.audioArrayController relationship:@"audios"];
    }
}

- (NSModalResponse)openAudioEditor:(UDDeclAudio *)audio {
    // Lazily load the NIB each time, or keep the controller around
    UDPDAAudioEditorViewController *editorVC = [[UDPDAAudioEditorViewController alloc] init];
    editorVC.editingAudio = audio;
    [[NSBundle bundleForClass:[UDPDAEditorViewController class]] loadNibNamed:@"UDPDAAudioEditorView"
                                 owner:editorVC
                       topLevelObjects:nil];

    NSModalResponse result = [NSApp runModalForWindow:editorVC.window];
    return result;
}

- (IBAction)addOrRemoveEmail:(NSSegmentedControl *)sender {
    if (sender.selectedSegment == 0) {
        [self addChildOfType:@"email" relationship:@"emails" actionName:@"Add Email"
                        open:^NSModalResponse(id child) { return [self openEmailEditor:child]; }];
    } else {
        [self detachSelectedFrom:self.emailArrayController relationship:@"emails"];
    }
}

- (NSModalResponse)openEmailEditor:(UDDeclEmail *)email {
    UDPDAEmailEditorViewController *editorVC = [[UDPDAEmailEditorViewController alloc] init];
    editorVC.editingEmail = email;
    [[NSBundle bundleForClass:[UDPDAEditorViewController class]] loadNibNamed:@"UDPDAEmailEditorView"
                                 owner:editorVC
                       topLevelObjects:nil];

    NSModalResponse result = [NSApp runModalForWindow:editorVC.window];
    return result;
}

- (IBAction)addOrRemoveVideo:(NSSegmentedControl *)sender {
    if (sender.selectedSegment == 0) {
        [self addChildOfType:@"video" relationship:@"videos" actionName:@"Add Video"
                        open:^NSModalResponse(id child) { return [self openVideoEditor:child]; }];
    } else {
        [self detachSelectedFrom:self.videoArrayController relationship:@"videos"];
    }
}

- (NSModalResponse)openVideoEditor:(UDDeclVideo *)video {
    // Lazily load the NIB each time, or keep the controller around
    UDPDAVideoEditorViewController *editorVC = [[UDPDAVideoEditorViewController alloc] init];
    editorVC.editingVideo = video;
    [[NSBundle bundleForClass:[UDPDAEditorViewController class]] loadNibNamed:@"UDPDAVideoEditorView"
                                 owner:editorVC
                       topLevelObjects:nil];

    NSModalResponse result = [NSApp runModalForWindow:editorVC.window];
    return result;
}

/// The row a double-click was on (none on empty space); sent otherwise (the
/// keyboard, a test), the row selected.
static NSInteger UDRowToEdit(NSTableView *tableView) {
    NSEventType type = [NSApp currentEvent].type;
    BOOL clicked = type == NSEventTypeLeftMouseDown || type == NSEventTypeLeftMouseUp;
    return clicked ? tableView.clickedRow : tableView.selectedRow;
}

- (IBAction)audioLogEdit:(id)sender {
    if (![sender isKindOfClass:[NSTableView class]]) {
        return;
    }
    NSInteger row = UDRowToEdit((NSTableView *)sender);
    if (row < 0) return;

    UDDeclAudio *selected = self.audioArrayController.arrangedObjects[row];
    [self editChild:selected actionName:@"Edit Audio Log"
               open:^NSModalResponse(id child) { return [self openAudioEditor:child]; }];
}

- (IBAction)emailEdit:(id)sender {
    if (![sender isKindOfClass:[NSTableView class]]) {
        return;
    }
    NSInteger row = UDRowToEdit((NSTableView *)sender);
    if (row < 0) return;

    UDDeclEmail *selected = self.emailArrayController.arrangedObjects[row];
    [self editChild:selected actionName:@"Edit Email"
               open:^NSModalResponse(id child) { return [self openEmailEditor:child]; }];
}

- (IBAction)videoEdit:(id)sender {
    if (![sender isKindOfClass:[NSTableView class]]) {
        return;
    }
    NSInteger row = UDRowToEdit((NSTableView *)sender);
    if (row < 0) return;

    UDDeclVideo *selected = self.videoArrayController.arrangedObjects[row];
    [self editChild:selected actionName:@"Edit Video"
               open:^NSModalResponse(id child) { return [self openVideoEditor:child]; }];
}

@end

@implementation UDPDAAudioEditorViewController

- (void)awakeFromNib {
    self.objectController.content = self.editingAudio;
}

- (IBAction)ok:(id)sender {
    // Clicking a button does not resign the first responder, so a text field
    // still being edited (no Enter yet) — and especially an NSTextView, whose
    // value binding only commits when editing ends — would otherwise lose its
    // in-flight value. Force editing to end, then ask the controller's
    // registered editors to commit, before the modal is torn down.
    if (![self.window makeFirstResponder:nil]) {
        [self.window endEditingFor:nil];
    }
    [self.objectController commitEditing];
    [NSApp stopModalWithCode:NSModalResponseOK];
    [self.window orderOut:sender];
}

- (IBAction)cancel:(id)sender {
    // Throw away any in-flight (uncommitted) field editing so it cannot get
    // pushed into the object after the session's undo group has closed.
    [self.objectController discardEditing];
    [NSApp stopModalWithCode:NSModalResponseCancel];
    [self.window orderOut:sender];
}

@end


@implementation UDPDAEmailEditorViewController

- (void)awakeFromNib {
    self.objectController.content = self.editingEmail;
}

- (IBAction)ok:(id)sender {
    // Clicking a button does not resign the first responder, so a text field
    // still being edited (no Enter yet) — and especially an NSTextView, whose
    // value binding only commits when editing ends — would otherwise lose its
    // in-flight value. Force editing to end, then ask the controller's
    // registered editors to commit, before the modal is torn down.
    if (![self.window makeFirstResponder:nil]) {
        [self.window endEditingFor:nil];
    }
    [self.objectController commitEditing];
    [NSApp stopModalWithCode:NSModalResponseOK];
    [self.window orderOut:sender];
}

- (IBAction)cancel:(id)sender {
    // Throw away any in-flight (uncommitted) field editing so it cannot get
    // pushed into the object after the session's undo group has closed.
    [self.objectController discardEditing];
    [NSApp stopModalWithCode:NSModalResponseCancel];
    [self.window orderOut:sender];
}

@end

@implementation UDPDAVideoEditorViewController

- (void)awakeFromNib {
    self.objectController.content = self.editingVideo;
}

- (IBAction)ok:(id)sender {
    // Clicking a button does not resign the first responder, so a text field
    // still being edited (no Enter yet) — and especially an NSTextView, whose
    // value binding only commits when editing ends — would otherwise lose its
    // in-flight value. Force editing to end, then ask the controller's
    // registered editors to commit, before the modal is torn down.
    if (![self.window makeFirstResponder:nil]) {
        [self.window endEditingFor:nil];
    }
    [self.objectController commitEditing];
    [NSApp stopModalWithCode:NSModalResponseOK];
    [self.window orderOut:sender];
}

- (IBAction)cancel:(id)sender {
    // Throw away any in-flight (uncommitted) field editing so it cannot get
    // pushed into the object after the session's undo group has closed.
    [self.objectController discardEditing];
    [NSApp stopModalWithCode:NSModalResponseCancel];
    [self.window orderOut:sender];
}

@end
