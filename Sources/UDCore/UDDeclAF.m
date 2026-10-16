/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 * UDDeclAF.m — articulated figures (idDeclAF).
 *
 * Ported from neo/framework/DeclAF.cpp: idAFVector::Parse and Write,
 * idDeclAF::Parse and its ParseSettings, ParseBody and constraint parsers,
 * ContentsFromString and ContentsToString, and the Write functions
 * RebuildTextSource writes the figure with. The values are kept as the text
 * has them (an idAFVector as its text, not resolved against a model's
 * joints, which idDeclAF::Finish does in the game).
 */

#import "UDDeclManagedObjects.h"
#import "UDDeclAF.h"
#import <objc/runtime.h>

#import "UDDeclCodec.h"
#import "idLexer.h"
#import "idToken.h"
#import "idStr.h"

// renderer/Material.h's contents bits ContentsFromString knows.
enum {
    UD_CONTENTS_SOLID       = 1 << 0,
    UD_CONTENTS_PLAYERCLIP  = 1 << 3,
    UD_CONTENTS_MONSTERCLIP = 1 << 4,
    UD_CONTENTS_BODY        = 1 << 8,
    UD_CONTENTS_CORPSE      = 1 << 10,
};

/// A lexer over @a text with the decl manager's flags.
static idLexer *UDAFLexer(NSString *text) {
    NSMutableData *buffer = [[text dataUsingEncoding:NSUTF8StringEncoding] mutableCopy] ?: [NSMutableData data];
    NSUInteger length = buffer.length;
    [buffer appendBytes:"" length:1];
    idLexer *src = [[idLexer alloc] initWithFileSystem:nil];
    if (![src loadMemory:buffer.bytes length:(int)length name:@"idDeclAF" startLine:1 error:NULL]) {
        return nil;
    }
    objc_setAssociatedObject(src, (__bridge const void *)src, buffer, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [src setFlags:DECL_LEXER_FLAGS | LEXFL_NOERRORS | LEXFL_NOWARNINGS];
    return src;
}

@interface UDDeclAF (UDSettings)
+ (NSDictionary<NSString *, id> *)ud_defaultSettings;
@end

#pragma mark - idAFVector

/// idAFVector::Parse, into the vector's text; NO where it returns false.
static BOOL UDAFParseVector(idLexer *src, NSString **vector) {
    idToken token;
    idToken_Init(&token);
    BOOL negate;

    if ( ![src readToken:&token error:NULL] ) {
        return NO;
    }
    if ( !strcmp( token.text, "-" ) ) {
        negate = YES;
        if ( ![src readToken:&token error:NULL] ) {
            return NO;
        }
    } else {
        negate = NO;
    }

    NSString *text = nil;
    if ( !strcmp( token.text, "(" ) ) {
        float x = 0, y = 0, z = 0;
        [src parseFloat:&x error:NULL];
        [src expectTokenString:@"," error:NULL];
        [src parseFloat:&y error:NULL];
        [src expectTokenString:@"," error:NULL];
        [src parseFloat:&z error:NULL];
        [src expectTokenString:@")" error:NULL];
        text = [NSString stringWithFormat:@"( %g, %g, %g )", x, y, z];
    } else if ( !strcmp( token.text, "joint" ) ) {
        [src expectTokenString:@"(" error:NULL];
        [src readToken:&token error:NULL];
        text = [NSString stringWithFormat:@"joint( \"%@\" )", UDTokenString( &token )];
        [src expectTokenString:@")" error:NULL];
    } else if ( !strcmp( token.text, "bonecenter" ) || !strcmp( token.text, "bonedir" ) ) {
        NSString *kind = UDTokenString( &token );
        [src expectTokenString:@"(" error:NULL];
        [src readToken:&token error:NULL];
        NSString *joint1 = UDTokenString( &token );
        [src expectTokenString:@"," error:NULL];
        [src readToken:&token error:NULL];
        NSString *joint2 = UDTokenString( &token );
        [src expectTokenString:@")" error:NULL];
        text = [NSString stringWithFormat:@"%@( \"%@\", \"%@\" )", kind, joint1, joint2];
    } else {
        [src error:NULL format:@"unknown token %s in vector", token.text];
        return NO;
    }
    *vector = negate ? [@"-" stringByAppendingString:text] : text;
    return YES;
}

/// idAFVector::Write's text of @a vector ("%f" coordinates).
static NSString *UDAFWriteVector(NSString *vector) {
    idLexer *src = UDAFLexer(vector ?: @"");
    idToken token;
    idToken_Init(&token);
    NSMutableString *out = [NSMutableString string];
    if ( src == nil || ![src readToken:&token error:NULL] ) {
        return @"( 0.000000, 0.000000, 0.000000 )";
    }
    if ( !strcmp( token.text, "-" ) ) {
        [out appendString:@"-"];
        [src readToken:&token error:NULL];
    }
    if ( !strcmp( token.text, "(" ) ) {
        float v[3] = { 0, 0, 0 };
        for ( int i = 0; i < 3; i++ ) {
            if ( i > 0 ) [src expectTokenString:@"," error:NULL];
            [src parseFloat:&v[i] error:NULL];
        }
        [out appendFormat:@"( %f, %f, %f )", v[0], v[1], v[2]];
    } else {
        [out appendString:[vector stringByReplacingOccurrencesOfString:@"-" withString:@"" options:NSAnchoredSearch
                                                                 range:NSMakeRange(0, vector.length)]];
    }
    return out;
}

/// What ToVec3() is before idDeclAF::Finish resolves the joints: the
/// coordinates, or zero.
static BOOL UDAFVectorIsZero(NSString *vector) {
    idLexer *src = UDAFLexer(vector ?: @"");
    idToken token;
    idToken_Init(&token);
    if ( src == nil || ![src readToken:&token error:NULL] ) return YES;
    if ( !strcmp( token.text, "-" ) ) [src readToken:&token error:NULL];
    if ( strcmp( token.text, "(" ) ) return YES;
    for ( int i = 0; i < 3; i++ ) {
        float f = 0;
        if ( i > 0 ) [src expectTokenString:@"," error:NULL];
        [src parseFloat:&f error:NULL];
        if ( f != 0.0f ) return NO;
    }
    return YES;
}

#pragma mark - Contents

static int UDAFContentsFromString(NSString *str) {
    idLexer *src = UDAFLexer(str ?: @"");
    idToken token;
    idToken_Init(&token);
    int c = 0;
    while ( src != nil && [src readToken:&token error:NULL] ) {
        if ( !strcasecmp( token.text, "none" ) ) {
            c = 0;
        } else if ( !strcasecmp( token.text, "solid" ) ) {
            c |= UD_CONTENTS_SOLID;
        } else if ( !strcasecmp( token.text, "body" ) ) {
            c |= UD_CONTENTS_BODY;
        } else if ( !strcasecmp( token.text, "corpse" ) ) {
            c |= UD_CONTENTS_CORPSE;
        } else if ( !strcasecmp( token.text, "playerclip" ) ) {
            c |= UD_CONTENTS_PLAYERCLIP;
        } else if ( !strcasecmp( token.text, "monsterclip" ) ) {
            c |= UD_CONTENTS_MONSTERCLIP;
        } else if ( !strcmp( token.text, "," ) ) {
            continue;
        } else {
            return c;
        }
    }
    return c;
}

static NSString *UDAFContentsToString(int contents) {
    NSMutableArray<NSString *> *names = [NSMutableArray array];
    if ( contents & UD_CONTENTS_SOLID ) [names addObject:@"solid"];
    if ( contents & UD_CONTENTS_BODY ) [names addObject:@"body"];
    if ( contents & UD_CONTENTS_CORPSE ) [names addObject:@"corpse"];
    if ( contents & UD_CONTENTS_PLAYERCLIP ) [names addObject:@"playerclip"];
    if ( contents & UD_CONTENTS_MONSTERCLIP ) [names addObject:@"monsterclip"];
    return names.count > 0 ? [names componentsJoinedByString:@", "] : @"none";
}

/// idDeclAF::ParseContents.
static NSString *UDAFParseContents(idLexer *src) {
    idToken token;
    idToken_Init(&token);
    NSMutableString *str = [NSMutableString string];
    while ( [src readToken:&token error:NULL] ) {
        [str appendString:UDTokenString( &token )];
        if ( ![src checkTokenString:@"," error:NULL] ) {
            break;
        }
        [str appendString:@","];
    }
    return UDAFContentsToString( UDAFContentsFromString( str ) );
}

#pragma mark - Bodies and constraints

@implementation UDAFBody

/// idDeclAF_Body::SetDefault, with @a file's settings.
- (instancetype)initWithSettings:(NSDictionary<NSString *, id> *)file {
    self = [super init];
    if (self) {
        _name = @"noname";
        _modelType = @"box";
        _v1 = @"( -10, -10, -10 )";
        _v2 = @"( 10, 10, 10 )";
        _numSides = 3;
        _width = 0.0f;
        _origin = @"( 0, 0, 0 )";
        _angles = @"( 0, 0, 0 )";
        _density = 0.2f;
        _inertiaScale = @"1 0 0 0 1 0 0 0 1";
        _linearFriction = [file[@"defaultLinearFriction"] floatValue];
        _angularFriction = [file[@"defaultAngularFriction"] floatValue];
        _contactFriction = [file[@"defaultContactFriction"] floatValue];
        _contents = file[@"contents"];
        _clipMask = file[@"clipMask"];
        _selfCollision = [file[@"selfCollision"] boolValue];
        _frictionDirection = @"( 0, 0, 0 )";
        _contactMotorDirection = @"( 0, 0, 0 )";
        _jointName = @"origin";
        _jointMod = @"orientation";
        _containedJoints = @"*origin";
    }
    return self;
}

- (instancetype)init {
    return [self initWithSettings:[UDDeclAF ud_defaultSettings]];
}

- (BOOL)validateValue:(id *)ioValue forKey:(NSString *)key error:(NSError **)error {
    if ([key isEqualToString:@"v1"] || [key isEqualToString:@"v2"] || [key isEqualToString:@"origin"] ||
        [key isEqualToString:@"frictionDirection"] || [key isEqualToString:@"contactMotorDirection"] ||
        [key isEqualToString:@"angles"]) {
        NSString *vector = [*ioValue isKindOfClass:[NSString class]] ? [UDDeclAF ud_normalizedVector:*ioValue] : nil;
        if (vector != nil) {
            *ioValue = vector;
            return YES;
        }
        if (error != NULL) {
            *error = [NSError errorWithDomain:@"UDAFBody" code:1 userInfo:@{NSLocalizedDescriptionKey:
                @"A vector is ( x, y, z ), joint( \"name\" ), bonecenter( \"a\", \"b\" ) or bonedir( \"a\", \"b\" )."}];
        }
        return NO;
    }
    if (([key isEqualToString:@"contents"] || [key isEqualToString:@"clipMask"]) && [*ioValue isKindOfClass:[NSString class]]) {
        *ioValue = [UDDeclAF ud_normalizedContents:*ioValue];
        return YES;
    }
    return [super validateValue:ioValue forKey:key error:error];
}

@end

@implementation UDAFConstraint

/// idDeclAF_Constraint::SetDefault, with @a file's settings and the bodies
/// read before it.
- (instancetype)initWithSettings:(NSDictionary<NSString *, id> *)file bodies:(NSArray<UDAFBody *> *)bodies {
    self = [super init];
    if (self) {
        _name = @"noname";
        _type = @"universalJoint";
        _body1 = bodies.count > 0 ? bodies.firstObject.name : @"world";
        _body2 = @"world";
        _friction = [file[@"defaultConstraintFriction"] floatValue];
        _anchor = @"( 0, 0, 0 )";
        _anchor2 = @"( 0, 0, 0 )";
        _axis = @"( 1, 0, 0 )";
        _shaft1 = @"( 0, 0, -1 )";
        _shaft2 = @"( 0, 0, 1 )";
        _limit = @"none";
        _limitAxis = @"( 0, 0, -1 )";
    }
    return self;
}

- (instancetype)init {
    return [self initWithSettings:[UDDeclAF ud_defaultSettings] bodies:@[]];
}

- (BOOL)validateValue:(id *)ioValue forKey:(NSString *)key error:(NSError **)error {
    if ([@[@"anchor", @"anchor2", @"shaft1", @"shaft2", @"axis", @"limitAxis"] containsObject:key]) {
        NSString *vector = [*ioValue isKindOfClass:[NSString class]] ? [UDDeclAF ud_normalizedVector:*ioValue] : nil;
        if (vector != nil) {
            *ioValue = vector;
            return YES;
        }
        if (error != NULL) {
            *error = [NSError errorWithDomain:@"UDAFConstraint" code:1 userInfo:@{NSLocalizedDescriptionKey:
                @"A vector is ( x, y, z ), joint( \"name\" ), bonecenter( \"a\", \"b\" ) or bonedir( \"a\", \"b\" )."}];
        }
        return NO;
    }
    return [super validateValue:ioValue forKey:key error:error];
}

@end

#pragma mark - Parsing (idDeclAF::Parse and its parsers)

/// The body's or constraint's name and its "{": NO where the engine's
/// ExpectTokenType( TT_STRING ) or ExpectTokenString( "{" ) fail.
static BOOL UDAFParseNameAndBrace(idLexer *src, NSString **name) {
    idToken token;
    idToken_Init(&token);
    if ( ![src expectTokenType:TT_STRING subtype:0 into:&token error:NULL] ||
         ![src expectTokenString:@"{" error:NULL] ) {
        return NO;
    }
    *name = UDTokenString( &token );
    return YES;
}

static NSString *UDAFParseString(idLexer *src) {
    idToken token;
    idToken_Init(&token);
    [src expectTokenType:TT_STRING subtype:0 into:&token error:NULL];
    return UDTokenString( &token );
}

static float UDAFParseFloat(idLexer *src) {
    float f = 0.0f;
    [src parseFloat:&f error:NULL];
    return f;
}

/// idDeclAF::ParseBody: the body is the figure's from the start, as
/// bodies.Alloc() makes it.
static BOOL UDAFParseBody(idLexer *src, NSDictionary *settings, NSMutableArray<UDAFBody *> *bodies) {
    BOOL hasJoint = NO;
    idToken token;
    idToken_Init(&token);
    UDAFBody *body = [[UDAFBody alloc] initWithSettings:settings];
    [bodies addObject:body];
    BOOL hasModel = NO;

    NSString *name = nil;
    if ( !UDAFParseNameAndBrace( src, &name ) ) {
        return NO;
    }
    body.name = name;
    if ( ![name caseInsensitiveCompare:@"origin"] || ![name caseInsensitiveCompare:@"world"] ) {
        [src error:NULL format:@"a body may not be named \"origin\" or \"world\""];
        return NO;
    }
    while ( [src readToken:&token error:NULL] ) {
        if ( !strcasecmp( token.text, "model" ) ) {
            if ( ![src expectTokenType:TT_NAME subtype:0 into:&token error:NULL] ) {
                return NO;
            }
            NSString *type = UDTokenString( &token ).lowercaseString;
            if ( [@[@"box", @"octahedron", @"dodecahedron", @"cylinder", @"cone", @"bone"] containsObject:type] ) {
                NSString *v1 = nil, *v2 = nil;
                if ( ![src expectTokenString:@"(" error:NULL] ||
                     !UDAFParseVector( src, &v1 ) ||
                     ![src expectTokenString:@"," error:NULL] ||
                     !UDAFParseVector( src, &v2 ) ) {
                    return NO;
                }
                body.modelType = type;
                body.v1 = v1;
                body.v2 = v2;
                if ( [type isEqualToString:@"cylinder"] || [type isEqualToString:@"cone"] ) {
                    if ( ![src expectTokenString:@"," error:NULL] ) return NO;
                    int sides = 0;
                    [src parseInt:&sides error:NULL];
                    body.numSides = sides;
                } else if ( [type isEqualToString:@"bone"] ) {
                    if ( ![src expectTokenString:@"," error:NULL] ) return NO;
                    body.width = UDAFParseFloat( src );
                }
                if ( ![src expectTokenString:@")" error:NULL] ) {
                    return NO;
                }
                hasModel = YES;
            } else if ( [type isEqualToString:@"custom"] ) {
                [src error:NULL format:@"custom models not yet implemented"];
                return NO;
            } else {
                [src error:NULL format:@"unknown model type %s", token.text];
                return NO;
            }
        } else if ( !strcasecmp( token.text, "origin" ) ) {
            NSString *origin = nil;
            if ( !UDAFParseVector( src, &origin ) ) return NO;
            body.origin = origin;
        } else if ( !strcasecmp( token.text, "angles" ) ) {
            NSString *angles = nil;
            if ( !UDAFParseVector( src, &angles ) ) return NO;
            body.angles = angles;
        } else if ( !strcasecmp( token.text, "joint" ) ) {
            if ( ![src expectTokenType:TT_STRING subtype:0 into:&token error:NULL] ) return NO;
            body.jointName = UDTokenString( &token );
            hasJoint = YES;
        } else if ( !strcasecmp( token.text, "mod" ) ) {
            if ( ![src expectAnyToken:&token error:NULL] ) return NO;
            // JointModFromString: orientation (and anything else), position, both.
            NSString *mod = UDTokenString( &token ).lowercaseString;
            body.jointMod = [@[@"position", @"both"] containsObject:mod] ? mod : @"orientation";
        } else if ( !strcasecmp( token.text, "density" ) ) {
            body.density = UDAFParseFloat( src );
        } else if ( !strcasecmp( token.text, "inertiaScale" ) ) {
            float m[9] = { 0 };
            [src parse1DMatrix:9 matrix:m error:NULL];
            body.inertiaScale = [NSString stringWithFormat:@"%g %g %g %g %g %g %g %g %g",
                                 m[0], m[1], m[2], m[3], m[4], m[5], m[6], m[7], m[8]];
        } else if ( !strcasecmp( token.text, "friction" ) ) {
            body.linearFriction = UDAFParseFloat( src );
            [src expectTokenString:@"," error:NULL];
            body.angularFriction = UDAFParseFloat( src );
            [src expectTokenString:@"," error:NULL];
            body.contactFriction = UDAFParseFloat( src );
        } else if ( !strcasecmp( token.text, "contents" ) ) {
            body.contents = UDAFParseContents( src );
        } else if ( !strcasecmp( token.text, "clipMask" ) ) {
            body.clipMask = UDAFParseContents( src );
        } else if ( !strcasecmp( token.text, "selfCollision" ) ) {
            BOOL b = NO;
            [src parseBool:&b error:NULL];
            body.selfCollision = b;
        } else if ( !strcasecmp( token.text, "containedjoints" ) ) {
            if ( ![src expectTokenType:TT_STRING subtype:0 into:&token error:NULL] ) return NO;
            body.containedJoints = UDTokenString( &token );
        } else if ( !strcasecmp( token.text, "frictionDirection" ) ) {
            NSString *vector = nil;
            if ( !UDAFParseVector( src, &vector ) ) return NO;
            body.frictionDirection = vector;
        } else if ( !strcasecmp( token.text, "contactMotorDirection" ) ) {
            NSString *vector = nil;
            if ( !UDAFParseVector( src, &vector ) ) return NO;
            body.contactMotorDirection = vector;
        } else if ( !strcmp( token.text, "}" ) ) {
            break;
        } else {
            [src error:NULL format:@"unknown token %s in body", token.text];
            return NO;
        }
    }
    // SetDefault gives a box: TRM_INVALID's "no model set for body" is
    // never met.
    (void)hasModel;
    if ( !hasJoint ) {
        [src error:NULL format:@"no joint set for body"];
        return NO;
    }
    // body->clipMask |= CONTENTS_MOVEABLECLIP: not one ContentsToString names.
    return YES;
}

/// The parsers of the constraints: their keywords, their defaults past
/// SetDefault's, the keywords they read.
static BOOL UDAFParseConstraint(idLexer *src, NSString *type, NSDictionary *settings,
                                NSArray<UDAFBody *> *bodies, NSMutableArray<UDAFConstraint *> *constraints) {
    idToken token;
    idToken_Init(&token);
    UDAFConstraint *constraint = [[UDAFConstraint alloc] initWithSettings:settings bodies:bodies];
    [constraints addObject:constraint];

    NSString *name = nil;
    if ( !UDAFParseNameAndBrace( src, &name ) ) {
        return NO;
    }
    constraint.type = type;
    constraint.name = name;
    BOOL fixed = [type isEqualToString:@"fixed"];
    if ( !fixed ) {
        constraint.limit = @"none";
        constraint.friction = 0.5f;
    }
    if ( [type isEqualToString:@"ballAndSocketJoint"] ) {
        constraint.anchor = @"( 0, 0, 0 )";
        constraint.shaft1 = @"( 0, 0, 0 )";
    } else if ( [type isEqualToString:@"universalJoint"] ) {
        constraint.anchor = @"( 0, 0, 0 )";
        constraint.shaft1 = @"( 0, 0, 0 )";
        constraint.shaft2 = @"( 0, 0, 0 )";
    } else if ( [type isEqualToString:@"hinge"] ) {
        constraint.anchor = @"( 0, 0, 0 )";
        constraint.axis = @"( 0, 0, 0 )";
    }
    // The engine's message for an unknown token, each parser's (ParseFixed's says ball and socket joint).
    NSDictionary *what = @{ @"fixed": @"ball and socket joint", @"ballAndSocketJoint": @"ball and socket joint",
                            @"universalJoint": @"universal joint", @"hinge": @"hinge", @"slider": @"slider", @"spring": @"spring" };

    while ( [src readToken:&token error:NULL] ) {
        NSString *vector = nil;
        if ( !strcasecmp( token.text, "body1" ) ) {
            constraint.body1 = UDAFParseString( src );
        } else if ( !strcasecmp( token.text, "body2" ) ) {
            constraint.body2 = UDAFParseString( src );
        } else if ( !strcmp( token.text, "}" ) ) {
            break;
        } else if ( !fixed && !strcasecmp( token.text, "friction" ) ) {
            constraint.friction = UDAFParseFloat( src );
        } else if ( ([type isEqualToString:@"ballAndSocketJoint"] || [type isEqualToString:@"universalJoint"] ||
                     [type isEqualToString:@"hinge"]) && !strcasecmp( token.text, "anchor" ) ) {
            if ( !UDAFParseVector( src, &vector ) ) return NO;
            constraint.anchor = vector;
        } else if ( [type isEqualToString:@"universalJoint"] && !strcasecmp( token.text, "shafts" ) ) {
            NSString *second = nil;
            if ( !UDAFParseVector( src, &vector ) || ![src expectTokenString:@"," error:NULL] ||
                 !UDAFParseVector( src, &second ) ) {
                return NO;
            }
            constraint.shaft1 = vector;
            constraint.shaft2 = second;
        } else if ( ([type isEqualToString:@"ballAndSocketJoint"] || [type isEqualToString:@"universalJoint"]) &&
                    (!strcasecmp( token.text, "conelimit" ) || !strcasecmp( token.text, "pyramidlimit" )) ) {
            BOOL pyramid = !strcasecmp( token.text, "pyramidlimit" );
            if ( !UDAFParseVector( src, &vector ) || ![src expectTokenString:@"," error:NULL] ) {
                return NO;
            }
            constraint.limitAxis = vector;
            constraint.limitAngle1 = UDAFParseFloat( src );
            if ( pyramid ) {
                if ( ![src expectTokenString:@"," error:NULL] ) return NO;
                constraint.limitAngle2 = UDAFParseFloat( src );
                if ( ![src expectTokenString:@"," error:NULL] ) return NO;
                constraint.limitAngle3 = UDAFParseFloat( src );
            }
            if ( [type isEqualToString:@"ballAndSocketJoint"] ) {
                if ( ![src expectTokenString:@"," error:NULL] || !UDAFParseVector( src, &vector ) ) {
                    return NO;
                }
                constraint.shaft1 = vector;
            }
            constraint.limit = pyramid ? @"pyramid" : @"cone";
        } else if ( ([type isEqualToString:@"hinge"] || [type isEqualToString:@"slider"]) && !strcasecmp( token.text, "axis" ) ) {
            if ( !UDAFParseVector( src, &vector ) ) return NO;
            constraint.axis = vector;
        } else if ( [type isEqualToString:@"hinge"] && !strcasecmp( token.text, "limit" ) ) {
            constraint.limitAngle1 = UDAFParseFloat( src );
            if ( ![src expectTokenString:@"," error:NULL] ) return NO;
            constraint.limitAngle2 = UDAFParseFloat( src );
            if ( ![src expectTokenString:@"," error:NULL] ) return NO;
            constraint.limitAngle3 = UDAFParseFloat( src );
            constraint.limit = @"cone";
        } else if ( [type isEqualToString:@"spring"] && (!strcasecmp( token.text, "anchor1" ) || !strcasecmp( token.text, "anchor2" )) ) {
            BOOL second = !strcasecmp( token.text, "anchor2" );
            if ( !UDAFParseVector( src, &vector ) ) return NO;
            if ( second ) constraint.anchor2 = vector; else constraint.anchor = vector;
        } else if ( [type isEqualToString:@"spring"] &&
                    [@[@"stretch", @"compress", @"damping", @"restlength", @"minlength", @"maxlength"]
                     containsObject:UDTokenString( &token ).lowercaseString] ) {
            NSDictionary *keys = @{ @"stretch": @"stretch", @"compress": @"compress", @"damping": @"damping",
                                    @"restlength": @"restLength", @"minlength": @"minLength", @"maxlength": @"maxLength" };
            [constraint setValue:@(UDAFParseFloat( src )) forKey:keys[UDTokenString( &token ).lowercaseString]];
        } else {
            [src error:NULL format:@"unknown token %s in %@", token.text, what[type]];
            return NO;
        }
    }
    return YES;
}

/// idDeclAF::ParseSettings, into @a settings.
static BOOL UDAFParseSettings(idLexer *src, NSMutableDictionary<NSString *, id> *settings) {
    idToken token;
    idToken_Init(&token);
    if ( ![src expectTokenString:@"{" error:NULL] ) {
        return NO;
    }
    while ( [src readToken:&token error:NULL] ) {
        if ( !strcasecmp( token.text, "mesh" ) || !strcasecmp( token.text, "anim" ) ) {
            if ( ![src expectTokenType:TT_STRING subtype:0 into:&token error:NULL] ) return NO;
        } else if ( !strcasecmp( token.text, "model" ) || !strcasecmp( token.text, "skin" ) ) {
            NSString *key = !strcasecmp( token.text, "model" ) ? @"model" : @"skin";
            if ( ![src expectTokenType:TT_STRING subtype:0 into:&token error:NULL] ) return NO;
            settings[key] = UDTokenString( &token );
        } else if ( !strcasecmp( token.text, "friction" ) ) {
            settings[@"defaultLinearFriction"] = @(UDAFParseFloat( src ));
            if ( ![src expectTokenString:@"," error:NULL] ) return NO;
            settings[@"defaultAngularFriction"] = @(UDAFParseFloat( src ));
            if ( ![src expectTokenString:@"," error:NULL] ) return NO;
            settings[@"defaultContactFriction"] = @(UDAFParseFloat( src ));
            if ( [src checkTokenString:@"," error:NULL] ) {
                settings[@"defaultConstraintFriction"] = @(UDAFParseFloat( src ));
            }
        } else if ( !strcasecmp( token.text, "suspendSpeed" ) ) {
            settings[@"suspendVelocity1"] = @(UDAFParseFloat( src ));
            if ( ![src expectTokenString:@"," error:NULL] ) return NO;
            settings[@"suspendVelocity2"] = @(UDAFParseFloat( src ));
            if ( ![src expectTokenString:@"," error:NULL] ) return NO;
            settings[@"suspendAcceleration1"] = @(UDAFParseFloat( src ));
            if ( ![src expectTokenString:@"," error:NULL] ) return NO;
            settings[@"suspendAcceleration2"] = @(UDAFParseFloat( src ));
        } else if ( !strcasecmp( token.text, "contents" ) || !strcasecmp( token.text, "clipMask" ) ) {
            NSString *key = !strcasecmp( token.text, "contents" ) ? @"contents" : @"clipMask";
            settings[key] = UDAFParseContents( src );
        } else if ( !strcasecmp( token.text, "selfCollision" ) ) {
            BOOL b = NO;
            [src parseBool:&b error:NULL];
            settings[@"selfCollision"] = @(b);
        } else if ( !strcmp( token.text, "}" ) ) {
            break;
        } else {
            BOOL matched = NO;
            for ( NSString *key in @[@"totalMass", @"noMoveTime", @"noMoveTranslation", @"noMoveRotation", @"minMoveTime", @"maxMoveTime"] ) {
                if ( !strcasecmp( token.text, key.UTF8String ) ) {
                    settings[key] = @(UDAFParseFloat( src ));
                    matched = YES;
                    break;
                }
            }
            if ( !matched ) {
                [src error:NULL format:@"unknown token %s in settings", token.text];
                return NO;
            }
        }
    }
    return YES;
}

@implementation UDDeclAF

@dynamic model, skin, defaultLinearFriction, defaultAngularFriction, defaultContactFriction, defaultConstraintFriction;
@dynamic totalMass, suspendVelocity1, suspendVelocity2, suspendAcceleration1, suspendAcceleration2;
@dynamic noMoveTime, noMoveTranslation, noMoveRotation, minMoveTime, maxMoveTime, contents, clipMask, selfCollision;
@dynamic bodies, constraints;

UD_ELEMENT_ARRAY_SETTER(setBodies, @"bodies")
UD_ELEMENT_ARRAY_SETTER(setConstraints, @"constraints")

// bodies and constraints are transient: read from the text here.
- (void)awakeFromFetch {
    [super awakeFromFetch];
    NSDictionary *parsed = UDParsedSourceText(self);
    for (NSString *key in @[@"bodies", @"constraints"]) {
        NSArray *elements = parsed[key] ?: @[];
        [self setPrimitiveValue:elements forKey:key];
        UDAdoptElements(elements, self, key);
    }
}

/// idDeclAF::FreeData's settings.
+ (NSDictionary<NSString *, id> *)ud_defaultSettings {
    return @{
        @"model": @"", @"skin": @"",
        @"defaultLinearFriction": @0.01f, @"defaultAngularFriction": @0.01f,
        @"defaultContactFriction": @0.8f, @"defaultConstraintFriction": @0.5f,
        @"totalMass": @-1.0f,
        @"suspendVelocity1": @20.0f, @"suspendVelocity2": @30.0f,
        @"suspendAcceleration1": @40.0f, @"suspendAcceleration2": @60.0f,
        @"noMoveTime": @1.0f, @"noMoveTranslation": @10.0f, @"noMoveRotation": @10.0f,
        @"minMoveTime": @-1.0f, @"maxMoveTime": @-1.0f,
        @"selfCollision": @YES,
        @"contents": @"corpse", @"clipMask": @"solid, corpse",
    };
}

+ (NSString *)ud_normalizedContents:(NSString *)text {
    return UDAFContentsToString( UDAFContentsFromString( text ) );
}

+ (NSString *)ud_normalizedVector:(NSString *)text {
    idLexer *src = UDAFLexer(text ?: @"");
    NSString *vector = nil;
    idToken token;
    idToken_Init(&token);
    if ( src == nil || !UDAFParseVector( src, &vector ) || [src readToken:&token error:NULL] ) {
        return nil;                                                  // none, or more than one
    }
    return vector;
}

- (BOOL)validateContents:(id *)ioValue error:(NSError **)error {
    *ioValue = [UDDeclAF ud_normalizedContents:[*ioValue description] ?: @""];
    return YES;
}

- (BOOL)validateClipMask:(id *)ioValue error:(NSError **)error {
    return [self validateContents:ioValue error:error];
}

// idDeclAF::DefaultDefinition
+ (NSString *)ud_defaultDefinition {
    return
        @"{\n"
        @"\t"    @"settings {\n"
        @"\t\t"        @"model \"\"\n"
        @"\t\t"        @"skin \"\"\n"
        @"\t\t"        @"friction 0.01, 0.01, 0.8, 0.5\n"
        @"\t\t"        @"suspendSpeed 20, 30, 40, 60\n"
        @"\t\t"        @"noMoveTime 1\n"
        @"\t\t"        @"noMoveTranslation 10\n"
        @"\t\t"        @"noMoveRotation 10\n"
        @"\t\t"        @"minMoveTime -1\n"
        @"\t\t"        @"maxMoveTime -1\n"
        @"\t\t"        @"totalMass -1\n"
        @"\t\t"        @"contents corpse\n"
        @"\t\t"        @"clipMask solid, corpse\n"
        @"\t\t"        @"selfCollision 1\n"
        @"\t"    @"}\n"
        @"\t"    @"body \"body\" {\n"
        @"\t\t"        @"joint \"origin\"\n"
        @"\t\t"        @"mod orientation\n"
        @"\t\t"        @"model box( ( -10, -10, -10 ), ( 10, 10, 10 ) )\n"
        @"\t\t"        @"origin ( 0, 0, 0 )\n"
        @"\t\t"        @"density 0.2\n"
        @"\t\t"        @"friction 0.01, 0.01, 0.8\n"
        @"\t\t"        @"contents corpse\n"
        @"\t\t"        @"clipMask solid, corpse\n"
        @"\t\t"        @"selfCollision 1\n"
        @"\t\t"        @"containedJoints \"*origin\"\n"
        @"\t"    @"}\n"
        @"}\n";
}

// A port of idDeclAF::Parse. Where a parser returns false the figure keeps
// what was read: idDeclLocal::ParseLocal makes no default of it.
+ (NSDictionary<NSString *, id> *)ud_parseValuesFromText:(NSData *)text
                                                    name:(NSString *)name
                                                fileName:(NSString *)fileName
                                                 lineNum:(int)lineNum
                                              fileSystem:(idFileSystem *)fileSystem
                                                   error:(NSError **)error {
    idLexer *src = UDDeclCodecLexer(text, name, fileName, lineNum, fileSystem, error);
    if (src == nil) {
        return nil;
    }
    idToken token;
    idToken_Init(&token);
    NSMutableDictionary<NSString *, id> *settings = [[self ud_defaultSettings] mutableCopy];
    NSMutableArray<UDAFBody *> *bodies = [NSMutableArray array];
    NSMutableArray<UDAFConstraint *> *constraints = [NSMutableArray array];
    NSDictionary *constraintKeywords = @{ @"fixed": @"fixed", @"ballandsocketjoint": @"ballAndSocketJoint",
                                          @"universaljoint": @"universalJoint", @"hinge": @"hinge",
                                          @"slider": @"slider", @"spring": @"spring" };

    BOOL read = YES;
    while ( read && [src readToken:&token error:NULL] ) {
        NSString *keyword = UDTokenString( &token ).lowercaseString;
        if ( [keyword isEqualToString:@"settings"] ) {
            read = UDAFParseSettings( src, settings );
        } else if ( [keyword isEqualToString:@"body"] ) {
            read = UDAFParseBody( src, settings, bodies );
        } else if ( constraintKeywords[keyword] != nil ) {
            read = UDAFParseConstraint( src, constraintKeywords[keyword], settings, bodies, constraints );
        } else if ( !strcmp( token.text, "}" ) ) {
            break;
        } else {
            [src error:NULL format:@"unknown keyword %s", token.text];
            read = NO;
        }
    }

    if ( read ) {
        for ( NSUInteger i = 0; i < bodies.count; i++ ) {
            // check for multiple bodies with the same name
            for ( NSUInteger j = i + 1; j < bodies.count; j++ ) {
                if ( [bodies[i].name isEqualToString:bodies[j].name] ) {
                    [src error:NULL format:@"two bodies with the same name \"%@\"", bodies[i].name];
                }
            }
        }
        for ( NSUInteger i = 0; i < constraints.count; i++ ) {
            // check for multiple constraints with the same name
            for ( NSUInteger j = i + 1; j < constraints.count; j++ ) {
                if ( [constraints[i].name isEqualToString:constraints[j].name] ) {
                    [src error:NULL format:@"two constraints with the same name \"%@\"", constraints[i].name];
                }
            }
            // check if there are two valid bodies set
            if ( constraints[i].body1.length == 0 ) {
                [src error:NULL format:@"no valid body1 specified for constraint '%@'", constraints[i].name];
            }
            if ( constraints[i].body2.length == 0 ) {
                [src error:NULL format:@"no valid body2 specified for constraint '%@'", constraints[i].name];
            }
        }
        // make sure the body which modifies the origin comes first
        for ( NSUInteger i = 0; i < bodies.count; i++ ) {
            if ( [bodies[i].jointName isEqualToString:@"origin"] ) {
                if ( i != 0 ) {
                    [bodies exchangeObjectAtIndex:0 withObjectAtIndex:i];
                }
                break;
            }
        }
    }

    NSMutableDictionary<NSString *, id> *values = settings;
    values[@"bodies"] = bodies;
    values[@"constraints"] = constraints;
    return values;
}

#pragma mark - Writing (idDeclAF::RebuildTextSource)

static void UDAFWriteBody(NSMutableString *f, UDAFBody *body) {
    [f appendFormat:@"\nbody \"%@\" {\n", body.name];
    [f appendFormat:@"\tjoint \"%@\"\n", body.jointName];
    [f appendFormat:@"\tmod %@\n", body.jointMod];
    NSString *type = body.modelType;
    [f appendFormat:@"\tmodel %@( %@, %@", type, UDAFWriteVector( body.v1 ), UDAFWriteVector( body.v2 )];
    if ( [type isEqualToString:@"cylinder"] || [type isEqualToString:@"cone"] ) {
        [f appendFormat:@", %d", body.numSides];
    } else if ( [type isEqualToString:@"bone"] ) {
        [f appendFormat:@", %f", body.width];
    }
    [f appendString:@" )\n"];
    [f appendFormat:@"\torigin %@\n", UDAFWriteVector( body.origin )];
    if ( !UDAFVectorIsZero( body.angles ) ) {
        // angles ( %f, %f, %f ): its pitch, yaw and roll
        [f appendFormat:@"\tangles %@\n", UDAFWriteVector( body.angles )];
    }
    [f appendFormat:@"\tdensity %f\n", body.density];
    NSArray<NSString *> *ic = [[body.inertiaScale componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceCharacterSet]]
                               filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"length > 0"]];
    BOOL identity = ic.count == 9;
    for ( NSUInteger i = 0; identity && i < 9; i++ ) {
        identity = ic[i].floatValue == ((i % 4 == 0) ? 1.0f : 0.0f);
    }
    if ( !identity && ic.count == 9 ) {
        [f appendFormat:@"\tinertiaScale (%f %f %f %f %f %f %f %f %f)\n",
                        ic[0].floatValue, ic[1].floatValue, ic[2].floatValue, ic[3].floatValue, ic[4].floatValue,
                        ic[5].floatValue, ic[6].floatValue, ic[7].floatValue, ic[8].floatValue];
    }
    if ( body.linearFriction != -1 ) {
        [f appendFormat:@"\tfriction %f, %f, %f\n", body.linearFriction, body.angularFriction, body.contactFriction];
    }
    [f appendFormat:@"\tcontents %@\n", UDAFContentsToString( UDAFContentsFromString( body.contents ) )];
    [f appendFormat:@"\tclipMask %@\n", UDAFContentsToString( UDAFContentsFromString( body.clipMask ) )];
    [f appendFormat:@"\tselfCollision %d\n", body.selfCollision ? 1 : 0];
    if ( !UDAFVectorIsZero( body.frictionDirection ) ) {
        [f appendFormat:@"\tfrictionDirection %@\n", UDAFWriteVector( body.frictionDirection )];
    }
    if ( !UDAFVectorIsZero( body.contactMotorDirection ) ) {
        [f appendFormat:@"\tcontactMotorDirection %@\n", UDAFWriteVector( body.contactMotorDirection )];
    }
    [f appendFormat:@"\tcontainedJoints \"%@\"\n", body.containedJoints];
    [f appendString:@"}\n"];
}

static void UDAFWriteConstraint(NSMutableString *f, UDAFConstraint *c) {
    NSString *type = c.type;
    if ( ![@[@"fixed", @"ballAndSocketJoint", @"universalJoint", @"hinge", @"slider", @"spring"] containsObject:type] ) {
        return;                                                     // WriteConstraint's default
    }
    [f appendFormat:@"\n%@ \"%@\" {\n", type, c.name];
    [f appendFormat:@"\tbody1 \"%@\"\n", c.body1];
    [f appendFormat:@"\tbody2 \"%@\"\n", c.body2];
    if ( [type isEqualToString:@"fixed"] ) {
        [f appendString:@"}\n"];
        return;
    }
    if ( [type isEqualToString:@"spring"] ) {
        [f appendFormat:@"\tanchor1 %@\n", UDAFWriteVector( c.anchor )];
        [f appendFormat:@"\tanchor2 %@\n", UDAFWriteVector( c.anchor2 )];
        [f appendFormat:@"\tfriction %f\n", c.friction];
        [f appendFormat:@"\tstretch %f\n", c.stretch];
        [f appendFormat:@"\tcompress %f\n", c.compress];
        [f appendFormat:@"\tdamping %f\n", c.damping];
        [f appendFormat:@"\trestLength %f\n", c.restLength];
        [f appendFormat:@"\tminLength %f\n", c.minLength];
        [f appendFormat:@"\tmaxLength %f\n", c.maxLength];
        [f appendString:@"}\n"];
        return;
    }
    if ( ![type isEqualToString:@"slider"] ) {
        [f appendFormat:@"\tanchor %@\n", UDAFWriteVector( c.anchor )];
    }
    if ( [type isEqualToString:@"universalJoint"] ) {
        [f appendFormat:@"\tshafts %@, %@\n", UDAFWriteVector( c.shaft1 ), UDAFWriteVector( c.shaft2 )];
    }
    if ( [type isEqualToString:@"hinge"] || [type isEqualToString:@"slider"] ) {
        [f appendFormat:@"\taxis %@\n", UDAFWriteVector( c.axis )];
    }
    [f appendFormat:@"\tfriction %f\n", c.friction];
    if ( [type isEqualToString:@"hinge"] ) {
        if ( [c.limit isEqualToString:@"cone"] ) {
            [f appendFormat:@"\tlimit %f, %f, %f\n", c.limitAngle1, c.limitAngle2, c.limitAngle3];
        }
    } else if ( [type isEqualToString:@"ballAndSocketJoint"] || [type isEqualToString:@"universalJoint"] ) {
        BOOL ball = [type isEqualToString:@"ballAndSocketJoint"];
        if ( [c.limit isEqualToString:@"cone"] ) {
            [f appendFormat:@"\tconeLimit %@, %f", UDAFWriteVector( c.limitAxis ), c.limitAngle1];
            if ( ball ) [f appendFormat:@", %@", UDAFWriteVector( c.shaft1 )];
            [f appendString:@"\n"];
        } else if ( [c.limit isEqualToString:@"pyramid"] ) {
            [f appendFormat:@"\tpyramidLimit %@, %f, %f, %f", UDAFWriteVector( c.limitAxis ), c.limitAngle1, c.limitAngle2, c.limitAngle3];
            if ( ball ) [f appendFormat:@", %@", UDAFWriteVector( c.shaft1 )];
            [f appendString:@"\n"];
        }
    }
    [f appendString:@"}\n"];
}

// RebuildTextSource's text (less its "Generated by the Articulated Figure
// Editor" banner): WriteSettings, WriteBody and WriteConstraint.
+ (NSData *)ud_textByUnparsingName:(NSString *)name
                            values:(NSDictionary<NSString *, id> *)values
                             error:(NSError **)error {
    NSMutableString *f = [NSMutableString stringWithFormat:@"articulatedFigure %@ {\n", name];
    [f appendString:@"\nsettings {\n"];
    [f appendFormat:@"\tmodel \"%@\"\n", values[@"model"] ?: @""];
    [f appendFormat:@"\tskin \"%@\"\n", values[@"skin"] ?: @""];
    [f appendFormat:@"\tfriction %f, %f, %f, %f\n", UDFloatValue(values, @"defaultLinearFriction"), UDFloatValue(values, @"defaultAngularFriction"),
                    UDFloatValue(values, @"defaultContactFriction"), UDFloatValue(values, @"defaultConstraintFriction")];
    [f appendFormat:@"\tsuspendSpeed %f, %f, %f, %f\n", UDFloatValue(values, @"suspendVelocity1"), UDFloatValue(values, @"suspendVelocity2"),
                    UDFloatValue(values, @"suspendAcceleration1"), UDFloatValue(values, @"suspendAcceleration2")];
    [f appendFormat:@"\tnoMoveTime %f\n", UDFloatValue(values, @"noMoveTime")];
    [f appendFormat:@"\tnoMoveTranslation %f\n", UDFloatValue(values, @"noMoveTranslation")];
    [f appendFormat:@"\tnoMoveRotation %f\n", UDFloatValue(values, @"noMoveRotation")];
    [f appendFormat:@"\tminMoveTime %f\n", UDFloatValue(values, @"minMoveTime")];
    [f appendFormat:@"\tmaxMoveTime %f\n", UDFloatValue(values, @"maxMoveTime")];
    [f appendFormat:@"\ttotalMass %f\n", UDFloatValue(values, @"totalMass")];
    [f appendFormat:@"\tcontents %@\n", UDAFContentsToString( UDAFContentsFromString( values[@"contents"] ) )];
    [f appendFormat:@"\tclipMask %@\n", UDAFContentsToString( UDAFContentsFromString( values[@"clipMask"] ) )];
    [f appendFormat:@"\tselfCollision %d\n", UDBoolValue(values, @"selfCollision") ? 1 : 0];
    [f appendString:@"}\n"];
    for (UDAFBody *body in values[@"bodies"]) {
        UDAFWriteBody(f, body);
    }
    for (UDAFConstraint *constraint in values[@"constraints"]) {
        UDAFWriteConstraint(f, constraint);
    }
    [f appendString:@"\n}"];
    return [f dataUsingEncoding:NSUTF8StringEncoding];
}

@end
