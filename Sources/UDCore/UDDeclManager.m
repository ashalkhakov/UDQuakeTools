/*
 * SPDX-License-Identifier: GPL-2.0-or-later
 * Decl model manager implementation.
 */

#import "UDAssetIndex.h"

static NSSet<NSString *> *UDDeclManagerTextAssetExtensions(void) {
    static NSSet<NSString *> *extensions = nil;
    if (!extensions) {
        extensions = [NSSet setWithObjects:@"def", @"mtr", @"skin", @"sndshd", @"fx", @"prt", @"xdata", @"pda", @"af", nil];
    }
    return extensions;
}

static BOOL UDDeclManagerAssetEntryCanContainDecls(UDAssetIndexEntry *entry) {
    return [UDDeclManagerTextAssetExtensions() containsObject:entry.fileExtension.lowercaseString];
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

@implementation UDDeclManager

- (UDDeclModel *)buildDeclModelFromAssetIndex:(UDAssetIndex *)assetIndex
                           persistenceAdapter:(id<UDDeclPersistenceAdapter>)persistenceAdapter
                                         error:(NSError **)error {
    NSParameterAssert(assetIndex != nil);
    NSParameterAssert(persistenceAdapter != nil);

    UDDeclParser *parser = [[UDDeclParser alloc] init];
    NSMutableArray<UDDeclDefinition *> *definitions = [NSMutableArray array];

    for (UDAssetIndexEntry *entry in assetIndex.entries) {
        if (!UDDeclManagerAssetEntryCanContainDecls(entry)) {
            continue;
        }

        NSError *readError = nil;
        NSString *text = [persistenceAdapter readDeclTextAtVirtualPath:entry.virtualPath error:&readError];
        if (!text) {
            if (error) {
                *error = readError;
            }
            return nil;
        }

        NSError *parseError = nil;
        NSArray<UDDeclDefinition *> *parsed = [parser parseDefinitionsFromText:text
                                                              sourceVirtualPath:entry.virtualPath
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
                                                   assetIndex:(UDAssetIndex *)assetIndex
                                           persistenceAdapter:(id<UDDeclPersistenceAdapter>)persistenceAdapter
                                                        error:(NSError **)error {
    NSParameterAssert(notification != nil);
    NSParameterAssert(existingModel != nil);
    NSParameterAssert(assetIndex != nil);
    NSParameterAssert(persistenceAdapter != nil);

    NSString *virtualPath = [notification.userInfo objectForKey:UDVFSNotificationVirtualPathKey];
    if (virtualPath.length == 0 || ![UDDeclManagerTextAssetExtensions() containsObject:virtualPath.pathExtension.lowercaseString]) {
        return existingModel;
    }

    NSString *normalizedPath = [virtualPath stringByReplacingOccurrencesOfString:@"\\" withString:@"/"];
    while ([normalizedPath hasPrefix:@"/"]) {
        normalizedPath = [normalizedPath substringFromIndex:1];
    }

    NSMutableArray<UDDeclDefinition *> *definitions = [NSMutableArray arrayWithCapacity:existingModel.definitions.count + 8];
    for (UDDeclDefinition *definition in existingModel.definitions) {
        if (![definition.sourceVirtualPath isEqualToString:normalizedPath]) {
            [definitions addObject:definition];
        }
    }

    UDAssetIndexEntry *entry = [assetIndex entryForVirtualPath:normalizedPath];
    if (entry && UDDeclManagerAssetEntryCanContainDecls(entry)) {
        UDAssetIndex *singleFileIndex = [[UDAssetIndex alloc] initWithEntries:@[entry]];
        UDDeclModel *singleFileModel = [self buildDeclModelFromAssetIndex:singleFileIndex
                                                        persistenceAdapter:persistenceAdapter
                                                                      error:error];
        if (!singleFileModel) {
            return nil;
        }
        [definitions addObjectsFromArray:singleFileModel.definitions];
    }

    [definitions sortUsingFunction:UDDeclManagerCompareDeclDefinitions context:NULL];

    if (error) {
        *error = nil;
    }
    return [[UDDeclModel alloc] initWithDefinitions:definitions];
}

@end
