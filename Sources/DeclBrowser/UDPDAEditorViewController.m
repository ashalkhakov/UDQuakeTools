#import "UDPDAEditorViewController.h"
#import "UDDeclItem.h"
#import "UDDeclDocument.h"
#import "idDeclPDA.h"

@implementation UDPDAEditorViewController

- (instancetype)init {
    self = [super initWithNibName:@"UDPDAEditorView" bundle:nil];
    return self;
}


- (void)setDocument:(UDDeclDocument *)document {
    idDeclPDA *pda = (idDeclPDA *)document.decl;
    //self.objectController.content = pda;
    [self.objectController addObject:pda];
    // optional, if undo doesn’t attach automatically:
    // self.objectController.undoManager = document.undoManager;
    _document = document;
}

- (idDeclPDA *)pda {
    return (idDeclPDA *)((UDDeclDocument *)self.document).decl;
}

- (void)viewDidLoad {
    idDeclPDA *pda;

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
    if (error) {
        NSLog(@"UDPDAEditorViewController: failed to open decl of type %@ name %@: %@", [_document.workspace.declManager declTypeName:declItem.type], declItem.name, error);
    }

    if (![self.document readFromURL:[NSURL URLWithString:@"http://localhost/unused.txt"] ofType:@"" error:&error]) {
        NSLog(@"UDPDAEditorViewController: failed to open decl of type %@ name %@: %@", [_document.workspace.declManager declTypeName:declItem.type], declItem.name, error);
    }
    
    pda = self.pda;
    self.objectController.content = pda;
}

- (IBAction)generateId:(id)sender {
    self.pda.ident = [NSString stringWithFormat:@"%d-%02X", 1000+(rand()%8999), (rand()%255)];
}

- (idDecl *)createDeclType:(declType_t)type subname:(NSString *)subname collection:(NSArray *)collection {
    idDeclPDA *pda = self.pda;
    idDeclManager *declManager = self.workspace.declManager;
    
    if (!pda) {
        return nil;
    }

    // Search for an unused name
    NSString *name = nil;
    int newIndex = (int)collection.count;
    do {
        name = [NSString stringWithFormat:@"%@_%@_%d", pda.name, subname, newIndex++];
    } while ([declManager findType:type name:name makeDefault:NO error:nil] != nil);
    
    // Create a blank email object
    idDecl *newDecl = [declManager createNewDecl:type name:name fileName:pda.fileName];
    
    return newDecl;
}

- (IBAction)addOrRemoveAudioLog:(NSSegmentedControl *)sender {
    if (sender.selectedSegment == 0) {
        idDeclPDA *pda = self.pda;

        idDeclAudio *newAudio = (idDeclAudio *)[self createDeclType:DECL_AUDIO subname:@"audio" collection:pda.audios];

        NSModalResponse result = [self openAudioEditor:newAudio];
        if (result == NSModalResponseOK) {
            [self.audioArrayController addObject:newAudio];
            
            // TODO: register undo for the whole add operation
            /*
             [[undoManager prepareWithInvocationTarget:self]
             removeEmailFromArrayController:email andDeleteFromDeclManager:YES];
             */
        } else {
            // [self.declManager deleteEmail:email]; // cancel: destroy immediately, no undo needed
        }
    } else {
        [self.audioArrayController remove:sender];
        /*
         // Deleting:
         [[self.undoManager prepareWithInvocationTarget:self.declManager]
             createEmailWithState:savedState]; // undo = recreate it
         */
    }
}

- (NSModalResponse)openAudioEditor:(idDeclAudio *)audio {
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
        idDeclPDA *pda = self.pda;

        idDeclEmail *newEmail = (idDeclEmail *)[self createDeclType:DECL_EMAIL subname:@"email" collection:pda.emails];

        // Lazily load the NIB each time, or keep the controller around
        NSModalResponse result = [self openEmailEditor:newEmail];
        if (result == NSModalResponseOK) {
            [self.emailArrayController addObject:newEmail];
        }
    } else {
        [self.emailArrayController remove:sender];
    }
}

- (NSModalResponse)openEmailEditor:(idDeclEmail *)email {
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
        idDeclPDA *pda = self.pda;

        idDeclVideo *newVideo = (idDeclVideo *)[self createDeclType:DECL_EMAIL subname:@"video" collection:pda.videos];
        
        NSModalResponse result = [self openVideoEditor:newVideo];
        if (result == NSModalResponseOK) {
            [self.videoArrayController addObject:newVideo];
        }
    } else {
        [self.videoArrayController remove:sender];
    }
}

- (NSModalResponse)openVideoEditor:(idDeclVideo *)video {
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

    idDeclAudio *selectedAudio = self.audioArrayController.arrangedObjects[row];
    NSModalResponse result = [self openAudioEditor:selectedAudio];
    if (result == NSModalResponseOK) {
        // save it
    } else {
        // undo it
    }
}

- (IBAction)emailEdit:(id)sender {
    if (![sender isKindOfClass:[NSTableView class]]) {
        return;
    }

    NSTableView *tableView = (NSTableView *)sender;
    NSInteger row = tableView.clickedRow;
    if (row < 0) return; // clicked empty area

    idDeclEmail *selectedEmail = self.emailArrayController.arrangedObjects[row];
    NSModalResponse result = [self openEmailEditor:selectedEmail];
    if (result == NSModalResponseOK) {
        // save it
    } else {
        // undo it
    }
}

- (IBAction)videoEdit:(id)sender {
    if (![sender isKindOfClass:[NSTableView class]]) {
        return;
    }

    NSTableView *tableView = (NSTableView *)sender;
    NSInteger row = tableView.clickedRow;
    if (row < 0) return; // clicked empty area

    idDeclVideo *selectedVideo = self.videoArrayController.arrangedObjects[row];
    NSModalResponse result = [self openVideoEditor:selectedVideo];
    if (result == NSModalResponseOK) {
        // save it
    } else {
        // undo it
    }
}

@end

@implementation UDPDAAudioEditorViewController

- (void)awakeFromNib {
    self.objectController.content = self.editingAudio;
}

- (IBAction)ok:(id)sender {
    [NSApp stopModalWithCode:NSModalResponseOK];
    [self.window orderOut:sender];
}

- (IBAction)cancel:(id)sender {
    [NSApp stopModalWithCode:NSModalResponseCancel];
    [self.window orderOut:sender];
}

@end


@implementation UDPDAEmailEditorViewController

- (void)awakeFromNib {
    self.objectController.content = self.editingEmail;
}

- (IBAction)ok:(id)sender {
    [NSApp stopModalWithCode:NSModalResponseOK];
    [self.window orderOut:sender];
}

- (IBAction)cancel:(id)sender {
    [NSApp stopModalWithCode:NSModalResponseCancel];
    [self.window orderOut:sender];
}

@end

@implementation UDPDAVideoEditorViewController

- (void)awakeFromNib {
    self.objectController.content = self.editingVideo;
}

- (IBAction)ok:(id)sender {
    [NSApp stopModalWithCode:NSModalResponseOK];
    [self.window orderOut:sender];
}

- (IBAction)cancel:(id)sender {
    [NSApp stopModalWithCode:NSModalResponseCancel];
    [self.window orderOut:sender];
}

@end
