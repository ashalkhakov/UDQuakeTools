/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 * idStrPool.h — a pool of shared, counted strings (idlib/containers/
 * StrPool.h), ported: idDict keeps its keys and values in two of them.
 */

#import <Foundation/Foundation.h>

@class idStrPool;

NS_ASSUME_NONNULL_BEGIN

/// idPoolStr: a string of a pool, and how many use it.
@interface idPoolStr : NSObject
@property (nonatomic, copy, readonly) NSString *string;
@property (nonatomic, weak, readonly, nullable) idStrPool *pool;
@property (nonatomic, readonly) int numUsers;
@end

@interface idStrPool : NSObject
/// SetCaseSensitive: whether strings differing in the case of A–Z are two.
@property (nonatomic) BOOL caseSensitive;
- (int)num;
/// AllocString: the pool's string equal to @a string (one more user), or a
/// new one.
- (idPoolStr *)allocString:(NSString *)string;
/// FreeString: one user fewer; the string leaves the pool with its last.
- (void)freeString:(idPoolStr *)poolStr;
/// CopyString: one more user of @a poolStr, or this pool's string of it.
- (idPoolStr *)copyString:(idPoolStr *)poolStr;
- (void)clear;
@end

NS_ASSUME_NONNULL_END
