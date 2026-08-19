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
        _declType = type;

        NSString *typeName = [workspace.declManager declNameFromType:type];
        NSPersistentStoreCoordinator *coordinator = workspace.declStoreCoordinator;

        BOOL typeHasEntity = coordinator != nil &&
            [UDDeclBase ud_entityNameForDeclTypeName:typeName
                                               inModel:coordinator.managedObjectModel] != nil;

        if (typeHasEntity) {
            // Each document gets its OWN context over the workspace's shared
            // coordinator, so saving this document saves only its changes.
            NSManagedObjectContext *context = [workspace newDeclEditingContextWithError:error];
            if (context == nil) {
                return nil;
            }
            _editingContext = context;
            _declObject = [UDDeclBase ud_declWithTypeName:typeName name:name inContext:context error:error];
            if (_declObject == nil) {
                return nil;
            }

            // Share the context's undo manager so Cmd-Z undoes managed
            // object edits made through bindings as well as text edits.
            self.undoManager = context.undoManager;

            // Track dirtiness: the context is private to this document, so
            // any change in it belongs to this document.
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
    // The editing context is private to this document, so any insert, update
    // or delete in it is this document's change.
    for (NSString *key in @[NSInsertedObjectsKey, NSUpdatedObjectsKey, NSDeletedObjectsKey]) {
        NSSet *objects = notification.userInfo[key];
        if (objects.count > 0) {
            [self updateChangeCount:NSChangeDone];
            return;
        }
    }
}

- (void)_textViewTextDidChange:(NSNotification *)notification {
    // Raw text edits never touch the managed object until save, so the
    // context can't report them — mark the document edited directly.
    [self updateChangeCount:NSChangeDone];
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

    [self updateChangeCount:NSChangeCleared];
    return YES;
}

#pragma mark - Save As (transfer the buffer to a new decl)

- (__kindof UDDeclBase *)saveAsNewDeclNamed:(NSString *)newName error:(NSError **)error {
    UDDeclBase *original = self.declObject;
    NSManagedObjectContext *context = self.editingContext;

    if (original == nil || context == nil || newName.length == 0) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:@"UDDeclDocument"
                                          code:1
                                      userInfo:@{NSLocalizedDescriptionKey:
                @"Save As is only available for entity-backed decls"}];
        }
        return nil;
    }

    NSEntityDescription *entity = original.entity;

    // 1. Capture the buffer's current content. When a text view is attached
    //    its string is the authoritative content (same rule as -writeToURL:);
    //    otherwise (structured form editors, e.g. the PDA editor) the managed
    //    object's attribute values are.
    NSData *bufferText = nil;
    NSMutableDictionary<NSString *, id> *attributeValues = nil;

    if (self.textView != nil) {
        bufferText = [self.textView.string dataUsingEncoding:NSUTF8StringEncoding];
    } else {
        attributeValues = [NSMutableDictionary dictionary];
        for (NSAttributeDescription *attribute in entity.attributesByName.allValues) {
            if ([attribute.name isEqualToString:@"name"] ||
                [attribute.name isEqualToString:@"sourceText"]) {
                // The new decl gets its own name; sourceText is regenerated
                // by the store's codec from the copied attributes, so the new
                // decl's text header carries the NEW name.
                continue;
            }
            id value = [original valueForKey:attribute.name];
            if (value != nil) {
                attributeValues[attribute.name] = value;
            }
        }
    }

    NSManagedObject *sourceFile = [original valueForKey:@"sourceFile"];

    // 2. Transfer semantics: the original (and anything else in this
    //    document's private context) reverts to its last saved state...
    [context processPendingChanges];
    [context rollback];

    // 3. ...and a new decl is created with the captured content, in the same
    //    source file as the original.
    UDDeclBase *newDecl = [NSEntityDescription insertNewObjectForEntityForName:entity.name
                                                          inManagedObjectContext:context];
    newDecl.name = newName;
    if (sourceFile != nil && sourceFile.managedObjectContext == context) {
        [newDecl setValue:sourceFile forKey:@"sourceFile"];
    }

    if (bufferText != nil) {
        // Raw-text transfer: keep only the body (from the first brace on).
        // The store/manager prepend the "type newname" header themselves, so
        // stripping the old header here is what gives the new decl a correct
        // one instead of a stale copy naming the original.
        NSData *body = bufferText;
        NSString *asString = [[NSString alloc] initWithData:bufferText encoding:NSUTF8StringEncoding];
        NSRange brace = [asString rangeOfString:@"{"];
        if (brace.location != NSNotFound) {
            body = [[asString substringFromIndex:brace.location] dataUsingEncoding:NSUTF8StringEncoding];
        }
        newDecl.sourceText = body;
    } else {
        [attributeValues enumerateKeysAndObjectsUsingBlock:^(NSString *key, id value, BOOL *stop) {
            [newDecl setValue:value forKey:key];
        }];
    }

    // 4. Persist. Only the new decl is dirty at this point, so this save
    //    creates exactly one decl and touches nothing else.
    if (![context save:error]) {
        [context rollback];
        return nil;
    }

    // The buffer's identity has effectively changed; the caller re-opens the
    // editor on the new decl, so the old undo history no longer applies.
    [context.undoManager removeAllActions];
    [self updateChangeCount:NSChangeCleared];
    return newDecl;
}

- (void)setTextView:(NSTextView *)textView {
    if (_textView != nil) {
        [[NSNotificationCenter defaultCenter] removeObserver:self
                                                        name:NSTextDidChangeNotification
                                                      object:_textView];
    }

    _textView = textView;
    if (textView && self.textContent) {
        [textView.textStorage beginEditing];
        [textView.textStorage
            replaceCharactersInRange:NSMakeRange(0, textView.textStorage.length)
                          withString:self.textContent];
        [textView.textStorage endEditing];
    }
    textView.undoManager.levelsOfUndo = 50;

    if (textView != nil) {
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(_textViewTextDidChange:)
                                                     name:NSTextDidChangeNotification
                                                   object:textView];
    }
}

@end
