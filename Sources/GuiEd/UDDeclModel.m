/*
 * SPDX-License-Identifier: GPL-2.0-or-later
 * UDDeclModel.m — Decl definition model and query implementation.
 */

#import "UDDeclModel.h"

static NSString *UDDeclLookupTypeKey(NSString *declType) {
    return declType.lowercaseString;
}

static NSString *UDDeclLookupTypeAndNameKey(NSString *declType, NSString *declName) {
    return [NSString stringWithFormat:@"%@|%@", declType.lowercaseString, declName.lowercaseString];
}

static NSComparisonResult UDCompareDeclDefinitions(id leftObject, id rightObject, void *context) {
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

static NSComparisonResult UDCompareDeclDefinitionsForSortField(UDDeclDefinition *left,
                                                               UDDeclDefinition *right,
                                                               UDDeclQuerySortField sortField,
                                                               BOOL ascending) {
    NSComparisonResult primary = NSOrderedSame;
    switch (sortField) {
        case UDDeclQuerySortFieldType:
            primary = [left.declType compare:right.declType options:NSCaseInsensitiveSearch];
            break;
        case UDDeclQuerySortFieldSourcePath:
            primary = [left.sourceVirtualPath compare:right.sourceVirtualPath options:NSCaseInsensitiveSearch];
            break;
        case UDDeclQuerySortFieldName:
        default:
            primary = [left.declName compare:right.declName options:NSCaseInsensitiveSearch];
            break;
    }

    if (primary == NSOrderedSame) {
        primary = UDCompareDeclDefinitions(left, right, NULL);
    }

    if (!ascending) {
        if (primary == NSOrderedAscending) {
            return NSOrderedDescending;
        }
        if (primary == NSOrderedDescending) {
            return NSOrderedAscending;
        }
    }
    return primary;
}

@implementation UDDeclDefinition

@synthesize declType = _declType;
@synthesize declName = _declName;
@synthesize body = _body;
@synthesize sourceVirtualPath = _sourceVirtualPath;

- (nullable UDDeclTypeDescriptor *)typeDescriptor {
    return [UDDeclTypeRegistry descriptorForIdentifier:_declType];
}

- (instancetype)initWithDeclType:(NSString *)declType
                        declName:(NSString *)declName
                            body:(NSString *)body
               sourceVirtualPath:(NSString *)sourceVirtualPath {
    NSParameterAssert(declType.length > 0);
    NSParameterAssert(declName.length > 0);
    NSParameterAssert(body != nil);
    NSParameterAssert(sourceVirtualPath.length > 0);

    self = [super init];
    if (!self) {
        return nil;
    }

    _declType = [declType copy];
    _declName = [declName copy];
    _body = [body copy];
    _sourceVirtualPath = [sourceVirtualPath copy];
    return self;
}

@end

@implementation UDDeclModel

@synthesize definitions = _definitions;

- (instancetype)initWithDefinitions:(NSArray<UDDeclDefinition *> *)definitions {
    NSParameterAssert(definitions != nil);

    self = [super init];
    if (!self) {
        return nil;
    }

    _definitions = [definitions copy];

    NSMutableDictionary<NSString *, NSMutableArray<UDDeclDefinition *> *> *definitionsByType = [NSMutableDictionary dictionary];
    NSMutableDictionary<NSString *, UDDeclDefinition *> *definitionsByTypeAndName = [NSMutableDictionary dictionaryWithCapacity:_definitions.count];
    NSMutableDictionary<NSString *, NSMutableArray<UDDeclDefinition *> *> *definitionsBySourcePath = [NSMutableDictionary dictionary];

    for (UDDeclDefinition *definition in _definitions) {
        NSString *typeKey = UDDeclLookupTypeKey(definition.declType);
        NSMutableArray<UDDeclDefinition *> *typeBucket = [definitionsByType objectForKey:typeKey];
        if (!typeBucket) {
            typeBucket = [NSMutableArray array];
            [definitionsByType setObject:typeBucket forKey:typeKey];
        }
        [typeBucket addObject:definition];

        [definitionsByTypeAndName setObject:definition
                                     forKey:UDDeclLookupTypeAndNameKey(definition.declType, definition.declName)];

        NSMutableArray<UDDeclDefinition *> *sourceBucket = [definitionsBySourcePath objectForKey:definition.sourceVirtualPath];
        if (!sourceBucket) {
            sourceBucket = [NSMutableArray array];
            [definitionsBySourcePath setObject:sourceBucket forKey:definition.sourceVirtualPath];
        }
        [sourceBucket addObject:definition];
    }

    NSMutableDictionary<NSString *, NSArray<UDDeclDefinition *> *> *frozenByType = [NSMutableDictionary dictionaryWithCapacity:definitionsByType.count];
    for (NSString *typeKey in definitionsByType) {
        [frozenByType setObject:[[definitionsByType objectForKey:typeKey] copy] forKey:typeKey];
    }

    NSMutableDictionary<NSString *, NSArray<UDDeclDefinition *> *> *frozenBySource = [NSMutableDictionary dictionaryWithCapacity:definitionsBySourcePath.count];
    for (NSString *sourcePath in definitionsBySourcePath) {
        [frozenBySource setObject:[[definitionsBySourcePath objectForKey:sourcePath] copy] forKey:sourcePath];
    }

    _definitionsByType = [frozenByType copy];
    _definitionsByTypeAndName = [definitionsByTypeAndName copy];
    _definitionsBySourceVirtualPath = [frozenBySource copy];
    return self;
}

- (NSArray<UDDeclDefinition *> *)definitionsOfType:(NSString *)declType {
    if (declType.length == 0) {
        return @[];
    }
    NSArray<UDDeclDefinition *> *results = [_definitionsByType objectForKey:UDDeclLookupTypeKey(declType)];
    return results ?: @[];
}

- (nullable UDDeclDefinition *)definitionWithType:(NSString *)declType name:(NSString *)declName {
    if (declType.length == 0 || declName.length == 0) {
        return nil;
    }
    return [_definitionsByTypeAndName objectForKey:UDDeclLookupTypeAndNameKey(declType, declName)];
}

- (NSArray<UDDeclDefinition *> *)definitionsWithNameContaining:(NSString *)nameFragment {
    if (nameFragment.length == 0) {
        return [self.definitions copy];
    }

    NSMutableArray<UDDeclDefinition *> *results = [NSMutableArray array];
    for (UDDeclDefinition *definition in self.definitions) {
        if ([definition.declName rangeOfString:nameFragment options:NSCaseInsensitiveSearch].location != NSNotFound) {
            [results addObject:definition];
        }
    }
    return results;
}

- (NSArray<UDDeclDefinition *> *)definitionsFromSourceVirtualPath:(NSString *)sourceVirtualPath {
    if (sourceVirtualPath.length == 0) {
        return @[];
    }
    NSArray<UDDeclDefinition *> *results = [_definitionsBySourceVirtualPath objectForKey:sourceVirtualPath];
    return results ?: @[];
}

@end

@implementation UDDeclQueryRequest

@synthesize searchText = _searchText;
@synthesize declType = _declType;
@synthesize sourceVirtualPath = _sourceVirtualPath;
@synthesize sortField = _sortField;
@synthesize ascending = _ascending;
@synthesize maxResults = _maxResults;

- (instancetype)init {
    self = [super init];
    if (!self) {
        return nil;
    }

    _searchText = nil;
    _declType = nil;
    _sourceVirtualPath = nil;
    _sortField = UDDeclQuerySortFieldName;
    _ascending = YES;
    _maxResults = 0;
    return self;
}

@end

@implementation UDDeclQueryService

- (NSArray<UDDeclDefinition *> *)queryDefinitionsInModel:(UDDeclModel *)model
                                                  request:(UDDeclQueryRequest *)request {
    NSParameterAssert(model != nil);

    UDDeclQueryRequest *effectiveRequest = request ?: [[UDDeclQueryRequest alloc] init];
    NSMutableArray<UDDeclDefinition *> *filtered = [NSMutableArray array];

    for (UDDeclDefinition *definition in model.definitions) {
        if (effectiveRequest.declType.length > 0 &&
            [definition.declType caseInsensitiveCompare:effectiveRequest.declType] != NSOrderedSame) {
            continue;
        }

        if (effectiveRequest.sourceVirtualPath.length > 0 &&
            [definition.sourceVirtualPath caseInsensitiveCompare:effectiveRequest.sourceVirtualPath] != NSOrderedSame) {
            continue;
        }

        if (effectiveRequest.searchText.length > 0) {
            NSStringCompareOptions options = NSCaseInsensitiveSearch;
            BOOL matched = ([definition.declName rangeOfString:effectiveRequest.searchText options:options].location != NSNotFound ||
                            [definition.declType rangeOfString:effectiveRequest.searchText options:options].location != NSNotFound ||
                            [definition.sourceVirtualPath rangeOfString:effectiveRequest.searchText options:options].location != NSNotFound);
            if (!matched) {
                continue;
            }
        }

        [filtered addObject:definition];
    }

    [filtered sortUsingComparator:^NSComparisonResult(UDDeclDefinition *left, UDDeclDefinition *right) {
        return UDCompareDeclDefinitionsForSortField(left,
                                                    right,
                                                    effectiveRequest.sortField,
                                                    effectiveRequest.isAscending);
    }];

    if (effectiveRequest.maxResults > 0 && filtered.count > effectiveRequest.maxResults) {
        return [filtered subarrayWithRange:NSMakeRange(0, effectiveRequest.maxResults)];
    }

    return [filtered copy];
}

@end
