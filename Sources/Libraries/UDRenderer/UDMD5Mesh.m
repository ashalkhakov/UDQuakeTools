/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 * UDMD5Mesh.m — a model's joints.
 *
 * Ported from neo/game/anim/Anim_Blend.cpp (idDeclModelDef::Parse, as far
 * as its mesh: anims and channels come after it, the engine says) and
 * neo/renderer/Model_md5.cpp (idRenderModelMD5::LoadModel and ParseJoint,
 * as far as the joints).
 */

#import "UDMD5Mesh.h"
#import <objc/runtime.h>

#import "idDeclManager.h"
#import "idFileSystem.h"
#import "idLexer.h"
#import "idToken.h"
#import "UDDeclCodec.h"

static NSString *const MD5_VERSION_STRING = @"MD5Version";
static const int MD5_VERSION = 10;

static NSError *UDMD5Error(NSString *message) {
    return [NSError errorWithDomain:@"UDMD5Mesh" code:1 userInfo:@{NSLocalizedDescriptionKey: message}];
}

@implementation UDMD5Mesh

+ (NSArray<NSString *> *)jointNamesOfMeshAtPath:(NSString *)path fileSystem:(idFileSystem *)fileSystem error:(NSError **)error {
    void *buffer = NULL;
    int length = [fileSystem readFile:path buffer:&buffer timestamp:NULL error:NULL];
    if (length < 0 || buffer == NULL) {
        if (error != NULL) *error = UDMD5Error([NSString stringWithFormat:@"No mesh “%@”", path]);
        return nil;
    }
    NSMutableData *text = [NSMutableData dataWithBytes:buffer length:(NSUInteger)length];
    [fileSystem freeFile:buffer error:NULL];
    [text appendBytes:"" length:1];

    idLexer *parser = [[idLexer alloc] initWithFileSystem:fileSystem];
    if (![parser loadMemory:text.bytes length:length name:path startLine:1 error:NULL]) {
        if (error != NULL) *error = UDMD5Error([NSString stringWithFormat:@"Mesh “%@” could not be read", path]);
        return nil;
    }
    objc_setAssociatedObject(parser, (__bridge const void *)parser, text, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [parser setFlags:LEXFL_ALLOWPATHNAMES | LEXFL_NOSTRINGESCAPECHARS | LEXFL_NOERRORS | LEXFL_NOWARNINGS];

    idToken token;
    idToken_Init(&token);
    int version = 0, numJoints = 0, numMeshes = 0;

    [parser expectTokenString:MD5_VERSION_STRING error:NULL];
    [parser parseInt:&version error:NULL];
    if ( version != MD5_VERSION ) {
        if (error != NULL) *error = UDMD5Error([NSString stringWithFormat:@"Invalid version %d.  Should be version %d", version, MD5_VERSION]);
        return nil;
    }
    // skip commandline
    [parser expectTokenString:@"commandline" error:NULL];
    [parser readToken:&token error:NULL];
    // parse num joints
    [parser expectTokenString:@"numJoints" error:NULL];
    [parser parseInt:&numJoints error:NULL];
    // parse num meshes
    [parser expectTokenString:@"numMeshes" error:NULL];
    [parser parseInt:&numMeshes error:NULL];
    if ( numMeshes < 0 ) {
        if (error != NULL) *error = UDMD5Error([NSString stringWithFormat:@"Invalid size: %d", numMeshes]);
        return nil;
    }
    // parse joints
    if ( ![parser expectTokenString:@"joints" error:NULL] || ![parser expectTokenString:@"{" error:NULL] ) {
        if (error != NULL) *error = UDMD5Error([NSString stringWithFormat:@"Mesh “%@” has no joints", path]);
        return nil;
    }
    NSMutableArray<NSString *> *names = [NSMutableArray arrayWithCapacity:(NSUInteger)MAX(numJoints, 0)];
    for ( int i = 0; i < numJoints; i++ ) {
        // ParseJoint: its name, its parent, its default pose.
        [parser readToken:&token error:NULL];
        [names addObject:UDTokenString( &token )];
        int parent = 0;
        [parser parseInt:&parent error:NULL];
        float t[3], q[3];
        [parser parse1DMatrix:3 matrix:t error:NULL];
        [parser parse1DMatrix:3 matrix:q error:NULL];
    }
    if ( ![parser expectTokenString:@"}" error:NULL] ) {
        if (error != NULL) *error = UDMD5Error([NSString stringWithFormat:@"Mesh “%@”'s joints are not all there", path]);
        return nil;
    }
    return names;
}

+ (NSString *)meshOfModelDef:(NSString *)name declManager:(idDeclManager *)declManager {
    return [self _meshOfModelDef:name declManager:declManager visited:[NSMutableSet set]];
}

+ (NSString *)_meshOfModelDef:(NSString *)name declManager:(idDeclManager *)declManager visited:(NSMutableSet<NSString *> *)visited {
    if (name.length == 0 || [visited containsObject:name.lowercaseString]) return nil;
    [visited addObject:name.lowercaseString];
    idDeclBase *decl = [declManager findDeclWithoutParsing:DECL_MODELDEF name:name makeDefault:NO];
    if (decl == nil) return nil;
    NSMutableData *text = [NSMutableData data];
    [decl text:text];
    idLexer *src = UDDeclCodecLexer([text subdataWithRange:NSMakeRange(0, text.length > 0 ? text.length - 1 : 0)],
                                    name, nil, 1, nil, NULL);
    if (src == nil) return nil;
    [src setFlags:DECL_LEXER_FLAGS | LEXFL_NOERRORS | LEXFL_NOWARNINGS];

    idToken token, token2;
    idToken_Init(&token);
    idToken_Init(&token2);
    NSString *mesh = nil;
    while ( 1 ) {
        if ( ![src readToken:&token error:NULL] ) {
            break;
        }
        if ( !strcasecmp( token.text, "}" ) ) {
            break;
        }
        if ( !strcmp( token.text, "inherit" ) ) {
            if ( ![src readToken:&token2 error:NULL] ) break;
            // CopyDecl: the inherited model's mesh, until one of its own.
            mesh = [self _meshOfModelDef:UDTokenString( &token2 ) declManager:declManager visited:visited] ?: mesh;
        } else if ( !strcmp( token.text, "skin" ) || !strcmp( token.text, "remove" ) ) {
            if ( ![src readToken:&token2 error:NULL] ) break;
        } else if ( !strcmp( token.text, "mesh" ) ) {
            if ( ![src readToken:&token2 error:NULL] ) break;
            NSString *filename = UDTokenString( &token2 );
            // "Invalid model for MD5 mesh"
            return [filename.pathExtension.lowercaseString isEqualToString:@"md5mesh"] ? filename : nil;
        } else if ( !strcmp( token.text, "offset" ) ) {
            float offset[3];
            if ( ![src parse1DMatrix:3 matrix:offset error:NULL] ) break;
        } else {
            // anims and channels: after the mesh ("Must specify mesh before …").
            break;
        }
    }
    return mesh;
}

+ (NSArray<NSString *> *)jointNamesOfModelDef:(NSString *)name declManager:(idDeclManager *)declManager fileSystem:(idFileSystem *)fileSystem {
    NSString *mesh = [self meshOfModelDef:name declManager:declManager];
    return mesh != nil ? [self jointNamesOfMeshAtPath:mesh fileSystem:fileSystem error:NULL] : nil;
}

@end
