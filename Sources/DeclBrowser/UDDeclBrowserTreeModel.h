/*
 * SPDX-License-Identifier: GPL-2.0-or-later
 * Decl Browser tree model.
 */

#import <Foundation/Foundation.h>

@class UDDeclDefinition;

NS_ASSUME_NONNULL_BEGIN

@interface UDDeclBrowserTreeNode : NSObject

@property (nonatomic, readonly, copy) NSString *name;
@property (nonatomic, readonly, copy) NSString *fullPath;
@property (nonatomic, readonly, getter=isLeaf) BOOL leaf;
@property (nullable, nonatomic, readonly, strong) UDDeclDefinition *definition;
@property (nonatomic, readonly, copy) NSArray<UDDeclBrowserTreeNode *> *children;

- (instancetype)initWithName:(NSString *)name
                    fullPath:(NSString *)fullPath
                        leaf:(BOOL)leaf
                  definition:(nullable UDDeclDefinition *)definition NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

- (void)addChild:(UDDeclBrowserTreeNode *)child;
- (NSUInteger)childCount;
- (nullable UDDeclBrowserTreeNode *)childAtIndex:(NSUInteger)index;

@end

@interface UDDeclBrowserTreeModel : NSObject

- (void)rebuildWithDefinitions:(NSArray<UDDeclDefinition *> *)definitions;
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
