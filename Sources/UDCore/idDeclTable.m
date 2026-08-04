/*
===========================================================================

Doom 3 GPL Source Code
Copyright (C) 1999-2011 id Software LLC, a ZeniMax Media company.

This file is part of the Doom 3 GPL Source Code (?Doom 3 Source Code?).

Doom 3 Source Code is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

Doom 3 Source Code is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with Doom 3 Source Code.  If not, see <http://www.gnu.org/licenses/>.

In addition, the Doom 3 Source Code is also subject to certain additional terms. You should have received a copy of these additional terms immediately following the terms and conditions of the GNU General Public License which accompanied the Doom 3 Source Code.  If not, please request a copy in writing from id Software at the address below.

If you have questions concerning this license or the applicable additional terms, you may contact in writing id Software LLC, c/o ZeniMax Media Inc., Suite 120, Rockville, Maryland 20850 USA.

===========================================================================
*/

#import "idDeclTable.h"
#import "UDWorkspace.h"

idDeclTable *idDeclTable_Allocator(void) {
    return [[idDeclTable alloc] init];
}


@interface idDeclTable ()

@property (nonatomic, strong) NSMutableArray<NSNumber *> *values;

@end

@implementation idDeclTable

-(instancetype)init {
    self = [super init];
    if (self) {
        _values = [[NSMutableArray alloc] init];
        [self freeData];
    }
    return self;
}

// jscott: to prevent a recursive crash
-(BOOL)rebuildTextSource {
    return NO;
}

-(float)tableLookupByIndex:(float)index {
    int iIndex;
    float iFrac;
    
    int domain = (int)_values.count - 1;

    if (domain <= 1) {
        return _values.count > 0 ? [[_values objectAtIndex:0] floatValue] : 1.0f;
    }

    if (_clamp) {
        index *= (domain-1);
        if (index >= domain - 1) {
            return [[_values objectAtIndex:domain - 1] floatValue];
        } else if ( index <= 0 ) {
            return [[_values objectAtIndex:0] floatValue];
        }
        iIndex = (int)index; // ftoi
        iFrac = index - iIndex;
    } else {
        index *= domain;

        if (index < 0) {
            index += domain * ceilf(-index / domain);
        }

        iIndex = (int)floorf(index);
        iFrac = index - iIndex;
        iIndex = iIndex % domain;
        if (iIndex < 0 || iFrac < 0.0f) {
            iIndex = 0;
            iFrac = 0.0f;
        }
    }

    if (!_snap) {
        // we duplicated the 0 index at the end at creation time, so we
        // don't need to worry about wrapping the filter
        return [[_values objectAtIndex:iIndex] floatValue] * (1.0f - iFrac) + [[_values objectAtIndex:iIndex + 1] floatValue] * iFrac;
    }
    
    return [[_values objectAtIndex:iIndex] floatValue];
}

-(size_t)size {
    //return sizeof( idDeclTable ) + values.Allocated();
    return 0;
}

-(void)freeData {
    _snap = NO;
    _clamp = NO;
    _minValue = INFINITY;
    _maxValue = -INFINITY;
    [_values removeAllObjects];
}

-(NSString *)defaultDefinition {
    return @"{ { 0 } }";
}

-(BOOL)parse:(NSMutableData *)text error:(NSError **)error {
    return [self parse:text noCaching:NO error:error];
}

-(BOOL)parse:(NSMutableData *)text noCaching:(BOOL)noCaching error:(NSError **)error {
    idLexer *src;
    idToken token;
    float v;
    
    idToken_Init(&token);

    src = [[idLexer alloc] initWithFileSystem: self.declManager.workspace.fileSystem];
    if (![src loadMemory:text.bytes length:text.length - 1 name:[self fileName] startLine:[self lineNum] error:error]) {
        return NO;
    }
    [src setFlags:DECL_LEXER_FLAGS];
    if (![src skipUntilString:@"{" error:error]) {
        return  NO;
    }

    _snap = NO;
    _clamp = NO;
    _minValue = INFINITY;
    _maxValue = -INFINITY;
    [_values removeAllObjects];

    while (1) {
        if (![src readToken:&token error:error]) {
            break;
        }

        if (!strcmp(token.text, "}")) {
            break;
        }

        if (strcasecmp(token.text, "snap") == 0) {
            _snap = YES;
        } else if (strcasecmp(token.text, "clamp") == 0) {
            _clamp = YES;
        } else if (strcmp(token.text, "{") == 0) {

            while (1) {

                if (![src parseFloat:&v error:error]) {
                    // we got something non-numeric
                    [self makeDefault:error];
                    return NO;
                }

                [_values addObject:@(v)];
                if (v < _minValue) {
                    _minValue = v;
                }
                if (v > _maxValue) {
                    _maxValue = v;
                }

                [src readToken:&token error:error];
                if (!strcmp(token.text, "}")) {
                    break;
                }
                if (!strcmp(token.text, ",")) {
                    continue;
                }
                [src warning:@"expected comma or brace"];
                [self makeDefault:error];
                return false;
            }

        } else {
            [src warning:@"unknown token '%s'", token.text];
            [self makeDefault:error];
            return NO;
        }
    }

    if (_values.count == 0) {
        [src warning:@"table '%@' has no values", [self name]];
        [self makeDefault:error];
        return NO;
    }

    // copy the 0 element to the end, so lerping doesn't
    // need to worry about the wrap case
    NSNumber *val = [_values objectAtIndex:0];        // template bug requires this to not be in the Append()?
    [_values addObject:[val copy]];

    return YES;
}

-(BOOL)validate:(NSMutableData *)psText reportTo:(NSMutableString *)strReportTo {
    idDecl *decl = [self.declManager allocateDecl:DECL_TABLE];
    BOOL valid = DeclManager_ValidateParsedDecl(decl, DECL_TABLE, decl != nil && [decl parse:psText noCaching:NO error:nil]);
    if (decl != nil) {
        [decl freeData];
    }
    DeclManager_FreeAllocatedDecl(decl);
    return valid;
}

@end
