/*
 * SPDX-License-Identifier: GPL-2.0-or-later
 * UDGame.m — Domain model representing a game profile.
 */

#import "UDGame.h"

@implementation UDGame

@synthesize type = _type;
@synthesize displayName = _displayName;
@synthesize identifier = _identifier;

- (instancetype)initWithType:(UDGameType)type
                 displayName:(NSString *)displayName
                  identifier:(NSString *)identifier {
    self = [super init];
    if (self) {
        _type = type;
        _displayName = [displayName copy];
        _identifier = [identifier copy];
    }
    return self;
}

- (instancetype)init {
    [self doesNotRecognizeSelector:_cmd];
    return nil;
}

+ (NSArray<UDGame *> *)allGames {
    static NSArray<UDGame *> *games = nil;
    if (!games) {
        games = @[
            [[UDGame alloc] initWithType:UDGameTypeUnknown displayName:@"Auto Detect" identifier:@"unknown"],
            [[UDGame alloc] initWithType:UDGameTypeQuake1 displayName:@"Quake 1" identifier:@"quake1"],
            [[UDGame alloc] initWithType:UDGameTypeQuake2 displayName:@"Quake 2" identifier:@"quake2"],
            [[UDGame alloc] initWithType:UDGameTypeDaikatana displayName:@"Daikatana" identifier:@"daikatana"],
            [[UDGame alloc] initWithType:UDGameTypeQuake3 displayName:@"Quake 3" identifier:@"quake3"],
            [[UDGame alloc] initWithType:UDGameTypeDoom3 displayName:@"Doom 3" identifier:@"doom3"]
        ];
    }
    return games;
}

+ (UDGame *)gameWithType:(UDGameType)type {
    for (UDGame *g in [self allGames]) {
        if (g.type == type) {
            return g;
        }
    }
    return [[self allGames] objectAtIndex:0]; // default to Unknown/Auto Detect
}

+ (nullable UDGame *)gameWithDisplayName:(NSString *)displayName {
    for (UDGame *g in [self allGames]) {
        if ([g.displayName isEqualToString:displayName]) {
            return g;
        }
    }
    return nil;
}

@end
