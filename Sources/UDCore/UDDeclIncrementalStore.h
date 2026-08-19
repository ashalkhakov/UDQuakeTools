#import <CoreData/CoreData.h>

@class idDeclManager;

extern NSString * const UDDeclIncrementalStoreType;
extern NSString * const UDDeclIncrementalStoreConfigureDeclManager;
extern NSString * const UDDeclIncrementalStoreConfigureDebugEnabled;

typedef enum {
    UDDeclIncrementalStoreUnsupportedResultType = 1,
    UDDeclIncrementalStoreUnsupportedRequestType = 2,
    UDDeclIncrementalStoreEntityDoesNotExist = 3,
    UDDeclIncrementalStoreDeclNotFound = 4,
    UDDeclIncrementalStoreDeclOperationFailed = 5,
    UDDeclIncrementalStoreReadOnlyEntity = 6,
} UDDeclIncrementalStoreError;

@interface UDDeclIncrementalStore : NSIncrementalStore

/// Registers this class with NSPersistentStoreCoordinator under
/// UDDeclIncrementalStoreType. Safe to call repeatedly; called automatically
/// by +newEditingContextForDeclManager:error:.
+ (void)registerStoreType;

/// The merged managed object model for DeclModel.xcdatamodeld, loaded from the
/// bundle that contains this class.
+ (nullable NSManagedObjectModel *)managedObjectModel;

/// Builds the shared half of the stack: model + coordinator with a
/// UDDeclIncrementalStore bound to the given decl manager. One coordinator is
/// shared by all editing contexts of a workspace; each editor/document gets
/// its own context over it (see +newEditingContextForCoordinator:), so every
/// document can be saved independently of the others.
+ (nullable NSPersistentStoreCoordinator *)newStoreCoordinatorForDeclManager:(idDeclManager *)declManager
                                                                       error:(NSError * _Nullable * _Nullable)error;

/// A fresh main-queue editing context (with its own NSUndoManager) over the
/// given coordinator. Contexts are independent: each one only saves its own
/// changes, and unsaved edits in one are invisible to the others — the
/// VSCode-style "one dirty buffer per open document" model.
+ (NSManagedObjectContext *)newEditingContextForCoordinator:(NSPersistentStoreCoordinator *)coordinator;

/// Convenience: coordinator + one context in a single call (used by tests and
/// one-shot tools).
+ (nullable NSManagedObjectContext *)newEditingContextForDeclManager:(idDeclManager *)declManager
                                                                error:(NSError * _Nullable * _Nullable)error;

/// Returns the current on-disk-equivalent source text for the decl backing
/// the given managed object, computed live from idDeclManager (by asking the
/// underlying idDecl to unparse itself). Used by UDDeclBase to populate its
/// transient sourceText attribute after a fetch, since transient attributes
/// are never faulted in through -newValuesForObjectWithID:withContext:error:.
- (nullable NSData *)ud_currentSourceTextForObjectID:(NSManagedObjectID *)objectID error:(NSError * _Nullable * _Nullable)error;

@end
