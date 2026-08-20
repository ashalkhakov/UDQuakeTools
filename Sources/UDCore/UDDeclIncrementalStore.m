/*
 * SPDX-License-Identifier: GPL-2.0-or-later
 * UDDeclIncrementalStore.m
 *
 * Bridges Core Data to idDeclManager. The manager is a dumb text repository;
 * this store is where decl text meets structure: on fault it parses the raw
 * text through the entity class's codec (+ud_parseValuesFromText:...), and on
 * save it rebuilds the text through +ud_textByUnparsingName:values: and hands
 * it back to the manager (updateDecl/createNewDecl/renameDecl/moveDecl/
 * removeDecl, then writeDecls).
 *
 * Everything is driven by the managed object model:
 *  - A "decl entity" is any entity whose name follows the convention
 *    "Decl" + capitalized decl type name (DeclMaterial ↔ material). Its
 *    objectID reference object is simply the decl name.
 *  - A to-many relationship between two decl entities (DeclPDA.audios) is a
 *    list of referenced decl names inside the owning decl's text.
 *  - Owned sub-structures with no identity of their own (particle stages)
 *    are NOT entities: they live in a transient attribute on their decl
 *    entity (DeclParticle.stages), populated from the decl text on fetch
 *    and unparsed back through the codec on save.
 *  - DeclFile and DeclType are read-mostly views over manager bookkeeping.
 */

#import "UDDeclIncrementalStore.h"

#import "idDeclManager.h"
#import "idFileSystem.h"
#import "UDDeclManagedObjects.h"
#import "UDDeclType.h"
#import "UDWorkspace.h"

NSString * const UDDeclIncrementalStoreType = @"UDDeclIncrementalStore";
NSString * const UDDeclIncrementalStoreConfigureDeclManager = @"UDDeclIncrementalStoreConfigureDeclManager";
NSString * const UDDeclIncrementalStoreConfigureDebugEnabled = @"UDDeclIncrementalStoreConfigureDebugEnabled";

static NSString * const UDDeclIncrementalStoreDomain = @"UDDeclIncrementalStore";

static NSString * const UDDeclFileEntityName = @"DeclFile";
static NSString * const UDDeclTypeEntityName = @"DeclType";
static NSString * const UDDeclBaseEntityName = @"DeclBase";

@implementation UDDeclIncrementalStore {
    idDeclManager *_declManager;
    BOOL _debugLog;
}

#pragma mark - Stack building

+ (void)registerStoreType {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        [NSPersistentStoreCoordinator registerStoreClass:self forStoreType:UDDeclIncrementalStoreType];
    });
}

+ (NSManagedObjectModel *)managedObjectModel {
    static NSManagedObjectModel *model;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        // Xcode builds compile the model to momd/mom. On GNUstep there is no
        // momc; FreeCoreData's NSManagedObjectModel reads the .xcdatamodel(d)
        // XML directly, so fall back to the uncompiled model resource (which
        // the GNUstep app makefiles bundle as-is). bundleForClass: may
        // resolve to the main bundle for classes living in a plain library,
        // so both bundles are searched.
        NSArray<NSString *> *extensions = @[@"momd", @"mom", @"xcdatamodeld", @"xcdatamodel"];
        NSMutableArray<NSBundle *> *bundles = [NSMutableArray array];
        NSBundle *classBundle = [NSBundle bundleForClass:[UDDeclIncrementalStore class]];
        if (classBundle != nil) {
            [bundles addObject:classBundle];
        }
        if (![bundles containsObject:[NSBundle mainBundle]] && [NSBundle mainBundle] != nil) {
            [bundles addObject:[NSBundle mainBundle]];
        }

        for (NSBundle *bundle in bundles) {
            for (NSString *extension in extensions) {
                NSURL *modelURL = [bundle URLForResource:@"DeclModel" withExtension:extension];
                if ([modelURL.pathExtension isEqualToString:@"xcdatamodeld"]) {
                    // the versioned container holds the actual model
                    modelURL = [modelURL URLByAppendingPathComponent:@"DeclModel.xcdatamodel"];
                }
                if (modelURL != nil) {
                    model = [[NSManagedObjectModel alloc] initWithContentsOfURL:modelURL];
                }
                if (model != nil) {
                    break;
                }
            }
            if (model != nil) {
                break;
            }
        }
        if (model == nil) {
            model = [NSManagedObjectModel mergedModelFromBundles:bundles];
        }
    });
    return model;
}

+ (NSPersistentStoreCoordinator *)newStoreCoordinatorForDeclManager:(idDeclManager *)declManager
                                                              error:(NSError **)error {
    [self registerStoreType];

    NSManagedObjectModel *model = [self managedObjectModel];
    if (model == nil) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:UDDeclIncrementalStoreDomain
                                          code:UDDeclIncrementalStoreEntityDoesNotExist
                                      userInfo:@{NSLocalizedDescriptionKey: @"Could not load DeclModel managed object model"}];
        }
        return nil;
    }

    NSPersistentStoreCoordinator *coordinator =
        [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:model];

    // The URL is never dereferenced; the store is backed by idDeclManager.
    NSURL *placeholderURL = [NSURL URLWithString:@"uddecl://decl-manager"];
    NSPersistentStore *store =
        [coordinator addPersistentStoreWithType:UDDeclIncrementalStoreType
                                  configuration:nil
                                            URL:placeholderURL
                                        options:@{UDDeclIncrementalStoreConfigureDeclManager: declManager}
                                          error:error];
    if (store == nil) {
        return nil;
    }
    return coordinator;
}

+ (NSManagedObjectContext *)newEditingContextForCoordinator:(NSPersistentStoreCoordinator *)coordinator {
    NSManagedObjectContext *context =
        [[NSManagedObjectContext alloc] initWithConcurrencyType:NSMainQueueConcurrencyType];
    context.persistentStoreCoordinator = coordinator;
    context.undoManager = [[NSUndoManager alloc] init];
    return context;
}

+ (NSManagedObjectContext *)newEditingContextForDeclManager:(idDeclManager *)declManager
                                                       error:(NSError **)error {
    NSPersistentStoreCoordinator *coordinator = [self newStoreCoordinatorForDeclManager:declManager error:error];
    if (coordinator == nil) {
        return nil;
    }
    return [self newEditingContextForCoordinator:coordinator];
}

#pragma mark - Setup

- (id)initWithPersistentStoreCoordinator:(NSPersistentStoreCoordinator *)coordinator
                       configurationName:(NSString *)name
                                     URL:(NSURL *)url
                                 options:(NSDictionary *)options {

    self = [super initWithPersistentStoreCoordinator:coordinator configurationName:name URL:url options:options];
    if (self) {
        _declManager = options[UDDeclIncrementalStoreConfigureDeclManager];

        NSNumber *debugEnabled = options[UDDeclIncrementalStoreConfigureDebugEnabled];
        if (debugEnabled != nil && debugEnabled.boolValue) {
            _debugLog = YES;
        }
    }
    return self;
}

- (BOOL)loadMetadata:(NSError **)error {
    [self setMetadata:@{
       NSStoreUUIDKey: @"1",
       NSStoreTypeKey: UDDeclIncrementalStoreType
     }];
    return YES;
}

#pragma mark - Model introspection

- (BOOL)_declType:(declType_t *)outType forEntity:(NSEntityDescription *)entity error:(NSError **)error {
    NSString *typeName = UDDeclTypeNameForDeclEntityName(entity.name);
    declType_t type = typeName != nil ? [_declManager declTypeFromName:typeName] : DECL_MAX_TYPES;

    if (type == DECL_MAX_TYPES) {
        if (error != NULL) {
            NSString *message = [NSString stringWithFormat:@"Entity \"%@\" is not a recognized decl type", entity.name];
            *error = [NSError errorWithDomain:UDDeclIncrementalStoreDomain
                                          code:UDDeclIncrementalStoreEntityDoesNotExist
                                      userInfo:@{NSLocalizedDescriptionKey: message}];
        }
        return NO;
    }

    *outType = type;
    return YES;
}

- (BOOL)_isDeclEntity:(NSEntityDescription *)entity {
    if (entity.isAbstract) {
        return NO;
    }
    declType_t type;
    return [self _declType:&type forEntity:entity error:NULL];
}

- (NSArray<NSEntityDescription *> *)_concreteDeclEntities {
    NSMutableArray<NSEntityDescription *> *entities = [NSMutableArray array];
    for (NSEntityDescription *entity in self.persistentStoreCoordinator.managedObjectModel.entities) {
        if ([self _isDeclEntity:entity]) {
            [entities addObject:entity];
        }
    }
    return entities;
}

- (NSEntityDescription *)_entityForDeclType:(declType_t)type {
    // Scan the model rather than deriving the entity name from the type name:
    // entity names capitalize acronyms (DeclPDA) while type names don't
    // ("pda"), so name derivation is not reliable in this direction.
    for (NSEntityDescription *entity in self.persistentStoreCoordinator.managedObjectModel.entities) {
        if (entity.isAbstract) {
            continue;
        }
        declType_t entityType;
        if ([self _declType:&entityType forEntity:entity error:NULL] && entityType == type) {
            return entity;
        }
    }
    return nil;
}

#pragma mark - Decl text access

- (idDeclBase *)_declForEntity:(NSEntityDescription *)entity name:(NSString *)name error:(NSError **)error {
    declType_t type;
    if (![self _declType:&type forEntity:entity error:error]) {
        return nil;
    }
    idDeclBase *decl = [_declManager declByName:name type:type forceParse:YES error:error];
    if (decl == nil && error != NULL && *error == nil) {
        *error = [self _errorWithCode:UDDeclIncrementalStoreDeclNotFound
                               message:[NSString stringWithFormat:@"Decl \"%@\" not found", name]];
    }
    return decl;
}

- (NSData *)_rawTextForDecl:(idDeclBase *)decl {
    NSMutableData *buffer = [[NSMutableData alloc] init];
    [decl text:buffer];
    if (buffer.length > 0) {
        [buffer setLength:buffer.length - 1]; // strip the trailing NUL
    }
    return buffer;
}

/// Runs the entity class's codec over the decl's current text. Returns nil
/// for raw-text-only entities (no codec).
- (NSDictionary<NSString *, id> *)_parsedValuesForEntity:(NSEntityDescription *)entity
                                                     decl:(idDeclBase *)decl
                                                    error:(NSError **)error {
    Class cls = NSClassFromString(entity.managedObjectClassName);
    if (![cls isSubclassOfClass:[UDDeclBase class]]) {
        return nil;
    }
    return [cls ud_parseValuesFromText:[self _rawTextForDecl:decl]
                                  name:[decl name]
                              fileName:[decl fileName]
                               lineNum:[decl lineNum]
                            fileSystem:_declManager.workspace.fileSystem
                                 error:error];
}

#pragma mark - Object ID helpers

- (NSManagedObjectID *)_objectIDForEntityName:(NSString *)entityName referenceObject:(NSString *)referenceObject {
    NSEntityDescription *entity = self.persistentStoreCoordinator.managedObjectModel.entitiesByName[entityName];
    if (entity == nil || referenceObject == nil) {
        return nil;
    }
    return [self newObjectIDForEntity:entity referenceObject:referenceObject];
}

- (NSManagedObjectID *)_fileObjectIDForFileName:(NSString *)fileName {
    if (fileName.length == 0) {
        return nil;
    }
    return [self _objectIDForEntityName:UDDeclFileEntityName referenceObject:fileName];
}

- (NSManagedObjectID *)_typeObjectIDForDeclType:(declType_t)type {
    NSString *typeName = [_declManager declNameFromType:type];
    return [self _objectIDForEntityName:UDDeclTypeEntityName referenceObject:typeName];
}

#pragma mark - Request dispatch

- (id)executeRequest:(NSPersistentStoreRequest *)request
         withContext:(NSManagedObjectContext *)context
               error:(NSError **)error {

    switch (request.requestType) {
        case NSFetchRequestType:
            return [self _executeFetchRequest:(NSFetchRequest *)request withContext:context error:error];

        case NSSaveRequestType:
            return [self _executeSaveRequest:(NSSaveChangesRequest *)request withContext:context error:error];

        default: {
            NSString *message = [NSString stringWithFormat:@"Unknown request type %lu", (unsigned long)request.requestType];
            if (error != NULL) {
                *error = [NSError errorWithDomain:UDDeclIncrementalStoreDomain
                                              code:UDDeclIncrementalStoreUnsupportedRequestType
                                          userInfo:@{NSLocalizedDescriptionKey: message}];
            }
            return nil;
        }
    }
}

- (NSArray *)obtainPermanentIDsForObjects:(NSArray *)objects error:(NSError **)error {
    NSMutableArray *ids = [NSMutableArray arrayWithCapacity:objects.count];

    for (NSManagedObject *object in objects) {
        NSString *referenceObject = nil;
        NSEntityDescription *entity = object.entity;

        if ([entity.name isEqualToString:UDDeclFileEntityName]) {
            referenceObject = [object valueForKey:@"fileName"];
        } else if ([entity.name isEqualToString:UDDeclTypeEntityName]) {
            referenceObject = [object valueForKey:@"name"];
        } else if ([self _isDeclEntity:entity]) {
            referenceObject = [object valueForKey:@"name"];
        }

        if (referenceObject == nil) {
            if (error != NULL) {
                *error = [self _errorWithCode:UDDeclIncrementalStoreDeclOperationFailed
                                       message:[NSString stringWithFormat:@"Cannot derive an identity for a new %@ (missing name)", entity.name]];
            }
            return nil;
        }
        [ids addObject:[self newObjectIDForEntity:entity referenceObject:referenceObject]];
    }
    return ids;
}

#pragma mark - Fetching

- (id)_executeFetchRequest:(NSFetchRequest *)request
               withContext:(NSManagedObjectContext *)context
                     error:(NSError **)error {

    if (request.resultType != NSManagedObjectResultType &&
        request.resultType != NSManagedObjectIDResultType &&
        request.resultType != NSCountResultType) {

        if (error != NULL) {
            NSString *message = [NSString stringWithFormat:@"Unsupported result type for request %@", request];
            *error = [NSError errorWithDomain:UDDeclIncrementalStoreDomain
                                          code:UDDeclIncrementalStoreUnsupportedResultType
                                      userInfo:@{NSLocalizedDescriptionKey: message}];
        }
        return nil;
    }

    NSMutableArray<NSManagedObjectID *> *objectIDs = [NSMutableArray array];
    NSEntityDescription *entity = request.entity;
    NSString *entityName = entity.name;

    if ([entityName isEqualToString:UDDeclTypeEntityName]) {
        for (int i = 0; i < [_declManager numDeclTypes]; i++) {
            NSString *typeName = [_declManager declNameFromType:(declType_t)i];
            if ([typeName isEqualToString:@"bad type"]) {
                continue;
            }
            NSManagedObjectID *objectID = [self _typeObjectIDForDeclType:(declType_t)i];
            if (objectID != nil) {
                [objectIDs addObject:objectID];
            }
        }
    } else if ([entityName isEqualToString:UDDeclFileEntityName]) {
        for (NSString *fileName in [_declManager loadedDeclFileNames]) {
            NSManagedObjectID *objectID = [self _fileObjectIDForFileName:fileName];
            if (objectID != nil) {
                [objectIDs addObject:objectID];
            }
        }
    } else {
        NSArray<NSEntityDescription *> *entitiesToScan = [entityName isEqualToString:UDDeclBaseEntityName]
            ? [self _concreteDeclEntities]
            : @[entity];

        for (NSEntityDescription *concreteEntity in entitiesToScan) {
            declType_t type;
            if (![self _declType:&type forEntity:concreteEntity error:NULL]) {
                continue;
            }
            // Listing only needs the decl names to mint objectIDs; the text
            // is loaded/parsed lazily when an individual object is faulted.
            for (idDeclBase *decl in [_declManager declsOfType:type forceParse:NO]) {
                [objectIDs addObject:[self newObjectIDForEntity:concreteEntity referenceObject:[decl name]]];
            }
        }
    }

    NSMutableArray *results = [NSMutableArray arrayWithCapacity:objectIDs.count];
    for (NSManagedObjectID *objectID in objectIDs) {
        NSError *objectError = nil;
        NSManagedObject *object = [context existingObjectWithID:objectID error:&objectError];
        if (object == nil) {
            if (_debugLog) {
                NSLog(@"Unable to load object for %@ (%@)", objectID, objectError.localizedDescription);
            }
            continue;
        }
        if (!request.predicate || [request.predicate evaluateWithObject:object]) {
            [results addObject:object];
        }
    }

    [results sortUsingDescriptors:request.sortDescriptors];

    switch (request.resultType) {
        case NSManagedObjectResultType:
            return results;
        case NSManagedObjectIDResultType:
            return [results valueForKeyPath:@"objectID"];
        case NSCountResultType:
            return @[@(results.count)];
        default:
            return nil; // unreachable, validated above
    }
}

#pragma mark - Faulting

- (NSIncrementalStoreNode *)newValuesForObjectWithID:(NSManagedObjectID *)objectID
                                          withContext:(NSManagedObjectContext *)context
                                                error:(NSError **)error {

    NSEntityDescription *entity = objectID.entity;
    NSString *entityName = entity.name;
    NSString *referenceObject = [self referenceObjectForObjectID:objectID];
    NSDictionary *values = nil;

    if ([entityName isEqualToString:UDDeclTypeEntityName]) {
        declType_t type = [_declManager declTypeFromName:referenceObject];
        if (type == DECL_MAX_TYPES) {
            if (error != NULL) {
                *error = [self _errorWithCode:UDDeclIncrementalStoreDeclNotFound
                                       message:[NSString stringWithFormat:@"Unknown decl type \"%@\"", referenceObject]];
            }
            return nil;
        }
        values = @{ @"name": referenceObject, @"type": @((int32_t)type) };

    } else if ([entityName isEqualToString:UDDeclFileEntityName]) {
        int checksum = 0;
        NSUInteger timestamp = 0;
        [_declManager declFileInfoForName:referenceObject checksum:&checksum timestamp:&timestamp];
        values = @{ @"fileName": referenceObject, @"checksum": @(checksum), @"timestamp": @((int64_t)timestamp) };

    } else {
        idDeclBase *decl = [self _declForEntity:entity name:referenceObject error:error];
        if (decl == nil) {
            return nil;
        }

        NSDictionary *parsed = [self _parsedValuesForEntity:entity decl:decl error:error];

        NSMutableDictionary *mutableValues = [NSMutableDictionary dictionary];
        mutableValues[@"name"] = [decl name];

        for (NSAttributeDescription *attribute in entity.attributesByName.allValues) {
            if (attribute.isTransient || [attribute.name isEqualToString:@"name"]) {
                continue;
            }
            id value = parsed[attribute.name] ?: attribute.defaultValue;
            // A missing attribute is simply OMITTED from the node — Core Data
            // then treats it as nil. NSNull is only the representation for
            // empty to-one RELATIONSHIPS; stuffing it into an attribute slot
            // leaks it into the row cache, and the first validateForUpdate:
            // on the object crashes with -[NSNull length] (seen with real
            // game emails that have no "image"/"date" field).
            if (value != nil && value != [NSNull null]) {
                mutableValues[attribute.name] = value;
            }
        }
        values = mutableValues;
    }

    return [[NSIncrementalStoreNode alloc] initWithObjectID:objectID withValues:values version:1];
}

- (id)newValueForRelationship:(NSRelationshipDescription *)relationship
              forObjectWithID:(NSManagedObjectID *)objectID
                  withContext:(NSManagedObjectContext *)context
                        error:(NSError **)error {

    NSEntityDescription *entity = objectID.entity;
    NSString *entityName = entity.name;
    NSString *referenceObject = [self referenceObjectForObjectID:objectID];
    NSString *relationshipName = relationship.name;

    if ([entityName isEqualToString:UDDeclFileEntityName]) {
        if ([relationshipName isEqualToString:@"decls"]) {
            return [self _declObjectIDsMatchingFileName:referenceObject];
        }
        return relationship.isToMany ? @[] : [NSNull null];
    }

    if ([entityName isEqualToString:UDDeclTypeEntityName]) {
        declType_t type = [_declManager declTypeFromName:referenceObject];
        if ([relationshipName isEqualToString:@"decls"]) {
            return [self _declObjectIDsForType:type];
        }
        return relationship.isToMany ? @[] : [NSNull null];
    }

    // A decl entity.
    if ([relationshipName isEqualToString:@"sourceFile"]) {
        idDeclBase *decl = [self _declForEntity:entity name:referenceObject error:error];
        NSManagedObjectID *fileObjectID = decl != nil ? [self _fileObjectIDForFileName:[decl fileName]] : nil;
        return fileObjectID ?: [NSNull null];
    }

    if ([relationshipName isEqualToString:@"type"]) {
        declType_t type;
        if (![self _declType:&type forEntity:entity error:error]) {
            return nil;
        }
        return [self _typeObjectIDForDeclType:type] ?: [NSNull null];
    }

    if (relationship.isToMany) {
        idDeclBase *decl = [self _declForEntity:entity name:referenceObject error:error];
        if (decl == nil) {
            return @[];
        }
        NSDictionary *parsed = [self _parsedValuesForEntity:entity decl:decl error:error];
        NSArray *children = parsed[relationshipName];

        NSMutableArray<NSManagedObjectID *> *ids = [NSMutableArray arrayWithCapacity:[children count]];

        if ([self _isDeclEntity:relationship.destinationEntity]) {
            // Referenced child decls (pda_email etc.), by name.
            for (NSString *childName in children) {
                if ([childName isKindOfClass:[NSString class]] && childName.length > 0) {
                    [ids addObject:[self newObjectIDForEntity:relationship.destinationEntity referenceObject:childName]];
                }
            }
        }
        return ids;
    }

    // To-one back-pointer from a child decl to the decl that references it
    // (e.g. DeclEmail.pda). This is the one place a scan is unavoidable: the
    // child's own text never names its owner (the reference direction in the
    // decl format is owner -> child, "pda_email <name>"), so there is no name
    // to hand to declByName:type: — the answer only exists in the owning
    // type's parsed child lists. It runs only when someone actually faults
    // the back-pointer of a child decl.
    NSRelationshipDescription *inverse = relationship.inverseRelationship;
    if (inverse != nil && inverse.isToMany && [self _isDeclEntity:relationship.destinationEntity]) {
        NSEntityDescription *ownerEntity = relationship.destinationEntity;
        declType_t ownerType;
        if ([self _declType:&ownerType forEntity:ownerEntity error:NULL]) {
            for (idDeclBase *ownerDecl in [_declManager declsOfType:ownerType forceParse:YES]) {
                NSDictionary *parsed = [self _parsedValuesForEntity:ownerEntity decl:ownerDecl error:NULL];
                for (NSString *childName in parsed[inverse.name]) {
                    if ([childName isKindOfClass:[NSString class]] &&
                        [childName caseInsensitiveCompare:referenceObject] == NSOrderedSame) {
                        return [self newObjectIDForEntity:ownerEntity referenceObject:[ownerDecl name]];
                    }
                }
            }
        }
        return [NSNull null];
    }

    return relationship.isToMany ? @[] : [NSNull null];
}

- (NSArray<NSManagedObjectID *> *)_declObjectIDsForType:(declType_t)type {
    NSMutableArray<NSManagedObjectID *> *ids = [NSMutableArray array];
    NSEntityDescription *entity = [self _entityForDeclType:type];
    if (entity == nil) {
        return ids;
    }
    // Names only — no need to load/parse any decl text here.
    for (idDeclBase *decl in [_declManager declsOfType:type forceParse:NO]) {
        [ids addObject:[self newObjectIDForEntity:entity referenceObject:[decl name]]];
    }
    return ids;
}

- (NSArray<NSManagedObjectID *> *)_declObjectIDsMatchingFileName:(NSString *)fileName {
    // The manager keeps a per-file decl list, so this is a direct lookup —
    // no sweep over the per-type lists and no parsing. Decls of types
    // without a model entity are skipped.
    NSMutableArray<NSManagedObjectID *> *ids = [NSMutableArray array];
    for (idDeclBase *decl in [_declManager declsInFileName:fileName]) {
        NSEntityDescription *entity = [self _entityForDeclType:[decl type]];
        if (entity != nil) {
            [ids addObject:[self newObjectIDForEntity:entity referenceObject:[decl name]]];
        }
    }
    return ids;
}

#pragma mark - Live source text (backing the transient sourceText attribute)

- (NSData *)ud_currentSourceTextForObjectID:(NSManagedObjectID *)objectID error:(NSError **)error {
    NSEntityDescription *entity = objectID.entity;
    if (![self _isDeclEntity:entity]) {
        return nil;
    }

    NSString *referenceObject = [self referenceObjectForObjectID:objectID];
    idDeclBase *decl = [self _declForEntity:entity name:referenceObject error:error];
    if (decl == nil) {
        return nil;
    }
    return [self _rawTextForDecl:decl];
}

#pragma mark - Saving

- (id)_executeSaveRequest:(NSSaveChangesRequest *)request
              withContext:(NSManagedObjectContext *)context
                    error:(NSError **)error {

    NSSet<NSManagedObject *> *inserted = request.insertedObjects ?: [NSSet set];
    NSSet<NSManagedObject *> *updated = request.updatedObjects ?: [NSSet set];
    NSSet<NSManagedObject *> *deleted = request.deletedObjects ?: [NSSet set];

    // 1. Create manager records for inserted decls.
    for (NSManagedObject *object in inserted) {
        if ([self _isDeclEntity:object.entity]) {
            if (![self _createDeclForInsertedObject:object error:error]) {
                return nil;
            }
        }
    }

    // 2. Collect every decl whose text needs rebuilding. (Owned
    // sub-structures like particle stages live in transient attributes on
    // their decl entity, so replacing them marks the decl itself updated —
    // there is nothing else to chase here.)
    NSMutableSet<NSManagedObject *> *affectedDecls = [NSMutableSet set];
    NSMutableSet<NSManagedObject *> *changedObjects = [NSMutableSet setWithSet:inserted];
    [changedObjects unionSet:updated];

    for (NSManagedObject *object in changedObjects) {
        if ([self _isDeclEntity:object.entity]) {
            [affectedDecls addObject:object];
        }
    }

    // 3. Apply renames / moves / text updates.
    for (NSManagedObject *object in affectedDecls) {
        if (![self _applyChangesForDeclObject:object isInserted:[inserted containsObject:object] error:error]) {
            return nil;
        }
    }

    // 4. Deletions.
    for (NSManagedObject *object in deleted) {
        if (![self _isDeclEntity:object.entity]) {
            continue;
        }
        declType_t type;
        if (![self _declType:&type forEntity:object.entity error:error]) {
            return nil;
        }
        NSString *name = [[object committedValuesForKeys:@[@"name"]] objectForKey:@"name"] ?: [object valueForKey:@"name"];
        if (![_declManager removeDecl:type name:name]) {
            if (error != NULL) {
                *error = [self _errorWithCode:UDDeclIncrementalStoreDeclOperationFailed
                                       message:[NSString stringWithFormat:@"Could not remove decl \"%@\"", name]];
            }
            return nil;
        }
    }

    if (![_declManager writeDecls:error]) {
        return nil;
    }

    return @[];
}

- (BOOL)_createDeclForInsertedObject:(NSManagedObject *)object error:(NSError **)error {
    declType_t type;
    if (![self _declType:&type forEntity:object.entity error:error]) {
        return NO;
    }

    NSString *name = [object valueForKey:@"name"];
    if (name.length == 0) {
        if (error != NULL) {
            *error = [self _errorWithCode:UDDeclIncrementalStoreDeclOperationFailed
                                   message:@"Cannot create a decl without a name"];
        }
        return NO;
    }

    NSString *fileName = [object valueForKeyPath:@"sourceFile.fileName"];
    if (fileName.length == 0) {
        fileName = [_declManager defaultFileNameForDeclType:type name:name];
    }
    if (fileName.length == 0) {
        *error = [self _errorWithCode:UDDeclIncrementalStoreDeclOperationFailed
                               message:[NSString stringWithFormat:@"Unable to find a suitable file for decl \"%@\"", name]];
    }

    idDeclBase *decl = [_declManager createNewDecl:type name:name fileName:fileName];
    if (decl == nil) {
        if (error != NULL) {
            *error = [self _errorWithCode:UDDeclIncrementalStoreDeclOperationFailed
                                   message:[NSString stringWithFormat:@"Could not create decl \"%@\"", name]];
        }
        return NO;
    }
    return YES;
}

- (BOOL)_applyChangesForDeclObject:(NSManagedObject *)object isInserted:(BOOL)isInserted error:(NSError **)error {
    NSEntityDescription *entity = object.entity;
    declType_t type;
    if (![self _declType:&type forEntity:entity error:error]) {
        return NO;
    }

    NSString *currentName = [object valueForKey:@"name"];
    NSString *lookupName = currentName;

    if (!isInserted) {
        NSString *committedName = [[object committedValuesForKeys:@[@"name"]] objectForKey:@"name"];
        if (committedName.length > 0 && ![committedName isEqualToString:currentName]) {
            if (![_declManager renameDecl:type fromName:committedName toName:currentName]) {
                if (error != NULL) {
                    *error = [self _errorWithCode:UDDeclIncrementalStoreDeclOperationFailed
                                           message:[NSString stringWithFormat:@"Could not rename decl \"%@\" to \"%@\"", committedName, currentName]];
                }
                return NO;
            }
        }
    }

    idDeclBase *decl = [_declManager declByName:lookupName type:type forceParse:YES error:error];
    if (decl == nil) {
        if (error != NULL && *error == nil) {
            *error = [self _errorWithCode:UDDeclIncrementalStoreDeclNotFound
                                   message:[NSString stringWithFormat:@"Decl \"%@\" not found", lookupName]];
        }
        return NO;
    }

    NSString *newFileName = [object valueForKeyPath:@"sourceFile.fileName"];
    if (newFileName.length > 0 && ![[decl fileName] isEqualToString:newFileName]) {
        [_declManager moveDecl:type name:lookupName toFileName:newFileName];
    }

    Class cls = NSClassFromString(entity.managedObjectClassName);
    NSData *newSourceText = nil;

    // If the raw sourceText itself was edited (text editor), it wins over the
    // structured attributes — otherwise a text edit of a structured decl
    // (table/skin/particle) would be silently regenerated from stale
    // attribute values and discarded.
    id editedText = [object changedValues][@"sourceText"];
    if ([editedText isKindOfClass:[NSData class]]) {
        newSourceText = editedText;
    }

    if (newSourceText == nil && [cls isSubclassOfClass:[UDDeclBase class]]) {
        // Parse the decl's current text first so child decl lists can keep
        // their existing (file) order for children that remain.
        NSDictionary *currentValues = [self _parsedValuesForEntity:entity decl:decl error:NULL];
        NSDictionary *values = [self _codecValuesForDeclObject:object currentValues:currentValues];
        newSourceText = [cls ud_textByUnparsingName:[decl name] values:values error:error];
    }

    if (newSourceText == nil) {
        // Raw-text entity: the transient sourceText attribute is authoritative.
        newSourceText = [object valueForKey:@"sourceText"];
    }

    if (newSourceText == nil && isInserted) {
        // Nothing structured and no text supplied: fall back to the entity's
        // default definition.
        NSString *typeName = [_declManager declNameFromType:type];
        NSString *body = [cls isSubclassOfClass:[UDDeclBase class]] ? [cls ud_defaultDefinition] : @"{\n}\n";
        newSourceText = [[NSString stringWithFormat:@"%@ %@ %@", typeName, [decl name], body]
                          dataUsingEncoding:NSUTF8StringEncoding];
    }

    if (newSourceText.length == 0) {
        return YES; // nothing further to persist; the decl already has default text.
    }

    NSMutableData *mutableText = [newSourceText mutableCopy];
    [mutableText appendBytes:"" length:1]; // manager expects NUL-terminated text
    if (![_declManager updateDecl:type name:[decl name] sourceText:mutableText]) {
        if (error != NULL) {
            *error = [self _errorWithCode:UDDeclIncrementalStoreDeclOperationFailed
                                   message:[NSString stringWithFormat:@"Could not update decl \"%@\"", [decl name]]];
        }
        return NO;
    }

    return YES;
}

/// Builds the codec values dictionary for a decl managed object: attribute
/// values straight from the object (including transient structured
/// attributes like DeclParticle.stages, which fall back to the freshly
/// parsed currentValues when unset), and child decl relationships as ordered
/// name arrays (preserving the existing order from currentValues).
- (NSDictionary<NSString *, id> *)_codecValuesForDeclObject:(NSManagedObject *)object
                                              currentValues:(NSDictionary *)currentValues {
    NSEntityDescription *entity = object.entity;
    NSMutableDictionary<NSString *, id> *values = [NSMutableDictionary dictionary];

    for (NSAttributeDescription *attribute in entity.attributesByName.allValues) {
        if ([attribute.name isEqualToString:@"name"] || [attribute.name isEqualToString:@"sourceText"]) {
            continue;
        }
        id value = [object valueForKey:attribute.name];
        if (value == nil && attribute.isTransient) {
            value = currentValues[attribute.name];
        }
        if (value != nil) {
            values[attribute.name] = value;
        }
    }

    for (NSRelationshipDescription *relationship in entity.relationshipsByName.allValues) {
        if (!relationship.isToMany) {
            continue;
        }

        if ([self _isDeclEntity:relationship.destinationEntity]) {
            NSSet<NSManagedObject *> *children = [object valueForKey:relationship.name];
            NSMutableSet<NSString *> *desired = [NSMutableSet setWithCapacity:children.count];
            for (NSManagedObject *child in children) {
                NSString *childName = [child valueForKey:@"name"];
                if (childName.length > 0) {
                    [desired addObject:childName.lowercaseString];
                }
            }

            // Keep the existing (file) order for children that remain.
            NSMutableArray<NSString *> *ordered = [NSMutableArray arrayWithCapacity:desired.count];
            NSMutableSet<NSString *> *present = [NSMutableSet set];
            for (NSString *existingName in currentValues[relationship.name]) {
                if (![existingName isKindOfClass:[NSString class]]) {
                    continue;
                }
                NSString *lower = existingName.lowercaseString;
                if ([desired containsObject:lower] && ![present containsObject:lower]) {
                    [ordered addObject:existingName];
                    [present addObject:lower];
                }
            }

            // Append newly added children, sorted by name for determinism.
            for (NSString *lower in [desired.allObjects sortedArrayUsingSelector:@selector(compare:)]) {
                if (![present containsObject:lower]) {
                    [ordered addObject:lower];
                    [present addObject:lower];
                }
            }
            values[relationship.name] = ordered;
        }
    }

    return values;
}

#pragma mark - Errors

- (NSError *)_errorWithCode:(UDDeclIncrementalStoreError)code message:(NSString *)message {
    return [NSError errorWithDomain:UDDeclIncrementalStoreDomain
                                code:code
                            userInfo:@{NSLocalizedDescriptionKey: message}];
}

@end
