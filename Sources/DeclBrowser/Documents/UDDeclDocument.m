#import "UDDeclDocument.h"

@interface UDDeclDocument ()
@property (nonatomic, weak) NSTextView *textView;
/** Legacy fallback for decl types without a DeclModel entity. */
@property (nonatomic, strong) idDeclBase *legacyDecl;
@end

@implementation UDDeclDocument

- (instancetype)initWithType:(declType_t)type name:(NSString *)name inWorkspace:(UDWorkspace *)workspace error:(NSError **)error {
    self = [super initWithType:@"public.plain-text" error:error];
    if (self) {
        self.workspace = workspace;

        NSString *typeName = [workspace.declManager declNameFromType:type];
        NSManagedObjectContext *context = workspace.declEditingContext;

        BOOL typeHasEntity = context != nil &&
            [UDDeclBase ud_entityNameForDeclTypeName:typeName
                                               inModel:context.persistentStoreCoordinator.managedObjectModel] != nil;

        if (typeHasEntity) {
            _editingContext = context;
            _declObject = [UDDeclBase ud_declWithTypeName:typeName name:name inContext:context error:error];
            if (_declObject == nil) {
                return nil;
            }

            // Share the context's undo manager so Cmd-Z undoes managed
            // object edits made through bindings as well as text edits.
            self.undoManager = context.undoManager;

            // Track dirtiness: any change to our decl (or to a child decl
            // that belongs to it) marks the document edited.
            [[NSNotificationCenter defaultCenter] addObserver:self
                                                     selector:@selector(_editingContextObjectsDidChange:)
                                                         name:NSManagedObjectContextObjectsDidChangeNotification
                                                       object:context];
        } else {
            // No entity for this decl type yet: edit the raw idDecl text
            // directly against the manager.
            _legacyDecl = [workspace.declManager declByName:name type:type forceParse:YES error:error];
            if (_legacyDecl == nil) {
                return nil;
            }
        }
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)_editingContextObjectsDidChange:(NSNotification *)notification {
    NSMutableSet *changed = [NSMutableSet set];
    for (NSString *key in @[NSInsertedObjectsKey, NSUpdatedObjectsKey, NSDeletedObjectsKey]) {
        NSSet *objects = notification.userInfo[key];
        if (objects != nil) {
            [changed unionSet:objects];
        }
    }

    for (NSManagedObject *object in changed) {
        if (object == self.declObject) {
            [self updateChangeCount:NSChangeDone];
            return;
        }
        // A child decl (email/audio/video) attached to our decl.
        if (object.entity.relationshipsByName[@"pda"] != nil &&
            [object valueForKey:@"pda"] == self.declObject) {
            [self updateChangeCount:NSChangeDone];
            return;
        }
    }
}

// Don't create a window; the workspace window controller hosts the view.
- (void)makeWindowControllers {
}

- (BOOL)readFromURL:(NSURL *)url ofType:(NSString *)typeName error:(NSError **)error {
    NSData *sourceText = nil;

    if (self.declObject != nil) {
        sourceText = self.declObject.sourceText;
    } else if (self.legacyDecl != nil) {
        NSMutableData *declText = [[NSMutableData alloc] init];
        [self.legacyDecl text:declText];
        sourceText = declText;
    }

    NSString *text = sourceText != nil ? [[NSString alloc] initWithData:sourceText encoding:NSUTF8StringEncoding] : nil;
    _textContent = text ?: @"";
    return YES;
}

- (BOOL)writeToURL:(NSURL *)url ofType:(NSString *)typeName error:(NSError **)error {
    NSString *content = self.textView ? self.textView.string : self.textContent ?: @"";

    if (self.declObject != nil) {
        // Text-based editing: push the text view's current contents into the
        // decl object. Structured editors (e.g. the PDA editor) edit the
        // managed object's attributes directly through bindings, so there is
        // nothing to transfer for them — the context already has their
        // changes and the store re-derives the source text on save.
        if (self.textView != nil) {
            self.textContent = content;
            self.declObject.sourceText = [content dataUsingEncoding:NSUTF8StringEncoding];
        }

        if (![self.editingContext save:error]) {
            return NO;
        }

        // Re-fault only after raw text edits, where attributes must re-parse
        // from the new text. For attribute-driven saves (e.g. the PDA
        // editor) the in-memory values are already authoritative, and
        // re-faulting an object under live bindings can blank the UI.
        if (self.textView != nil) {
            [self.editingContext refreshObject:self.declObject mergeChanges:NO];
        }

        [self updateChangeCount:NSChangeCleared];
        return YES;
    }

    // Legacy path.
    NSMutableData *buffer = [[content dataUsingEncoding:NSUTF8StringEncoding] mutableCopy];
    [self.legacyDecl setText:buffer];
    if (![self.legacyDecl replaceSourceFileText:error]) {
        return NO;
    }
    [self.legacyDecl invalidate];

    return YES;
}

- (void)setTextView:(NSTextView *)textView {
    _textView = textView;
    if (textView && self.textContent) {
        [textView.textStorage beginEditing];
        [textView.textStorage
            replaceCharactersInRange:NSMakeRange(0, textView.textStorage.length)
                          withString:self.textContent];
        [textView.textStorage endEditing];
    }
    textView.undoManager.levelsOfUndo = 50;
}

@end
