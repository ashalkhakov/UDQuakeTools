/*
 * SPDX-License-Identifier: GPL-2.0-or-later
 * Decl Browser view-model.
 */

#import "UDDeclBrowserViewModel.h"

#import "UDDeclBrowserTreeModel.h"
#import "../UDCore/UDDeclManager.h"
#import "../UDCore/UDDeclModel.h"
#import "../UDCore/UDGame.h"
#import "../UDCore/UDVirtualFileSystem.h"
#import "../UDFormats/UDCodecRegistry.h"

@interface UDDeclBrowserViewModel ()

@property (nonatomic, strong) UDDeclModel *declModel;
@property (nonatomic, strong) UDDeclQueryService *queryService;
@property (nonatomic, strong) UDDeclBrowserTreeModel *treeModel;
@property (nonatomic, copy) NSArray<UDDeclDefinition *> *results;
@property (nonatomic, strong) UDGame *selectedGame;
@property (nonatomic, copy) NSString *searchString;
@property (nonatomic, copy) NSString *statusText;

@end

@implementation UDDeclBrowserViewModel

- (instancetype)init {
    self = [super init];
    if (self) {
        _declModel = [[UDDeclModel alloc] initWithDefinitions:@[]];
        _queryService = [[UDDeclQueryService alloc] init];
        _treeModel = [[UDDeclBrowserTreeModel alloc] init];
        _results = @[];
        _selectedGame = [UDGame gameWithType:UDGameTypeDoom3];
        _searchString = @"";
        _statusText = @"No decls loaded";

        [self _rebuildResults];
    }
    return self;
}

- (NSString *)selectedGameDisplayName {
    return self.selectedGame.displayName ?: @"Doom 3";
}

- (void)setSearchText:(nullable NSString *)searchText {
    self.searchString = searchText ?: @"";
    [self _rebuildResults];
}

- (void)setSelectedGameDisplayName:(nullable NSString *)displayName {
    UDGame *game = [UDGame gameWithDisplayName:displayName ?: @""];
    if (game) {
        self.selectedGame = game;
    }
}

- (BOOL)loadFromDirectoryURL:(nullable NSURL *)directoryURL
                 statusText:(NSString * __autoreleasing _Nullable * _Nullable)statusText {
    NSError *error = nil;
    UDVirtualFileSystem *vfs = [[UDVirtualFileSystem alloc] initWithCodecRegistry:[UDCodecRegistry sharedRegistry]];

    if (directoryURL) {
        [vfs configureWithGameType:self.selectedGame.type gameDirectoryURL:directoryURL];
        [vfs mountDirectoryURL:directoryURL identifier:@"gamedir" virtualRoot:nil priority:0 error:&error];
        if (!error) {
            [vfs mountDiscoveredArchivesInGameDirectory:&error];
        }
    }

    if (error) {
        NSString *message = [NSString stringWithFormat:@"Failed to load %@: %@", directoryURL.lastPathComponent, error.localizedDescription];
        [self _resetModelAndTreeForFailureWithStatus:message];
        if (statusText) {
            *statusText = message;
        }
        return NO;
    }

    UDDeclManager *declManager = [[UDDeclManager alloc] init];
    self.declModel = [declManager buildDeclModelFromVirtualFileSystem:vfs error:&error];
    if (error) {
        NSString *message = [NSString stringWithFormat:@"Failed to build decl model for %@: %@", directoryURL.lastPathComponent, error.localizedDescription];
        [self _resetModelAndTreeForFailureWithStatus:message];
        if (statusText) {
            *statusText = message;
        }
        return NO;
    }

    [self _rebuildResults];

    NSString *success = [NSString stringWithFormat:@"Loaded %lu decls from %@", (unsigned long)self.results.count, directoryURL.lastPathComponent ?: @"folder"];
    self.statusText = success;
    if (statusText) {
        *statusText = success;
    }
    return YES;
}

- (NSInteger)numberOfRowsInColumn:(NSInteger)column selectedRows:(NSArray<NSNumber *> *)selectedRows {
    return [self.treeModel numberOfRowsInColumn:column selectedRows:selectedRows];
}

- (nullable UDDeclBrowserTreeNode *)nodeForRow:(NSInteger)row
                                      inColumn:(NSInteger)column
                                   selectedRows:(NSArray<NSNumber *> *)selectedRows {
    return [self.treeModel nodeForRow:row inColumn:column selectedRows:selectedRows];
}

- (nullable NSArray<NSNumber *> *)firstLeafSelectionPath {
    return [self.treeModel firstLeafSelectionPath];
}

- (nullable NSArray<NSNumber *> *)selectionPathForNodeNameChain:(NSArray<NSString *> *)nameChain {
    return [self.treeModel selectionPathForNodeNameChain:nameChain];
}

- (nullable NSArray<NSNumber *> *)selectionPathForDefinitionWithType:(NSString *)declType
                                                                 name:(NSString *)declName
                                                           sourcePath:(NSString *)sourcePath {
    return [self.treeModel selectionPathForDefinitionWithType:declType name:declName sourcePath:sourcePath];
}

- (void)_rebuildResults {
    UDDeclQueryRequest *request = [[UDDeclQueryRequest alloc] init];
    request.searchText = self.searchString;
    request.sortField = UDDeclQuerySortFieldName;
    request.ascending = YES;

    self.results = [[self.queryService queryDefinitionsInModel:self.declModel request:request] copy];
    [self.treeModel rebuildWithDefinitions:self.results];

    self.statusText = [NSString stringWithFormat:@"%lu result%@", (unsigned long)self.results.count, self.results.count == 1 ? @"" : @"s"];
}

- (void)_resetModelAndTreeForFailureWithStatus:(NSString *)status {
    self.declModel = [[UDDeclModel alloc] initWithDefinitions:@[]];
    self.results = @[];
    [self.treeModel rebuildWithDefinitions:self.results];
    self.statusText = status;
}

@end
