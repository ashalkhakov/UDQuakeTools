/*
 * SPDX-License-Identifier: GPL-2.0-or-later
 * Decl Browser view-model.
 */

#import <Foundation/Foundation.h>

@class UDDeclBrowserTreeModel;
@class UDDeclBrowserTreeNode;

NS_ASSUME_NONNULL_BEGIN

@interface UDDeclBrowserViewModel : NSObject

@property (nonatomic, readonly, copy) NSString *selectedGameDisplayName;
@property (nonatomic, readonly, copy) NSString *statusText;

- (instancetype)init NS_DESIGNATED_INITIALIZER;

- (void)setSearchText:(nullable NSString *)searchText;
- (void)setSelectedGameDisplayName:(nullable NSString *)displayName;

- (BOOL)loadFromDirectoryURL:(nullable NSURL *)directoryURL
                 statusText:(NSString * __autoreleasing _Nullable * _Nullable)statusText;

- (NSInteger)numberOfRowsInColumn:(NSInteger)column selectedRows:(NSArray<NSNumber *> *)selectedRows;
- (nullable UDDeclBrowserTreeNode *)nodeForRow:(NSInteger)row
                                      inColumn:(NSInteger)column
                                   selectedRows:(NSArray<NSNumber *> *)selectedRows;
- (nullable NSArray<NSNumber *> *)firstLeafSelectionPath;
- (nullable NSArray<NSNumber *> *)selectionPathForNodeNameChain:(NSArray<NSString *> *)nameChain;
- (nullable NSArray<NSNumber *> *)selectionPathForDefinitionWithType:(NSString *)declType
                                   name:(NSString *)declName
                                sourcePath:(NSString *)sourcePath;

@end

NS_ASSUME_NONNULL_END
