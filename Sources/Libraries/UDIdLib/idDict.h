/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 * idDict.h — idDict (idlib/Dict.h, Dict.cpp), as the GUI code uses it:
 * key/value strings in the order they were set, keys compared ignoring the
 * case of A–Z, the strings in two global pools (globalKeys, ignoring case,
 * and globalValues), and its typed getters and setters.
 */

#import <Foundation/Foundation.h>
#import "idMath.h"

NS_ASSUME_NONNULL_BEGIN

@interface idDict : NSObject <NSCopying>

- (void)clear;
- (void)set:(NSString *)key value:(NSString *)value;
- (void)setFloat:(NSString *)key value:(float)val;
- (void)setInt:(NSString *)key value:(int)val;
- (void)setBool:(NSString *)key value:(BOOL)val;
- (void)setVector:(NSString *)key value:(idVec3)val;
- (void)setVec2:(NSString *)key value:(idVec2)val;
- (void)setVec4:(NSString *)key value:(idVec4)val;

/// GetString( key, defaultString ): the value, or @a defaultString.
- (nullable NSString *)getString:(NSString *)key defaultString:(nullable NSString *)defaultString;
- (NSString *)getString:(NSString *)key;              // default ""
- (float)getFloat:(NSString *)key;                    // default "0"
- (int)getInt:(NSString *)key;                        // default "0"
- (BOOL)getBool:(NSString *)key;                      // default "0"
- (BOOL)getBool:(NSString *)key defaultString:(NSString *)defaultString;
/// GetBool( key, defaultString, out ): whether the key is there.
- (BOOL)getBool:(NSString *)key defaultString:(NSString *)defaultString out:(BOOL *)out;
- (idVec3)getVector:(NSString *)key;                  // default "0 0 0"
- (idVec2)getVec2:(NSString *)key;                    // default "0 0"
- (idVec4)getVec4:(NSString *)key;                    // default "0 0 0 0"

- (void)deleteKey:(NSString *)key;
- (int)numKeyVals;
- (NSString *)keyAtIndex:(int)index;
- (NSString *)valueAtIndex:(int)index;

@end

NS_ASSUME_NONNULL_END
