/*
 * SPDX-License-Identifier: GPL-2.0-or-later
 * UDDeclPersistence.h — Decl persistence abstraction.
 */

#import <Foundation/Foundation.h>

#import "UDVirtualFileSystem.h"

NS_ASSUME_NONNULL_BEGIN

@protocol UDDeclPersistenceAdapter <NSObject>

- (nullable NSString *)readDeclTextAtVirtualPath:(NSString *)virtualPath
                                           error:(NSError **)error;
- (BOOL)writeDeclText:(NSString *)text
         toVirtualPath:(NSString *)virtualPath
                 error:(NSError **)error;

@end

@interface UDVFSDeclPersistenceAdapter : NSObject <UDDeclPersistenceAdapter> {
    UDVirtualFileSystem *_virtualFileSystem;
}

@property (nonatomic, readonly, strong) UDVirtualFileSystem *virtualFileSystem;

- (instancetype)initWithVirtualFileSystem:(UDVirtualFileSystem *)virtualFileSystem NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
