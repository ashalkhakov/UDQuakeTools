/*
 * SPDX-License-Identifier: GPL-2.0-or-later
 */

#import "UDArchiveMutation.h"

@implementation UDArchiveMutation

@synthesize kind      = _kind;
@synthesize payload   = _payload;
@synthesize createdAt = _createdAt;

- (instancetype)initWithKind:(NSString *)kind payload:(NSDictionary *)payload {
    NSParameterAssert(kind.length > 0);
    NSParameterAssert(payload != nil);

    self = [super init];
    if (!self) {
        return nil;
    }

    _kind      = [kind copy];
    _payload   = [payload copy];
    _createdAt = [NSDate date];
    return self;
}

@end
