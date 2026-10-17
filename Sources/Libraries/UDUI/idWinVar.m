/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 * idWinVar.m — ui/Winvar.h, Winvar.cpp, ported. See idWinVar.h.
 */

#import "idWinVar.h"
#import "idDict.h"
#import "idStr.h"
#import "idWindow.h"
#import "idUserInterface.h"
#include <stdio.h>
#include <stdlib.h>

NSString *const VAR_GUIPREFIX = @"gui::";
static const NSUInteger VAR_GUIPREFIX_LEN = 5;

/// sscanf( val, format, … ) over four floats
static void ScanFloats( NSString *val, const char *format, float *a, float *b, float *c, float *d ) {
    sscanf( val.UTF8String, format, a, b, c, d );
}

@implementation idWinVar

- (instancetype)init {
    self = [super init];
    if (self) {
        guiDict = nil;
        name = nil;
        eval = YES;
    }
    return self;
}

- (void)setGuiInfo:(idDict *)gd name:(NSString *)_name {
    guiDict = gd;
    [self setName:_name];
}

- (NSString *)getName {
    if (name) {
        if (guiDict && [name hasPrefix:@"*"]) {
            return [guiDict getString:[name substringFromIndex:1]];
        }
        return name;
    }
    return @"";
}

- (void)setName:(NSString *)_name {
    name = [_name copy];
}

- (void)assign:(idWinVar *)other {
    guiDict = other->guiDict;
    [self setName:other->name];
}

- (idDict *)getDict { return guiDict; }
- (BOOL)needsUpdate { return (guiDict != nil); }

- (void)winVarInit:(NSString *)_name window:(idWindow *)win {
    NSString *key = _name;
    guiDict = nil;
    NSUInteger len = key.length;
    if (len > 5 && [key hasPrefix:@"gui:"]) {
        // key = key.Right( len - VAR_GUIPREFIX_LEN )
        [self setGuiInfo:[[win getGui] getStateDict] name:[key substringFromIndex:VAR_GUIPREFIX_LEN]];
        [win addUpdateVar:self];
    } else {
        [self set:key];
    }
}

- (void)set:(NSString *)val { }
- (void)update { }
- (NSString *)string { return @""; }
- (float)x { return 0.0f; }
- (void)setEval:(BOOL)b { eval = b; }
- (BOOL)getEval { return eval; }

@end

#pragma mark - idWinBool

@implementation idWinBool

- (void)winVarInit:(NSString *)_name window:(idWindow *)win {
    [super winVarInit:_name window:win];
    if (guiDict) {
        _data = [guiDict getBool:[self getName]];
    }
}

- (void)setData:(BOOL)other {
    _data = other;
    if (guiDict) {
        [guiDict setBool:[self getName] value:_data];
    }
}

- (void)assign:(idWinVar *)other {
    [super assign:other];
    _data = ((idWinBool *)other)->_data;
}

- (void)set:(NSString *)val {
    _data = ( atoi( val.UTF8String ) != 0 );
    if (guiDict) {
        [guiDict setBool:[self getName] value:_data];
    }
}

- (void)update {
    NSString *s = [self getName];
    if ( guiDict && s.length != 0 ) {
        _data = [guiDict getBool:s];
    }
}

- (NSString *)string { return [NSString stringWithFormat:@"%i", _data ? 1 : 0]; }

- (float)x { return _data ? 1.0f : 0.0f; }

@end

#pragma mark - idWinStr

@implementation idWinStr

- (instancetype)init {
    self = [super init];
    if (self) {
        data = @"";
    }
    return self;
}

- (void)winVarInit:(NSString *)_name window:(idWindow *)win {
    [super winVarInit:_name window:win];
    if (guiDict) {
        data = [guiDict getString:[self getName]];
    }
}

- (NSString *)data { return data; }

- (void)setData:(NSString *)other {
    data = [other copy];
    if (guiDict) {
        [guiDict set:[self getName] value:data];
    }
}

- (void)assign:(idWinVar *)other {
    [super assign:other];
    data = ((idWinStr *)other)->data;
}

- (NSUInteger)lengthWithoutColors {
    if (guiDict && name.length) {
        data = [guiDict getString:[self getName]];
    }
    return [data ud_lengthWithoutColors];
}

- (NSUInteger)length {
    if (guiDict && name.length) {
        data = [guiDict getString:[self getName]];
    }
    return data.length;
}

- (void)removeColors {
    if (guiDict && name.length) {
        data = [guiDict getString:[self getName]];
    }
    data = [data ud_stringByRemovingColors];
}

- (NSString *)string { return data; }

- (void)set:(NSString *)val {
    data = [val copy];
    if ( guiDict ) {
        [guiDict set:[self getName] value:data];
    }
}

- (void)update {
    NSString *s = [self getName];
    if ( guiDict && s.length != 0 ) {
        data = [guiDict getString:s];
    }
}

// return wether string is emtpy
- (float)x { return data.length ? 1.0f : 0.0f; }

@end

#pragma mark - idWinInt

@implementation idWinInt

- (void)winVarInit:(NSString *)_name window:(idWindow *)win {
    [super winVarInit:_name window:win];
    if (guiDict) {
        _data = [guiDict getInt:[self getName]];
    }
}

- (void)setData:(int)other {
    _data = other;
    if (guiDict) {
        [guiDict setInt:[self getName] value:_data];
    }
}

- (void)assign:(idWinVar *)other {
    [super assign:other];
    _data = ((idWinInt *)other)->_data;
}

- (void)set:(NSString *)val {
    _data = atoi( val.UTF8String );
    if (guiDict) {
        [guiDict setInt:[self getName] value:_data];
    }
}

- (void)update {
    NSString *s = [self getName];
    if ( guiDict && s.length != 0 ) {
        _data = [guiDict getInt:s];
    }
}

- (NSString *)string { return [NSString stringWithFormat:@"%i", _data]; }

// no suitable conversion
- (float)x { return 0.0f; }

@end

#pragma mark - idWinFloat

@implementation idWinFloat

- (void)winVarInit:(NSString *)_name window:(idWindow *)win {
    [super winVarInit:_name window:win];
    if (guiDict) {
        _data = [guiDict getFloat:[self getName]];
    }
}

- (void)assign:(idWinVar *)other {
    [super assign:other];
    _data = ((idWinFloat *)other)->_data;
}

- (void)setData:(float)other {
    _data = other;
    if (guiDict) {
        [guiDict setFloat:[self getName] value:_data];
    }
}

- (void)set:(NSString *)val {
    _data = atof( val.UTF8String );
    if (guiDict) {
        [guiDict setFloat:[self getName] value:_data];
    }
}

- (void)update {
    NSString *s = [self getName];
    if ( guiDict && s.length != 0 ) {
        _data = [guiDict getFloat:s];
    }
}

- (NSString *)string { return [NSString stringWithFormat:@"%f", _data]; }

- (float)x { return _data; }

@end

#pragma mark - idWinRectangle

@implementation idWinRectangle

- (void)winVarInit:(NSString *)_name window:(idWindow *)win {
    [super winVarInit:_name window:win];
    if (guiDict) {
        idVec4 v = [guiDict getVec4:[self getName]];
        _data.x = v.x;
        _data.y = v.y;
        _data.w = v.z;
        _data.h = v.w;
    }
}

- (void)assign:(idWinVar *)other {
    [super assign:other];
    _data = ((idWinRectangle *)other)->_data;
}

- (void)setVec4:(idVec4)other {
    _data = idRectangle_FromVec4( other );
    if (guiDict) {
        [guiDict setVec4:[self getName] value:other];
    }
}

- (void)setData:(idRectangle)other {
    _data = other;
    if (guiDict) {
        idVec4 v = idRectangle_ToVec4( &_data );
        [guiDict setVec4:[self getName] value:v];
    }
}

- (float)x { return _data.x; }
- (float)y { return _data.y; }
- (float)w { return _data.w; }
- (float)h { return _data.h; }
- (float)right { return idRectangle_Right( &_data ); }
- (float)bottom { return idRectangle_Bottom( &_data ); }
- (idVec4)toVec4 { return idRectangle_ToVec4( &_data ); }

- (void)set:(NSString *)val {
    if ( [val rangeOfString:@","].location != NSNotFound ) {
        ScanFloats( val, "%f,%f,%f,%f", &_data.x, &_data.y, &_data.w, &_data.h );
    } else {
        ScanFloats( val, "%f %f %f %f", &_data.x, &_data.y, &_data.w, &_data.h );
    }
    if (guiDict) {
        idVec4 v = idRectangle_ToVec4( &_data );
        [guiDict setVec4:[self getName] value:v];
    }
}

- (void)update {
    NSString *s = [self getName];
    if ( guiDict && s.length != 0 ) {
        idVec4 v = [guiDict getVec4:s];
        _data.x = v.x;
        _data.y = v.y;
        _data.w = v.z;
        _data.h = v.w;
    }
}

- (NSString *)string { return idVec4_ToString( idRectangle_ToVec4( &_data ) ); }

@end

#pragma mark - idWinVec2

@implementation idWinVec2

- (void)winVarInit:(NSString *)_name window:(idWindow *)win {
    [super winVarInit:_name window:win];
    if (guiDict) {
        _data = [guiDict getVec2:[self getName]];
    }
}

- (void)assign:(idWinVar *)other {
    [super assign:other];
    _data = ((idWinVec2 *)other)->_data;
}

- (void)setData:(idVec2)other {
    _data = other;
    if (guiDict) {
        [guiDict setVec2:[self getName] value:_data];
    }
}

- (float)x { return _data.x; }
- (float)y { return _data.y; }

- (void)set:(NSString *)val {
    if ( [val rangeOfString:@","].location != NSNotFound ) {
        sscanf( val.UTF8String, "%f,%f", &_data.x, &_data.y );
    } else {
        sscanf( val.UTF8String, "%f %f", &_data.x, &_data.y);
    }
    if (guiDict) {
        [guiDict setVec2:[self getName] value:_data];
    }
}

- (void)update {
    NSString *s = [self getName];
    if ( guiDict && s.length != 0 ) {
        _data = [guiDict getVec2:s];
    }
}

- (NSString *)string { return idVec2_ToString( _data ); }

- (void)zero {
    _data.x = _data.y = 0;
}

@end

#pragma mark - idWinVec4

@implementation idWinVec4

- (void)winVarInit:(NSString *)_name window:(idWindow *)win {
    [super winVarInit:_name window:win];
    if (guiDict) {
        _data = [guiDict getVec4:[self getName]];
    }
}

- (void)assign:(idWinVar *)other {
    [super assign:other];
    _data = ((idWinVec4 *)other)->_data;
}

- (void)setData:(idVec4)other {
    _data = other;
    if (guiDict) {
        [guiDict setVec4:[self getName] value:_data];
    }
}

- (float)x { return _data.x; }
- (float)y { return _data.y; }
- (float)z { return _data.z; }
- (float)w { return _data.w; }

- (void)set:(NSString *)val {
    if ( [val rangeOfString:@","].location != NSNotFound ) {
        ScanFloats( val, "%f,%f,%f,%f", &_data.x, &_data.y, &_data.z, &_data.w );
    } else {
        ScanFloats( val, "%f %f %f %f", &_data.x, &_data.y, &_data.z, &_data.w );
    }
    if ( guiDict ) {
        [guiDict setVec4:[self getName] value:_data];
    }
}

- (void)update {
    NSString *s = [self getName];
    if ( guiDict && s.length != 0 ) {
        _data = [guiDict getVec4:s];
    }
}

- (NSString *)string { return idVec4_ToString( _data ); }

- (void)zero {
    _data.x = _data.y = _data.z = _data.w = 0;
    if ( guiDict ) {
        [guiDict setVec4:[self getName] value:_data];
    }
}

- (idVec3)toVec3 { return idVec3_Make( _data.x, _data.y, _data.z ); }

@end

#pragma mark - idWinVec3

@implementation idWinVec3

- (void)winVarInit:(NSString *)_name window:(idWindow *)win {
    [super winVarInit:_name window:win];
    if (guiDict) {
        _data = [guiDict getVector:[self getName]];
    }
}

- (void)assign:(idWinVar *)other {
    [super assign:other];
    _data = ((idWinVec3 *)other)->_data;
}

- (void)setData:(idVec3)other {
    _data = other;
    if (guiDict) {
        [guiDict setVector:[self getName] value:_data];
    }
}

- (float)x { return _data.x; }
- (float)y { return _data.y; }
- (float)z { return _data.z; }

- (void)set:(NSString *)val {
    sscanf( val.UTF8String, "%f %f %f", &_data.x, &_data.y, &_data.z);
    if (guiDict) {
        [guiDict setVector:[self getName] value:_data];
    }
}

- (void)update {
    NSString *s = [self getName];
    if ( guiDict && s.length != 0 ) {
        _data = [guiDict getVector:s];
    }
}

- (NSString *)string { return idVec3_ToString( _data ); }

- (void)zero {
    _data.x = _data.y = _data.z = 0;
    if (guiDict) {
        [guiDict setVector:[self getName] value:_data];
    }
}

@end

#pragma mark - idWinBackground

@implementation idWinBackground {
    __weak id<idWinBackgroundTarget> mat;
}

- (void)winVarInit:(NSString *)_name window:(idWindow *)win {
    [super winVarInit:_name window:win];
    if (guiDict) {
        data = [guiDict getString:[self getName]];
    }
}

// (*mat) = data == "" ? NULL : declManager->FindMaterial( data )
- (void)updateMaterial {
    if (mat) {
        [mat setBackgroundMaterialNamed:data.length == 0 ? nil : data];
    }
}

- (void)setData:(NSString *)other {
    data = [other copy];
    if (guiDict) {
        [guiDict set:[self getName] value:data];
    }
    [self updateMaterial];
}

- (void)assign:(idWinVar *)other {
    // idWinVar::operator=, then its data and material pointer
    guiDict = other->guiDict;
    [self setName:other->name];
    data = ((idWinBackground *)other)->data;
    mat = ((idWinBackground *)other)->mat;
    [self updateMaterial];
}

- (NSUInteger)length {
    if (guiDict) {
        data = [guiDict getString:[self getName]];
    }
    return data.length;
}

- (void)set:(NSString *)val {
    data = [val copy];
    if (guiDict) {
        [guiDict set:[self getName] value:data];
    }
    [self updateMaterial];
}

- (void)update {
    NSString *s = [self getName];
    if ( guiDict && s.length != 0 ) {
        data = [guiDict getString:s];
        [self updateMaterial];
    }
}

- (void)setMaterialPtr:(id<idWinBackgroundTarget>)m {
    mat = m;
}

@end

#pragma mark - idMultiWinVar

@implementation idMultiWinVar

- (instancetype)init {
    self = [super init];
    if (self) {
        _list = [NSMutableArray array];
    }
    return self;
}

- (void)set:(NSString *)val {
    for ( idWinVar *var in self.list ) {
        [var set:val];
    }
}

- (void)update {
    for ( idWinVar *var in self.list ) {
        [var update];
    }
}

- (void)setGuiInfo:(idDict *)dict {
    for ( idWinVar *var in self.list ) {
        [var setGuiInfo:dict name:[var string]];
    }
}

@end
