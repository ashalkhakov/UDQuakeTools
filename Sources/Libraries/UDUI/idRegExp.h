/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 * idRegExp.h — a window's registers (ui/RegExp.h, RegExp.cpp), ported: a
 * var's components' places among the window's expression registers.
 */

#import <Foundation/Foundation.h>
#import "idMath.h"

@class idParser, idWindow, idWinVar;

NS_ASSUME_NONNULL_BEGIN

/// idRegister::REGTYPE
typedef enum { REG_VEC4 = 0, REG_FLOAT, REG_BOOL, REG_INT, REG_STRING, REG_VEC2, REG_VEC3, REG_RECTANGLE, REG_NUMTYPES } idRegisterType;

extern const int idRegister_REGCOUNT[REG_NUMTYPES];

@interface idRegister : NSObject {
@public
    BOOL                enabled;
    short               type;
    NSString           *name;
    int                 regCount;
    unsigned short      regs[4];
    idWinVar *_Nullable var;
}
- (instancetype)initWithName:(NSString *)p type:(int)t;
- (void)setToRegs:(float *)registers;
- (void)getFromRegs:(float *)registers;
- (void)copyRegs:(idRegister *)src;
- (void)enable:(BOOL)b;
@end

@interface idRegisterList : NSObject
- (void)addReg:(NSString *)name type:(int)type parser:(idParser *)src window:(idWindow *)win var:(idWinVar *)var;
- (void)addReg:(NSString *)name type:(int)type data:(idVec4)data window:(idWindow *)win var:(idWinVar *)var;
- (nullable idRegister *)findReg:(NSString *)name;
- (void)setToRegs:(float *)registers;
- (void)getFromRegs:(float *)registers;
- (void)reset;
@end

NS_ASSUME_NONNULL_END
