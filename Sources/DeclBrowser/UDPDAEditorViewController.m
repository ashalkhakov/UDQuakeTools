#import "UDPDAEditorViewController.h"
#import "UDDeclItem.h"
#import "UDDeclDocument.h"
#import "UDDeclManagedObjects.h"

@implementation UDPDAEditorViewController

- (instancetype)init {
    self = [super initWithNibName:@"UDPDAEditorView" bundle:nil];
    return self;
}

- (void)setDocument:(UDDeclDocument *)document {
    _document = document;
    if (self.viewLoaded && document != nil) {
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
}

// Runs a modal child-editor session inside its own named undo group on the
// context's undo manager:
//
//   1. before the modal starts: beginUndoGrouping + setActionName
//   2. after it ends (OK or Cancel): endUndoGrouping
//   3. if the user cancelled: a single -undoNestedGroup reverts just that
//      innermost group — everything the session did (field edits, inserts,
//      relationship changes) in one step, leaving the rest of the stack
//      intact.
//
// The processPendingChanges calls bracket the group so that (a) changes made
// before the session are registered outside the group and (b) everything the
// session did is registered inside it before it closes.
- (NSModalResponse)runModalEditSession:(NSModalResponse (^)(void))session
                            actionName:(NSString *)actionName {
    NSManagedObjectContext *context = self.editingContext;
    NSUndoManager *undoManager = context.undoManager;

    [context processPendingChanges];
    [undoManager beginUndoGrouping];
    [undoManager setActionName:actionName];

    NSModalResponse result = session();

    [context processPendingChanges];
    [undoManager endUndoGrouping];

    if (result != NSModalResponseOK) {
        [undoManager undoNestedGroup];
    }
    return result;
}

- (IBAction)generateId:(id)sender {
    self.pda.ident = [NSString stringWithFormat:@"%d-%02X", 1000+(rand()%8999), (rand()%255)];
}

/**
 * Inserts a new child decl managed object (email/audio/video) into the shared
 * editing context. The incremental store turns the insert into an
 * idDeclManager createNewDecl on save. The child starts out in the same
 * source file as the PDA itself.
 */
- (__kindof UDDeclBase *)createChildDeclWithTypeName:(NSString *)typeName subname:(NSString *)subname {
    UDDeclPDA *pda = self.pda;
    idDeclManager *declManager = self.workspace.declManager;

    if (!pda) {
        return nil;
    }

    NSManagedObjectContext *context = self.editingContext;
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
    child.sourceFile = pda.sourceFile;
    return child;
}

- (IBAction)addOrRemoveAudioLog:(NSSegmentedControl *)sender {
    if (sender.selectedSegment == 0) {
        // The insert, the modal's edits and the relationship hookup all land
        // in one "Add Audio Log" undo group; cancelling undoes that group,
        // which removes the freshly inserted object again.
        [self runModalEditSession:^NSModalResponse{
            UDDeclAudio *newAudio = [self createChildDeclWithTypeName:@"audio" subname:@"audio"];
            if (newAudio == nil) {
                return NSModalResponseCancel;
            }
            NSModalResponse result = [self openAudioEditor:newAudio];
            if (result == NSModalResponseOK) {
                [[self.pda mutableSetValueForKey:@"audios"] addObject:newAudio];
            }
            return result;
        } actionName:@"Add Audio Log"];
    } else {
        // Detaches the selected audio from the PDA; the audio decl itself
        // stays in its source file.
        [self.audioArrayController remove:sender];
    }
}

- (NSModalResponse)openAudioEditor:(UDDeclAudio *)audio {
    // Lazily load the NIB each time, or keep the controller around
    UDPDAAudioEditorViewController *editorVC = [[UDPDAAudioEditorViewController alloc] init];
    editorVC.editingAudio = audio;
    [[NSBundle mainBundle] loadNibNamed:@"UDPDAAudioEditorView"
                                 owner:editorVC
                       topLevelObjects:nil];

    NSModalResponse result = [NSApp runModalForWindow:editorVC.window];
    return result;
}

- (IBAction)addOrRemoveEmail:(NSSegmentedControl *)sender {
    if (sender.selectedSegment == 0) {
        [self runModalEditSession:^NSModalResponse{
            UDDeclEmail *newEmail = [self createChildDeclWithTypeName:@"email" subname:@"email"];
            if (newEmail == nil) {
                return NSModalResponseCancel;
            }
            NSModalResponse result = [self openEmailEditor:newEmail];
            if (result == NSModalResponseOK) {
                [[self.pda mutableSetValueForKey:@"emails"] addObject:newEmail];
            }
            return result;
        } actionName:@"Add Email"];
    } else {
        [self.emailArrayController remove:sender];
    }
}

- (NSModalResponse)openEmailEditor:(UDDeclEmail *)email {
    UDPDAEmailEditorViewController *editorVC = [[UDPDAEmailEditorViewController alloc] init];
    editorVC.editingEmail = email;
    [[NSBundle mainBundle] loadNibNamed:@"UDPDAEmailEditorView"
                                 owner:editorVC
                       topLevelObjects:nil];

    NSModalResponse result = [NSApp runModalForWindow:editorVC.window];
    return result;
}

- (IBAction)addOrRemoveVideo:(NSSegmentedControl *)sender {
    if (sender.selectedSegment == 0) {
        [self runModalEditSession:^NSModalResponse{
            UDDeclVideo *newVideo = [self createChildDeclWithTypeName:@"video" subname:@"video"];
            if (newVideo == nil) {
                return NSModalResponseCancel;
            }
            NSModalResponse result = [self openVideoEditor:newVideo];
            if (result == NSModalResponseOK) {
                [[self.pda mutableSetValueForKey:@"videos"] addObject:newVideo];
            }
            return result;
        } actionName:@"Add Video"];
    } else {
        [self.videoArrayController remove:sender];
    }
}

- (NSModalResponse)openVideoEditor:(UDDeclVideo *)video {
    // Lazily load the NIB each time, or keep the controller around
    UDPDAVideoEditorViewController *editorVC = [[UDPDAVideoEditorViewController alloc] init];
    editorVC.editingVideo = video;
    [[NSBundle mainBundle] loadNibNamed:@"UDPDAVideoEditorView"
                                 owner:editorVC
                       topLevelObjects:nil];

    NSModalResponse result = [NSApp runModalForWindow:editorVC.window];
    return result;
}

- (IBAction)audioLogEdit:(id)sender {
    if (![sender isKindOfClass:[NSTableView class]]) {
        return;
    }

    NSTableView *tableView = (NSTableView *)sender;
    NSInteger row = tableView.clickedRow;
    if (row < 0) return; // clicked empty area

    UDDeclAudio *selectedAudio = self.audioArrayController.arrangedObjects[row];
    [self runModalEditSession:^NSModalResponse{
        return [self openAudioEditor:selectedAudio];
    } actionName:@"Edit Audio Log"];
}

- (IBAction)emailEdit:(id)sender {
    if (![sender isKindOfClass:[NSTableView class]]) {
        return;
    }

    NSTableView *tableView = (NSTableView *)sender;
    NSInteger row = tableView.clickedRow;
    if (row < 0) return; // clicked empty area

    UDDeclEmail *selectedEmail = self.emailArrayController.arrangedObjects[row];
    [self runModalEditSession:^NSModalResponse{
        return [self openEmailEditor:selectedEmail];
    } actionName:@"Edit Email"];
}

- (IBAction)videoEdit:(id)sender {
    if (![sender isKindOfClass:[NSTableView class]]) {
        return;
    }

    NSTableView *tableView = (NSTableView *)sender;
    NSInteger row = tableView.clickedRow;
    if (row < 0) return; // clicked empty area

    UDDeclVideo *selectedVideo = self.videoArrayController.arrangedObjects[row];
    [self runModalEditSession:^NSModalResponse{
        return [self openVideoEditor:selectedVideo];
    } actionName:@"Edit Video"];
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
