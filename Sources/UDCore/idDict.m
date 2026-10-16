/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 * idDict.m — idlib/Dict.cpp, ported as far as idDict.h says.
 */

#import "idDict.h"
#import "idStr.h"
#import "idStrPool.h"
#include <stdio.h>
#include <stdlib.h>

/// idKeyValue: its key and value, the pools'.
@interface idKeyValue : NSObject {
@public
    idPoolStr *key;
    idPoolStr *value;
}
@end

@implementation idKeyValue
@end

/*
================
idDict::Init: globalKeys ignores case, globalValues doesn't
================
*/
static idStrPool *GlobalKeys( void ) {
    static idStrPool *globalKeys;
    if ( globalKeys == nil ) {
        globalKeys = [[idStrPool alloc] init];
        globalKeys.caseSensitive = NO;
    }
    return globalKeys;
}

static idStrPool *GlobalValues( void ) {
    static idStrPool *globalValues;
    if ( globalValues == nil ) {
        globalValues = [[idStrPool alloc] init];
        globalValues.caseSensitive = YES;
    }
    return globalValues;
}

@implementation idDict {
    NSMutableArray<idKeyValue *> *args;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        args = [NSMutableArray array];
    }
    return self;
}

- (void)dealloc {
    [self clear];
}

- (id)copyWithZone:(NSZone *)zone {
    idDict *copy = [[idDict alloc] init];
    for ( idKeyValue *kv in args ) {
        idKeyValue *c = [[idKeyValue alloc] init];
        c->key = [GlobalKeys() copyString:kv->key];
        c->value = [GlobalValues() copyString:kv->value];
        [copy->args addObject:c];
    }
    return copy;
}

/*
================
idDict::Clear
================
*/
- (void)clear {
    for ( idKeyValue *kv in args ) {
        [GlobalKeys() freeString:kv->key];
        [GlobalValues() freeString:kv->value];
    }
    [args removeAllObjects];
}

/*
================
idDict::FindKeyIndex
================
*/
- (NSInteger)findKeyIndex:(NSString *)key {
    if ( key.length == 0 ) {
        return -1;
    }
    NSInteger i = 0;
    for ( idKeyValue *kv in args ) {
        if ( [kv->key.string ud_iequals:key] ) {
            return i;
        }
        i++;
    }
    return -1;
}

/*
================
idDict::Set
================
*/
- (void)set:(NSString *)key value:(NSString *)value {
    if ( key.length == 0 ) {
        return;
    }

    NSInteger i = [self findKeyIndex:key];
    if ( i != -1 ) {
        // first set the new value and then free the old value to allow proper self copying
        idPoolStr *oldValue = args[i]->value;
        args[i]->value = [GlobalValues() allocString:value];
        [GlobalValues() freeString:oldValue];
    } else {
        idKeyValue *kv = [[idKeyValue alloc] init];
        kv->key = [GlobalKeys() allocString:key];
        kv->value = [GlobalValues() allocString:value];
        [args addObject:kv];
    }
}

- (void)setFloat:(NSString *)key value:(float)val { [self set:key value:[NSString stringWithFormat:@"%f", val]]; }
- (void)setInt:(NSString *)key value:(int)val { [self set:key value:[NSString stringWithFormat:@"%i", val]]; }
- (void)setBool:(NSString *)key value:(BOOL)val { [self set:key value:[NSString stringWithFormat:@"%i", val ? 1 : 0]]; }
- (void)setVector:(NSString *)key value:(idVec3)val { [self set:key value:idVec3_ToString( val )]; }
- (void)setVec2:(NSString *)key value:(idVec2)val { [self set:key value:idVec2_ToString( val )]; }
- (void)setVec4:(NSString *)key value:(idVec4)val { [self set:key value:idVec4_ToString( val )]; }

/*
================
idDict::FindKey, GetString
================
*/
- (NSString *)getString:(NSString *)key defaultString:(NSString *)defaultString {
    NSInteger i = [self findKeyIndex:key];
    if ( i != -1 ) {
        return args[i]->value.string;
    }
    return defaultString;
}

- (NSString *)getString:(NSString *)key { return [self getString:key defaultString:@""]; }
- (float)getFloat:(NSString *)key { return atof( [self getString:key defaultString:@"0"].UTF8String ); }
- (int)getInt:(NSString *)key { return atoi( [self getString:key defaultString:@"0"].UTF8String ); }
- (BOOL)getBool:(NSString *)key { return [self getBool:key defaultString:@"0"]; }
- (BOOL)getBool:(NSString *)key defaultString:(NSString *)defaultString {
    return ( atoi( [self getString:key defaultString:defaultString].UTF8String ) != 0 );
}

/*
================
idDict::GetBool
================
*/
- (BOOL)getBool:(NSString *)key defaultString:(NSString *)defaultString out:(BOOL *)out {
    BOOL found = [self findKeyIndex:key] != -1;
    *out = ( atoi( [self getString:key defaultString:defaultString].UTF8String ) != 0 );
    return found;
}

/*
================
idDict::GetVector, GetVec2, GetVec4
================
*/
- (idVec3)getVector:(NSString *)key {
    idVec3 out = { 0, 0, 0 };
    sscanf( [self getString:key defaultString:@"0 0 0"].UTF8String, "%f %f %f", &out.x, &out.y, &out.z );
    return out;
}

- (idVec2)getVec2:(NSString *)key {
    idVec2 out = { 0, 0 };
    sscanf( [self getString:key defaultString:@"0 0"].UTF8String, "%f %f", &out.x, &out.y );
    return out;
}

- (idVec4)getVec4:(NSString *)key {
    idVec4 out = { 0, 0, 0, 0 };
    sscanf( [self getString:key defaultString:@"0 0 0 0"].UTF8String, "%f %f %f %f", &out.x, &out.y, &out.z, &out.w );
    return out;
}

/*
================
idDict::Delete
================
*/
- (void)deleteKey:(NSString *)key {
    NSInteger i = [self findKeyIndex:key];
    if ( i == -1 ) {
        return;
    }
    [GlobalKeys() freeString:args[i]->key];
    [GlobalValues() freeString:args[i]->value];
    [args removeObjectAtIndex:i];
}

- (int)numKeyVals { return (int)args.count; }
- (NSString *)keyAtIndex:(int)index { return args[index]->key.string; }
- (NSString *)valueAtIndex:(int)index { return args[index]->value.string; }

@end
