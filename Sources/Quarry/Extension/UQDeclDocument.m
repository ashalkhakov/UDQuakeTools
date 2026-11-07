/*---------------------------------------------------------------------------------------------
 *  UQDeclDocument.m
 *--------------------------------------------------------------------------------------------*/

#import "UQDeclDocument.h"
#import "UDDeclDocument.h"
#import "UDDeclItem.h"
#import "UDDeclManagedObjects.h"
#import "UDWorkspace.h"
#import "idDeclManager.h"

/// The types Quarry has a structured editor for (UDBaseEditorViewController's).
static BOOL UQHasStructuredEditor(declType_t type) {
    switch (type) {
    case DECL_PDA: case DECL_TABLE: case DECL_SKIN: case DECL_ENTITYDEF: case DECL_MAPDEF: case DECL_SOUND:
    case DECL_PARTICLE: case DECL_FX: case DECL_AF: case DECL_MATERIAL:
        return YES;
    default:
        return NO;
    }
}

@implementation UQDeclDocument

+ (BOOL)isStructuredDeclType:(NSString *)typeName inWorkspace:(UDWorkspace *)workspace {
    declType_t type = [workspace.declManager declTypeFromName:typeName];
    if ((int)type < 0 || (int)type >= [workspace.declManager numDeclTypes] || !UQHasStructuredEditor(type)) return NO;
    NSPersistentStoreCoordinator *coordinator = workspace.declStoreCoordinator;
    return coordinator && [UDDeclBase ud_entityNameForDeclTypeName:typeName inModel:coordinator.managedObjectModel] != nil;
}

- (instancetype)initWithDeclType:(NSString *)typeName name:(NSString *)name inWorkspace:(UDWorkspace *)workspace error:(NSError **)error {
    if (!(self = [super init])) return nil;
    declType_t type = [workspace.declManager declTypeFromName:typeName];
    _workspace = workspace;
    _declDocument = [[UDDeclDocument alloc] initWithType:type name:name inWorkspace:workspace error:error];
    if (!_declDocument.declObject) return nil;
    // it reads its text; the URL is no file's
    if (![_declDocument readFromURL:[NSURL URLWithString:@"http://localhost/unused.txt"] ofType:@"" error:error]) return nil;
    _item = [[UDDeclItem alloc] initWithType:type declName:name path:[NSString stringWithFormat:@"%@/%@", typeName, name]];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_contextDidChange:)
                                                 name:NSManagedObjectContextObjectsDidChangeNotification
                                               object:_declDocument.editingContext];
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)_contextDidChange:(NSNotification *)note {
    [[NSNotificationCenter defaultCenter] postNotificationName:UDCustomDocumentDidChangeNotification object:self];
}

// ---------------------------------------------------------------------------
// MARK: - UDCustomDocument
// ---------------------------------------------------------------------------

- (NSUndoManager *)undoManager {
    return _declDocument.editingContext.undoManager;
}

- (BOOL)isEdited {
    return _declDocument.editingContext.hasChanges;
}

- (BOOL)saveCustomDocument:(NSError **)error {
    // through the store into the decl manager, which writes the savepath
    if (![_declDocument writeToURL:[NSURL URLWithString:@"http://localhost/unused.txt"] ofType:@"" error:error]) return NO;
    [[NSNotificationCenter defaultCenter] postNotificationName:UDCustomDocumentDidChangeNotification object:self];
    return YES;
}

- (BOOL)revertCustomDocument:(NSError **)error {
    // its edits dropped, and their undo with them (-rollback clears it)
    NSManagedObjectContext *context = _declDocument.editingContext;
    [context rollback];
    [context refreshObject:_declDocument.declObject mergeChanges:NO];
    [context processPendingChanges];
    [context.undoManager removeAllActions];
    [[NSNotificationCenter defaultCenter] postNotificationName:UDCustomDocumentDidChangeNotification object:self];
    return YES;
}

- (NSString *)textOfDocument {
    NSData *text = [_declDocument.declObject ud_currentText:NULL];
    NSString *string = text ? [[NSString alloc] initWithData:text encoding:NSUTF8StringEncoding] : nil;
    return string ? [_declDocument editorTextFromFileText:string] : nil;
}

- (BOOL)applyText:(NSString *)text error:(NSError **)error {
    NSData *data = [[_declDocument fileTextFromEditorText:text] dataUsingEncoding:NSUTF8StringEncoding];
    return [_declDocument.declObject ud_applyText:data error:error];
}

@end
