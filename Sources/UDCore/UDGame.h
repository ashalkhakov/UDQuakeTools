/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 * UDGame.h — Domain model representing a game profile.
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, UDGameType) {
    UDGameTypeUnknown = 0,
    UDGameTypeQuake1,
    UDGameTypeQuake2,
    UDGameTypeDaikatana,
    UDGameTypeQuake3,
    UDGameTypeDoom3
};

@interface UDGame : NSObject {
    UDGameType _type;
    NSString *_displayName;
    NSString *_identifier;
}

@property (nonatomic, readonly) UDGameType type;
@property (nonatomic, readonly, copy) NSString *displayName;
@property (nonatomic, readonly, copy) NSString *identifier;

- (instancetype)initWithType:(UDGameType)type
                 displayName:(NSString *)displayName
                  identifier:(NSString *)identifier NS_DESIGNATED_INITIALIZER;

// Spelled out: GNUstep's NS_UNAVAILABLE is empty.
- (instancetype)init __attribute__((unavailable));
+ (instancetype)new __attribute__((unavailable));

+ (NSArray<UDGame *> *)allGames;
+ (UDGame *)gameWithType:(UDGameType)type;
+ (nullable UDGame *)gameWithDisplayName:(NSString *)displayName;

@end

NS_ASSUME_NONNULL_END
