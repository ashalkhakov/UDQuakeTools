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

/// Builds a complete, ready-to-use Core Data stack (model + coordinator +
/// UDDeclIncrementalStore + main-queue context with an undo manager) bound to
/// the given decl manager. This is the single entry point editors use to pull
/// decl entities for editing and push their changes back.
+ (nullable NSManagedObjectContext *)newEditingContextForDeclManager:(idDeclManager *)declManager
                                                                error:(NSError * _Nullable * _Nullable)error;

/// Returns the current on-disk-equivalent source text for the decl backing
/// the given managed object, computed live from idDeclManager (by asking the
/// underlying idDecl to unparse itself). Used by UDDeclBase to populate its
/// transient sourceText attribute after a fetch, since transient attributes
/// are never faulted in through -newValuesForObjectWithID:withContext:error:.
- (nullable NSData *)ud_currentSourceTextForObjectID:(NSManagedObjectID *)objectID error:(NSError * _Nullable * _Nullable)error;

@end
