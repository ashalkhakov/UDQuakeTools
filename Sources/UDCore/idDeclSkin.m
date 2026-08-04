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

#import "idDeclSkin.h"
#import "UDWorkspace.h"

idDeclSkin *idDeclSkin_Allocator(void) {
    return [[idDeclSkin alloc] init];
}

@implementation idSkinMapping
@end

@interface idDeclSkin ()

@property (nonatomic, strong) NSMutableArray<idSkinMapping *> *mappings;
@property (nonatomic, strong) NSMutableArray<NSString *> *associatedModels;

@end

@implementation idDeclSkin

-(instancetype)init {
    self = [super init];
    if (self) {
        _mappings = [[NSMutableArray alloc] init];
        _associatedModels = [[NSMutableArray alloc] init];
    }
    return self;
}

-(size_t)size {
    /*
     size_t size = sizeof( idDeclSkin ) + mappings.Allocated() + associatedModels.Allocated();
     
     for ( int i = 0; i < associatedModels.Num(); i++ ) {
     size += associatedModels[i].Allocated();
     }
     
     return size;*/
    return 0;
}

-(void)freeData {
    [_mappings removeAllObjects];
    [_associatedModels removeAllObjects];
}

-(BOOL)parse:(NSMutableData *)text error:(NSError **)error {
    return [self parse:text noCaching:NO error:error];
}

-(BOOL)parse:(NSMutableData *)text noCaching:(BOOL)noCaching error:(NSError **)error {
    idToken token, token2;
    idLexer *src;
    
    idToken_Init(&token);
    idToken_Init(&token2);
    
    src = [[idLexer alloc] initWithFileSystem: self.declManager.workspace.fileSystem];
    if (![src loadMemory:text.bytes length:text.length - 1 name:[self fileName] startLine:[self lineNum] error:error]) {
        return NO;
    }
    [src setFlags:DECL_LEXER_FLAGS];
    if (![src skipUntilString:@"{" error:error]) {
        return  NO;
    }
    
    [_associatedModels removeAllObjects];
    
    while (1) {
        if (![src readToken:&token error:error]) {
            break;
        }
        
        if (!strcasecmp(token.text, "}")) {
            break;
        }
        if (![src readToken:&token2 error:error]) {
            [src warning:@"Unexpected end of file"];
            [self makeDefault:error];
            return NO;
        }
        
        if (!strcasecmp(token.text, "model")) {
            [_associatedModels addObject:[NSString stringWithUTF8String:token2.text]];
            continue;
        }
        
        idSkinMapping *map = [[idSkinMapping alloc] init];
        
        if (!strcasecmp(token.text, "*")) {
            // wildcard
            map.from = nil;
        } else {
            map.from = [self.declManager findMaterial:[NSString stringWithUTF8String:token.text] error:error];
        }
        
        map.to = [self.declManager findMaterial:[NSString stringWithUTF8String:token2.text] error:error];
        
        [_mappings addObject:map];
    }
    
    return NO;
}

-(BOOL)setDefaultText {
    NSError *error = nil;
    
    // if there exists a material with the same name
    if ([self.declManager findType:DECL_MATERIAL name:[self name] makeDefault:NO error:&error]) {
        NSMutableData *generated = [[NSMutableData alloc] initWithCapacity:2048];
        
        [generated appendUTF8StringAndNullTerminate:"skin "];
        [generated appendUTF8StringAndNullTerminate:[self name].UTF8String];
        [generated appendUTF8StringAndNullTerminate:" // IMPLICITLY GENERATED\n"];
        [generated appendUTF8StringAndNullTerminate:"{\n"];
        [generated appendUTF8StringAndNullTerminate:"_default "];
        [generated appendUTF8StringAndNullTerminate:[self name].UTF8String];
        [generated appendUTF8StringAndNullTerminate:"\n}\n"];
        
        [self setText:generated];
        
        return YES;
    } else {
        return NO;
    }
}

-(NSString *)defaultDefinition {
    return
    @"{\n"
    @"\t"    @"\"*\"\t\"_default\"\n"
    @"}";
}

-(idDeclMaterial *)remapShaderBySkin:(idDeclMaterial *)shader {
    int        i;
    
    if (!shader) {
        return nil;
    }
    
    // never remap surfaces that were originally nodraw, like collision hulls
    /*
     if ( !shader->IsDrawn() ) {
     return shader;
     }
     */
    
    for (i = 0; i < _mappings.count; i++ ) {
        idSkinMapping    *map = [_mappings objectAtIndex:i];
        
        // NULL = wildcard match
        if (!map.from || map.from == shader) {
            return map.to;
        }
    }
    
    // didn't find a match or wildcard, so stay the same
    return shader;
}

-(BOOL)validate:(NSMutableData *)psText reportTo:(NSMutableString *)strReportTo {
    idDecl *decl = [self.declManager allocateDecl:DECL_SKIN];
    BOOL valid = DeclManager_ValidateParsedDecl(decl, DECL_SKIN, decl != nil && [decl parse:psText noCaching:NO error:nil]);
    if (decl != nil) {
        [decl freeData];
    }
    DeclManager_FreeAllocatedDecl(decl);
    return valid;
}

// RAVEN BEGIN
// jscott: inlined for access from tools dll
-(NSString *)associatedModelByIndex:(int)index {
    if (index >= 0 && index < _associatedModels.count) {
        return [_associatedModels objectAtIndex:(NSUInteger)index];
    }
    return @"";
}
// RAVEN END

@end
