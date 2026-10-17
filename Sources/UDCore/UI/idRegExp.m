/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 * idRegExp.m — ui/RegExp.cpp, ported (its demo and savegame parts left out).
 */

#import "idRegExp.h"
#import "idWindow.h"
#import "idWinVar.h"
#import "idUserInterface.h"
#import "idParser.h"
#import "idToken.h"
#import "idStr.h"
#import "UDDeclCodec.h"

const int idRegister_REGCOUNT[REG_NUMTYPES] = {4, 1, 1, 1, 0, 2, 3, 4};

@implementation idRegister

- (instancetype)initWithName:(NSString *)p type:(int)t {
    self = [super init];
    if (self) {
        name = [p copy];
        type = t;
        assert( t >= 0 && t < REG_NUMTYPES );
        regCount = idRegister_REGCOUNT[t];
        enabled = ( type == REG_STRING ) ? NO : YES;
        var = nil;
    }
    return self;
}

- (void)copyRegs:(idRegister *)src {
    regs[0] = src->regs[0];
    regs[1] = src->regs[1];
    regs[2] = src->regs[2];
    regs[3] = src->regs[3];
}

- (void)enable:(BOOL)b {
    enabled = b;
}

/*
====================
idRegister::SetToRegs
====================
*/
- (void)setToRegs:(float *)registers {
    int i;
    idVec4 v = { 0, 0, 0, 0 };
    idVec2 v2;
    idVec3 v3;
    idRectangle rect;

    if ( !enabled || var == nil || ( var && ( [var getDict] || ![var getEval] ) ) ) {
        return;
    }

    switch( type ) {
        case REG_VEC4: {
            v = [(idWinVec4 *)var data];
            break;
        }
        case REG_RECTANGLE: {
            rect = [(idWinRectangle *)var data];
            v = idRectangle_ToVec4( &rect );
            break;
        }
        case REG_VEC2: {
            v2 = [(idWinVec2 *)var data];
            v.x = v2.x;
            v.y = v2.y;
            break;
        }
        case REG_VEC3: {
            v3 = [(idWinVec3 *)var data];
            v.x = v3.x;
            v.y = v3.y;
            v.z = v3.z;
            break;
        }
        case REG_FLOAT: {
            v.x = [(idWinFloat *)var data];
            break;
        }
        case REG_INT: {
            v.x = [(idWinInt *)var data];
            break;
        }
        case REG_BOOL: {
            v.x = [(idWinBool *)var data];
            break;
        }
        default: {
            // common->FatalError( "idRegister::SetToRegs: bad reg type" );
            return;
        }
    }
    for ( i = 0; i < regCount; i++ ) {
        registers[ regs[ i ] ] = idVec4_Ptr( &v )[i];
    }
}

/*
=================
idRegister::GetFromRegs
=================
*/
- (void)getFromRegs:(float *)registers {
    idVec4 v = { 0, 0, 0, 0 };
    idRectangle rect;

    if (!enabled || var == nil || (var && ([var getDict] || ![var getEval]))) {
        return;
    }

    for ( int i = 0; i < regCount; i++ ) {
        idVec4_Ptr( &v )[i] = registers[regs[i]];
    }

    switch( type ) {
        case REG_VEC4: {
            [(idWinVec4 *)var setData:v];
            break;
        }
        case REG_RECTANGLE: {
            rect.x = v.x;
            rect.y = v.y;
            rect.w = v.z;
            rect.h = v.w;
            [(idWinRectangle *)var setData:rect];
            break;
        }
        case REG_VEC2: {
            [(idWinVec2 *)var setData:idVec2_Make( v.x, v.y )];
            break;
        }
        case REG_VEC3: {
            [(idWinVec3 *)var setData:idVec3_Make( v.x, v.y, v.z )];
            break;
        }
        case REG_FLOAT: {
            [(idWinFloat *)var setData:v.x];
            break;
        }
        case REG_INT: {
            [(idWinInt *)var setData:(int)v.x];
            break;
        }
        case REG_BOOL: {
            [(idWinBool *)var setData:( v.x != 0.0f )];
            break;
        }
        default: {
            // common->FatalError( "idRegister::GetFromRegs: bad reg type" );
            break;
        }
    }
}

@end

@implementation idRegisterList {
    NSMutableArray<idRegister *> *regs;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        regs = [NSMutableArray array];
    }
    return self;
}

/*
====================
idRegisterList::AddReg
====================
*/
- (void)addReg:(NSString *)name type:(int)type data:(idVec4)data window:(idWindow *)win var:(idWinVar *)var {
    if ( [self findReg:name] == nil ) {
        assert( type >= 0 && type < REG_NUMTYPES );
        int numRegs = idRegister_REGCOUNT[type];
        idRegister *reg = [[idRegister alloc] initWithName:name type:type];
        reg->var = var;
        for ( int i = 0; i < numRegs; i++ ) {
            reg->regs[i] = [win expressionConstant:idVec4_Ptr( &data )[i]];
        }
        [regs addObject:reg];
    }
}

/*
====================
idRegisterList::AddReg
====================
*/
- (void)addReg:(NSString *)name type:(int)type parser:(idParser *)src window:(idWindow *)win var:(idWinVar *)var {
    idRegister *reg;

    reg = [self findReg:name];

    if ( reg == nil ) {
        assert(type >= 0 && type < REG_NUMTYPES);
        int numRegs = idRegister_REGCOUNT[type];
        reg = [[idRegister alloc] initWithName:name type:type];
        reg->var = var;
        if ( type == REG_STRING ) {
            idToken tok;
            idToken_Init( &tok );
            if ( [src readToken:&tok error:NULL] ) {
                NSString *str = [[[win getGui] manager].languageDict getString:UDTokenLatin1String( &tok )];
                [var winVarInit:str window:win];
            }
        } else {
            for ( int i = 0; i < numRegs; i++ ) {
                reg->regs[i] = [win parseExpression:src var:nil component:0];
                if ( i < numRegs-1 ) {
                    [src expectTokenString:@"," error:NULL];
                }
            }
        }
        [regs addObject:reg];
    } else {
        int numRegs = idRegister_REGCOUNT[type];
        reg->var = var;
        if ( type == REG_STRING ) {
            idToken tok;
            idToken_Init( &tok );
            if ( [src readToken:&tok error:NULL] ) {
                [var winVarInit:UDTokenLatin1String( &tok ) window:win];
            }
        } else {
            for ( int i = 0; i < numRegs; i++ ) {
                reg->regs[i] = [win parseExpression:src var:nil component:0];
                if ( i < numRegs-1 ) {
                    [src expectTokenString:@"," error:NULL];
                }
            }
        }
    }
}

/*
====================
idRegisterList::GetFromRegs
====================
*/
- (void)getFromRegs:(float *)registers {
    for ( idRegister *reg in regs ) {
        [reg getFromRegs:registers];
    }
}

/*
====================
idRegisterList::SetToRegs
====================
*/
- (void)setToRegs:(float *)registers {
    for ( idRegister *reg in regs ) {
        [reg setToRegs:registers];
    }
}

/*
====================
idRegisterList::FindReg
====================
*/
- (idRegister *)findReg:(NSString *)name {
    for ( idRegister *reg in regs ) {
        if ( [reg->name ud_iequals:name] ) {
            return reg;
        }
    }
    return nil;
}

/*
====================
idRegisterList::Reset
====================
*/
- (void)reset {
    [regs removeAllObjects];
}

@end
