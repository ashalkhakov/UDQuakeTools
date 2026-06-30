/*
 * SPDX-License-Identifier: GPL-2.0-or-later
 * UDArchiveMutation — an immutable record of a net archive delta.
 *
 * Supported kinds used by UDArchiveEditor.currentDiff / pendingMutations:
 *   @"add"     — payload: @{ @"path": NSString, @"source": id<UDContentSource> }
 *   @"remove"  — payload: @{ @"path": NSString }
 *   @"replace" — payload: @{ @"path": NSString, @"source": id<UDContentSource> }
 *   @"move"    — payload: @{ @"fromPath": NSString, @"toPath": NSString }
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface UDArchiveMutation : NSObject {
    NSString     *_kind;
    NSDictionary *_payload;
    NSDate       *_createdAt;
}

@property (nonatomic, readonly, copy) NSString     *kind;
@property (nonatomic, readonly, copy) NSDictionary *payload;
@property (nonatomic, readonly, copy) NSDate       *createdAt;

- (instancetype)initWithKind:(NSString *)kind
                     payload:(NSDictionary *)payload NS_DESIGNATED_INITIALIZER;

@end

NS_ASSUME_NONNULL_END
