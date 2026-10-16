/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 * idWinVar.h — a window's variables (ui/Winvar.h, Winvar.cpp), ported:
 * idWinVar and its kinds. C++'s operators are methods: a kind's -data is its
 * value (operator bool, operator const char *…), -setData: is operator= of a
 * value (which writes the GUI's state dict, when the var is bound to it),
 * -assign: is operator= of another var of its kind (which doesn't), and
 * -string is c_str().
 */

#import <Foundation/Foundation.h>
#import "idMath.h"

@class idDict, idWindow;

NS_ASSUME_NONNULL_BEGIN

extern NSString *const VAR_GUIPREFIX;

@interface idWinVar : NSObject {
@public
    idDict *_Nullable guiDict;
    NSString *_Nullable name;
    BOOL eval;
}

- (void)setGuiInfo:(nullable idDict *)gd name:(nullable NSString *)_name;
- (NSString *)getName;
- (void)setName:(nullable NSString *)_name;
/// idWinVar::operator=( const idWinVar &other ): its dict and name.
- (void)assign:(idWinVar *)other;
- (nullable idDict *)getDict;
- (BOOL)needsUpdate;
/// idWinVar::Init( name, win ): bound to the GUI's state ("gui::"), or
/// Set to @a _name.
- (void)winVarInit:(NSString *)_name window:(idWindow *)win;
- (void)set:(NSString *)val;
- (void)update;
- (NSString *)string;
- (float)x;
- (void)setEval:(BOOL)b;
- (BOOL)getEval;

@end

@interface idWinBool : idWinVar
@property (nonatomic, readonly) BOOL data;
- (void)setData:(BOOL)other;
@end

@interface idWinStr : idWinVar {
@protected
    NSString *data;
}
/// operator const char *
- (NSString *)data;
/// operator=( const idStr & )
- (void)setData:(NSString *)other;
- (NSUInteger)lengthWithoutColors;
- (NSUInteger)length;
- (void)removeColors;
@end

@interface idWinInt : idWinVar
@property (nonatomic, readonly) int data;
- (void)setData:(int)other;
@end

@interface idWinFloat : idWinVar
@property (nonatomic, readonly) float data;
- (void)setData:(float)other;
@end

@interface idWinRectangle : idWinVar
@property (nonatomic, readonly) idRectangle data;
/// operator=( const idRectangle & )
- (void)setData:(idRectangle)other;
/// operator=( const idVec4 & )
- (void)setVec4:(idVec4)other;
- (float)y;
- (float)w;
- (float)h;
- (float)right;
- (float)bottom;
- (idVec4)toVec4;
@end

@interface idWinVec2 : idWinVar
@property (nonatomic, readonly) idVec2 data;
- (void)setData:(idVec2)other;
- (float)y;
- (void)zero;
@end

@interface idWinVec4 : idWinVar
@property (nonatomic, readonly) idVec4 data;
- (void)setData:(idVec4)other;
- (float)y;
- (float)z;
- (float)w;
- (void)zero;
- (idVec3)toVec3;
@end

@interface idWinVec3 : idWinVar
@property (nonatomic, readonly) idVec3 data;
- (void)setData:(idVec3)other;
- (float)y;
- (float)z;
- (void)zero;
@end

/// What an idWinBackground's material pointer points into: a window's
/// background, which it sets to the material of a name (nil for "").
@protocol idWinBackgroundTarget <NSObject>
- (void)setBackgroundMaterialNamed:(nullable NSString *)materialName;
@end

@interface idWinBackground : idWinStr
/// SetMaterialPtr: the window whose background this sets.
- (void)setMaterialPtr:(nullable id<idWinBackgroundTarget>)m;
@end

/// idMultiWinVar: an idList of vars set, updated, bound together.
@interface idMultiWinVar : NSObject
@property (nonatomic, strong, readonly) NSMutableArray<idWinVar *> *list;
- (void)set:(NSString *)val;
- (void)update;
- (void)setGuiInfo:(idDict *)dict;
@end

NS_ASSUME_NONNULL_END
