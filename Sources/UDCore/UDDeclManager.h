/*
 * SPDX-License-Identifier: GPL-2.0-or-later
 * UDDeclManager.h — Decl model orchestration from VFS and change notifications.
 */

#import <Foundation/Foundation.h>

#import "UDDeclModel.h"
#import "UDDeclPersistence.h"
#import "UDVirtualFileSystem.h"

NS_ASSUME_NONNULL_BEGIN

@interface UDDeclManager : NSObject

- (UDDeclModel *)buildDeclModelFromVirtualFileSystem:(UDVirtualFileSystem *)virtualFileSystem
                                                error:(NSError **)error;

- (UDDeclModel *)buildDeclModelFromVirtualFileSystem:(UDVirtualFileSystem *)virtualFileSystem
                                  persistenceAdapter:(id<UDDeclPersistenceAdapter>)persistenceAdapter
                                                error:(NSError **)error;

- (UDDeclModel *)rebuildDeclModelByApplyingWriteNotification:(NSNotification *)notification
                                              toExistingModel:(UDDeclModel *)existingModel
                                            virtualFileSystem:(UDVirtualFileSystem *)virtualFileSystem
                                                        error:(NSError **)error;

- (UDDeclModel *)rebuildDeclModelByApplyingWriteNotification:(NSNotification *)notification
                                              toExistingModel:(UDDeclModel *)existingModel
                                           persistenceAdapter:(id<UDDeclPersistenceAdapter>)persistenceAdapter
                                                        error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
