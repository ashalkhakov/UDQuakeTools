/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 * idCVarSystem.m — framework/CVarSystem.cpp's idInternalCVar, ported (its
 * Set and UpdateValue), over the cvars of idCVarDefaults.inc.
 */

#import "idCVarSystem.h"
#import "idStr.h"
#include <stdlib.h>

typedef struct {
    const char *name;
    const char *value;
    char        type;       // 'b' CVAR_BOOL, 'i' CVAR_INTEGER, 'f' CVAR_FLOAT, 's' none
    float       valueMin;
    float       valueMax;
} cvarDefault_t;

static const cvarDefault_t cvarDefaults[] = {
#include "idCVarDefaults.inc"
};

/*
============
idStr::IsNumeric
============
*/
static BOOL IsNumeric( NSString *s ) {
    NSUInteger i = 0, length = s.length;
    BOOL dot;

    if ( i < length && [s characterAtIndex:i] == '-' ) {
        i++;
    }

    dot = NO;
    for ( ; i < length; i++ ) {
        unichar c = [s characterAtIndex:i];
        if ( !( c >= '0' && c <= '9' ) ) {
            if ( ( c == '.' ) && !dot ) {
                dot = YES;
                continue;
            }
            return NO;
        }
    }

    return YES;
}

// idStr( float ): "%f", its trailing zeros and point off
static NSString *FloatString( float f ) {
    NSMutableString *text = [NSMutableString stringWithFormat:@"%f", f];
    while ( text.length > 0 && [text characterAtIndex:text.length - 1] == '0' ) [text deleteCharactersInRange:NSMakeRange( text.length - 1, 1 )];
    while ( text.length > 0 && [text characterAtIndex:text.length - 1] == '.' ) [text deleteCharactersInRange:NSMakeRange( text.length - 1, 1 )];
    return text;
}

@implementation idCVar {
@public
    NSString   *nameString;
    NSString   *resetString;
    NSString   *valueString;
    char        type;
    float       valueMin;
    float       valueMax;
    int         integerValue;
    float       floatValue;
}

- (instancetype)initWithName:(NSString *)name value:(NSString *)value type:(char)aType min:(float)min max:(float)max {
    self = [super init];
    if (self) {
        nameString = [name copy];
        resetString = [value copy];
        valueString = [value copy];
        type = aType;
        valueMin = min;
        valueMax = max;
        [self updateValue];
    }
    return self;
}

/*
============
idInternalCVar::UpdateValue
============
*/
- (void)updateValue {
    BOOL clamped = NO;

    if ( type == 'b' ) {
        integerValue = ( atoi( valueString.UTF8String ) != 0 );
        floatValue = integerValue;
        if ( ![valueString ud_iequals:@"0"] && ![valueString ud_iequals:@"1"] ) {
            valueString = ( integerValue != 0 ) ? @"1" : @"0";
        }
    } else if ( type == 'i' ) {
        integerValue = (int)atoi( valueString.UTF8String );
        if ( valueMin < valueMax ) {
            if ( integerValue < valueMin ) {
                integerValue = (int)valueMin;
                clamped = YES;
            } else if ( integerValue > valueMax ) {
                integerValue = (int)valueMax;
                clamped = YES;
            }
        }
        if ( clamped || !IsNumeric( valueString ) || [valueString rangeOfString:@"."].location != NSNotFound ) {
            valueString = [NSString stringWithFormat:@"%d", integerValue];
        }
        floatValue = (float)integerValue;
    } else if ( type == 'f' ) {
        floatValue = (float)atof( valueString.UTF8String );
        if ( valueMin < valueMax ) {
            if ( floatValue < valueMin ) {
                floatValue = valueMin;
                clamped = YES;
            } else if ( floatValue > valueMax ) {
                floatValue = valueMax;
                clamped = YES;
            }
        }
        if ( clamped || !IsNumeric( valueString ) ) {
            valueString = FloatString( floatValue );
        }
        integerValue = (int)floatValue;
    } else {
        if ( valueString.length < 32 ) {
            floatValue = (float)atof( valueString.UTF8String );
            integerValue = (int)floatValue;
        } else {
            floatValue = 0.0f;
            integerValue = 0;
        }
    }
}

/*
============
idInternalCVar::Set( newValue, force true )
============
*/
- (void)set:(NSString *)newValue {
    if ( !newValue ) {
        newValue = resetString;
    }

    if ( [valueString ud_iequals:newValue] ) {
        return;
    }

    valueString = [newValue copy];
    [self updateValue];
}

- (NSString *)getName { return nameString; }
- (NSString *)getString { return valueString; }
- (BOOL)getBool { return ( integerValue != 0 ); }
- (int)getInteger { return integerValue; }
- (float)getFloat { return floatValue; }

- (void)setString:(NSString *)value { [self set:value]; }
- (void)setBool:(BOOL)value { [self set:value ? @"1" : @"0"]; }
- (void)setInteger:(int)value { [self set:[NSString stringWithFormat:@"%d", value]]; }
- (void)setFloat:(float)value { [self set:FloatString( value )]; }
- (void)reset { [self set:resetString]; }

@end

@implementation idCVarSystem {
    NSMutableDictionary<NSString *, idCVar *> *cvars;       // by name, A–Z lowered
}

- (instancetype)init {
    self = [super init];
    if (self) {
        cvars = [NSMutableDictionary dictionary];
        for ( size_t i = 0; i < sizeof( cvarDefaults ) / sizeof( cvarDefaults[0] ); i++ ) {
            const cvarDefault_t *d = &cvarDefaults[i];
            NSString *name = [NSString stringWithUTF8String:d->name];
            idCVar *cvar = [[idCVar alloc] initWithName:name value:[NSString stringWithUTF8String:d->value]
                                                   type:d->type min:d->valueMin max:d->valueMax];
            cvars[name.lowercaseString] = cvar;
        }
    }
    return self;
}

// FindInternal: the names compared ignoring case
- (idCVar *)find:(NSString *)name {
    return cvars[name.lowercaseString];
}

- (NSString *)getString:(NSString *)name {
    idCVar *cvar = [self find:name];
    return cvar ? [cvar getString] : @"";
}

- (BOOL)getBool:(NSString *)name {
    idCVar *cvar = [self find:name];
    return cvar ? [cvar getBool] : NO;
}

- (int)getInt:(NSString *)name {
    idCVar *cvar = [self find:name];
    return cvar ? [cvar getInteger] : 0;
}

- (float)getFloat:(NSString *)name {
    idCVar *cvar = [self find:name];
    return cvar ? [cvar getFloat] : 0.0f;
}

/*
============
idCVarSystemLocal::SetInternal
============
*/
- (void)set:(NSString *)name value:(NSString *)value {
    idCVar *cvar = [self find:name];
    if ( cvar ) {
        [cvar setString:value];
    } else {
        cvars[name.lowercaseString] = [[idCVar alloc] initWithName:name value:value type:'s' min:1.0f max:-1.0f];
    }
}

- (void)setBool:(NSString *)name value:(BOOL)value {
    [self set:name value:value ? @"1" : @"0"];
}

@end
