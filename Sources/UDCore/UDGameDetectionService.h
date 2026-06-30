/*
 * SPDX-License-Identifier: GPL-2.0-or-later
 * UDGameDetectionService.h — Service for auto-detecting the active game profile.
 */

#import <Foundation/Foundation.h>
#import "UDGame.h"

@class UDArchiveEntry;

NS_ASSUME_NONNULL_BEGIN

@interface UDGameDetectionService : NSObject

- (UDGame *)detectGameForURL:(nullable NSURL *)url
                     entries:(NSArray<UDArchiveEntry *> *)entries
             codecIdentifier:(nullable NSString *)formatIdentifier;

@end

NS_ASSUME_NONNULL_END
