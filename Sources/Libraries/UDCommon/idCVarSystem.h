/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 * idCVarSystem.h — console variables (framework/CVarSystem.cpp), ported as
 * far as the GUI code uses them: every cvar dhewm3 and its base game
 * register (idCVarDefaults.inc, generated from their idCVar declarations),
 * found by name, set as idInternalCVar sets them (its type and range kept).
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface idCVar : NSObject
- (NSString *)getName;
- (NSString *)getString;
- (BOOL)getBool;
- (int)getInteger;
- (float)getFloat;
/// idCVar::SetString… (InternalSetString…: forced, the value updated as
/// its type has it)
- (void)setString:(NSString *)value;
- (void)setBool:(BOOL)value;
- (void)setInteger:(int)value;
- (void)setFloat:(float)value;
- (void)reset;
@end

@interface idCVarSystem : NSObject

/// The cvars dhewm3 registers, at their defaults.
- (instancetype)init;

/// cvarSystem->Find: nil for a cvar no one registered.
- (nullable idCVar *)find:(NSString *)name;

/// GetCVarString…: "" (0) for one not registered.
- (NSString *)getString:(NSString *)name;
- (BOOL)getBool:(NSString *)name;
- (int)getInt:(NSString *)name;
- (float)getFloat:(NSString *)name;
/// SetCVarString…: one not registered is registered, a string.
- (void)set:(NSString *)name value:(NSString *)value;
- (void)setBool:(NSString *)name value:(BOOL)value;

@end

NS_ASSUME_NONNULL_END
