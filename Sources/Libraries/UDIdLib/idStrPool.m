/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 * idStrPool.m — idlib/containers/StrPool.h, ported. Its hash is a
 * dictionary: by the string, or by the string with A–Z lowered (Icmp's
 * equality) when the pool ignores case.
 */

#import "idStrPool.h"

@interface idPoolStr ()
@property (nonatomic, copy, readwrite) NSString *string;
@property (nonatomic, weak, readwrite, nullable) idStrPool *pool;
@property (nonatomic, readwrite) int numUsers;
@end

@implementation idPoolStr
@end

@implementation idStrPool {
    NSMutableDictionary<NSString *, idPoolStr *> *pool;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _caseSensitive = YES;
        pool = [NSMutableDictionary dictionary];
    }
    return self;
}

- (int)num {
    return (int)pool.count;
}

/// The hash's key: the string, or with A–Z lowered.
- (NSString *)hashKey:(NSString *)string {
    if ( self.caseSensitive ) {
        return string;
    }
    NSUInteger length = string.length;
    unichar *chars = malloc( sizeof( unichar ) * ( length + 1 ) );
    [string getCharacters:chars range:NSMakeRange( 0, length )];
    for ( NSUInteger i = 0; i < length; i++ ) {
        if ( chars[i] <= 'Z' && chars[i] >= 'A' ) {
            chars[i] += 'a' - 'A';
        }
    }
    NSString *key = [NSString stringWithCharacters:chars length:length];
    free( chars );
    return key;
}

/*
================
idStrPool::AllocString
================
*/
- (idPoolStr *)allocString:(NSString *)string {
    NSString *key = [self hashKey:string];
    idPoolStr *poolStr = pool[key];
    if ( poolStr != nil ) {
        poolStr.numUsers++;
        return poolStr;
    }

    poolStr = [[idPoolStr alloc] init];
    poolStr.string = string;
    poolStr.pool = self;
    poolStr.numUsers = 1;
    pool[key] = poolStr;
    return poolStr;
}

/*
================
idStrPool::FreeString
================
*/
- (void)freeString:(idPoolStr *)poolStr {
    assert( poolStr.numUsers >= 1 );
    assert( poolStr.pool == self );

    poolStr.numUsers--;
    if ( poolStr.numUsers <= 0 ) {
        [pool removeObjectForKey:[self hashKey:poolStr.string]];
    }
}

/*
================
idStrPool::CopyString
================
*/
- (idPoolStr *)copyString:(idPoolStr *)poolStr {
    assert( poolStr.numUsers >= 1 );

    if ( poolStr.pool == self ) {
        // the string is from this pool so just increase the user count
        poolStr.numUsers++;
        return poolStr;
    } else {
        // the string is from another pool so it needs to be re-allocated from this pool.
        return [self allocString:poolStr.string];
    }
}

/*
================
idStrPool::Clear
================
*/
- (void)clear {
    for ( idPoolStr *poolStr in pool.allValues ) {
        poolStr.numUsers = 0;
    }
    [pool removeAllObjects];
}

@end
