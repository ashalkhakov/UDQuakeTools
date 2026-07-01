/*
 * SPDX-License-Identifier: GPL-2.0-or-later
 * Decl model manager implementation.
 */

#import "UDDeclManager.h"

#import "UDDeclParser.h"
#import "UDDeclType.h"

static NSSet<NSString *> *UDDeclManagerTextAssetExtensionsForGameType(UDGameType gameType) {
    return [UDDeclTypeRegistry sourceFileExtensionsForGameType:gameType];
}

static BOOL UDDeclManagerPathCanContainDecls(NSString *virtualPath, UDGameType gameType) {
    return [UDDeclManagerTextAssetExtensionsForGameType(gameType) containsObject:virtualPath.pathExtension.lowercaseString];
}

static NSString *UDDeclManagerNormalizedVirtualPath(NSString *virtualPath) {
    NSString *normalizedPath = [virtualPath stringByReplacingOccurrencesOfString:@"\\" withString:@"/"];
    while ([normalizedPath hasPrefix:@"/"]) {
        normalizedPath = [normalizedPath substringFromIndex:1];
    }
    return normalizedPath;
}

static NSArray<NSString *> *UDDeclManagerSourcePathsFromVirtualFileSystem(UDVirtualFileSystem *virtualFileSystem,
                                                                           NSError **error) {
    NSArray<UDVFSResolvedFile *> *visibleFiles = [virtualFileSystem visibleFilesWithExtensions:UDDeclManagerTextAssetExtensionsForGameType(virtualFileSystem.gameType)
                                                                                           error:error];
    if (!visibleFiles) {
        return nil;
    }

    NSMutableArray<NSString *> *paths = [NSMutableArray arrayWithCapacity:visibleFiles.count];
    for (UDVFSResolvedFile *resolved in visibleFiles) {
        [paths addObject:UDDeclManagerNormalizedVirtualPath(resolved.virtualPath)];
    }

    [paths sortUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
    return paths;
}

static NSComparisonResult UDDeclManagerCompareDeclDefinitions(id leftObject, id rightObject, void *context) {
    (void)context;
    UDDeclDefinition *left = (UDDeclDefinition *)leftObject;
    UDDeclDefinition *right = (UDDeclDefinition *)rightObject;

    NSComparisonResult typeResult = [left.declType compare:right.declType options:NSCaseInsensitiveSearch];
    if (typeResult != NSOrderedSame) {
        return typeResult;
    }

    NSComparisonResult nameResult = [left.declName compare:right.declName options:NSCaseInsensitiveSearch];
    if (nameResult != NSOrderedSame) {
        return nameResult;
    }

    return [left.sourceVirtualPath compare:right.sourceVirtualPath options:NSCaseInsensitiveSearch];
}

static UDDeclModel *UDDeclManagerRebuildDeclModelByApplyingWriteNotification(NSNotification *notification,
                                                                            UDDeclModel *existingModel,
                                                                            id<UDDeclPersistenceAdapter> persistenceAdapter,
                                                                            UDGameType gameType,
                                                                            NSError **error) {
    NSString *virtualPath = [notification.userInfo objectForKey:UDVFSNotificationVirtualPathKey];
    if (virtualPath.length == 0 || !UDDeclManagerPathCanContainDecls(virtualPath, gameType)) {
        return existingModel;
    }

    NSString *normalizedPath = UDDeclManagerNormalizedVirtualPath(virtualPath);

    NSMutableArray<UDDeclDefinition *> *definitions = [NSMutableArray arrayWithCapacity:existingModel.definitions.count + 8];
    for (UDDeclDefinition *definition in existingModel.definitions) {
        if (![definition.sourceVirtualPath isEqualToString:normalizedPath]) {
            [definitions addObject:definition];
        }
    }

    NSString *updatedText = [persistenceAdapter readDeclTextAtVirtualPath:normalizedPath error:nil];
    if (updatedText) {
        UDDeclParser *parser = [[UDDeclParser alloc] init];
        NSError *parseError = nil;
        NSArray<UDDeclDefinition *> *parsed = [parser parseDefinitionsFromText:updatedText
                                                              sourceVirtualPath:normalizedPath
                                                                          error:&parseError];
        if (!parsed) {
            if (error) {
                *error = parseError;
            }
            return nil;
        }
        [definitions addObjectsFromArray:parsed];
    }

    [definitions sortUsingFunction:UDDeclManagerCompareDeclDefinitions context:NULL];

    if (error) {
        *error = nil;
    }
    return [[UDDeclModel alloc] initWithDefinitions:definitions];
}

@implementation UDDeclManager

- (UDDeclModel *)buildDeclModelFromVirtualFileSystem:(UDVirtualFileSystem *)virtualFileSystem
                                                error:(NSError **)error {
    NSParameterAssert(virtualFileSystem != nil);

    UDVFSDeclPersistenceAdapter *adapter = [[UDVFSDeclPersistenceAdapter alloc] initWithVirtualFileSystem:virtualFileSystem];
    return [self buildDeclModelFromVirtualFileSystem:virtualFileSystem
                                  persistenceAdapter:adapter
                                                error:error];
}

- (UDDeclModel *)buildDeclModelFromVirtualFileSystem:(UDVirtualFileSystem *)virtualFileSystem
                                      persistenceAdapter:(id<UDDeclPersistenceAdapter>)persistenceAdapter
                                                    error:(NSError **)error {
    NSParameterAssert(virtualFileSystem != nil);
    NSParameterAssert(persistenceAdapter != nil);

    NSArray<NSString *> *sourcePaths = UDDeclManagerSourcePathsFromVirtualFileSystem(virtualFileSystem, error);
    if (!sourcePaths) {
        return nil;
    }

    UDDeclParser *parser = [[UDDeclParser alloc] init];
    NSMutableArray<UDDeclDefinition *> *definitions = [NSMutableArray array];

    for (NSString *sourcePath in sourcePaths) {
        NSError *readError = nil;
        NSString *text = [persistenceAdapter readDeclTextAtVirtualPath:sourcePath error:&readError];
        if (!text) {
            if (error) {
                *error = readError;
            }
            return nil;
        }

        NSError *parseError = nil;
        NSArray<UDDeclDefinition *> *parsed = [parser parseDefinitionsFromText:text
                                                              sourceVirtualPath:sourcePath
                                                                          error:&parseError];
        if (!parsed) {
            if (error) {
                *error = parseError;
            }
            return nil;
        }

        [definitions addObjectsFromArray:parsed];
    }

    [definitions sortUsingFunction:UDDeclManagerCompareDeclDefinitions context:NULL];

    if (error) {
        *error = nil;
    }
    return [[UDDeclModel alloc] initWithDefinitions:definitions];
}

- (UDDeclModel *)rebuildDeclModelByApplyingWriteNotification:(NSNotification *)notification
                                              toExistingModel:(UDDeclModel *)existingModel
                                            virtualFileSystem:(UDVirtualFileSystem *)virtualFileSystem
                                                        error:(NSError **)error {
    NSParameterAssert(virtualFileSystem != nil);

    UDVFSDeclPersistenceAdapter *adapter = [[UDVFSDeclPersistenceAdapter alloc] initWithVirtualFileSystem:virtualFileSystem];
    return UDDeclManagerRebuildDeclModelByApplyingWriteNotification(notification,
                                                                    existingModel,
                                                                    adapter,
                                                                    virtualFileSystem.gameType,
                                                                    error);
}

- (UDDeclModel *)rebuildDeclModelByApplyingWriteNotification:(NSNotification *)notification
                                              toExistingModel:(UDDeclModel *)existingModel
                                             persistenceAdapter:(id<UDDeclPersistenceAdapter>)persistenceAdapter
                                                        error:(NSError **)error {
    NSParameterAssert(notification != nil);
    NSParameterAssert(existingModel != nil);
    NSParameterAssert(persistenceAdapter != nil);
    return UDDeclManagerRebuildDeclModelByApplyingWriteNotification(notification,
                                                                    existingModel,
                                                                    persistenceAdapter,
                                                                    UDGameTypeUnknown,
                                                                    error);
}

@end
