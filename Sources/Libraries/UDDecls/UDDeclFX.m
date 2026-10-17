/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 * UDDeclFX.m — FX (idDeclFX).
 */

#import "UDDeclManagedObjects.h"
#import "UDDeclFX.h"
#import <objc/runtime.h>

#import "UDDeclCodec.h"
#import "UDDeclIncrementalStore.h"
#import "UDDeclTextChecker.h"
#import "idLexer.h"
#import "idToken.h"
#import "idStr.h"

#pragma mark - FX

@implementation UDFXAction

+ (NSSet<NSString *> *)ud_numberKeys {
    return [NSSet setWithArray:@[@"delay", @"duration", @"restart", @"size", @"fadeIn", @"fadeOut", @"rotate",
                                 @"random1", @"random2", @"lightRadius", @"shakeTime", @"shakeAmplitude",
                                 @"shakeDistance", @"shakeImpulse"]];
}

@end

/// The numbers of a "x, y, z" (ParseFloat and ExpectTokenString( "," ) in
/// turn), as a value's "x y z".
static NSString *UDFXParseCommaFloats(idLexer *src, int count) {
    NSMutableArray<NSString *> *values = [NSMutableArray array];
    for (int i = 0; i < count; i++) {
        if (i > 0) [src expectTokenString:@"," error:NULL];
        float f = 0.0f;
        [src parseFloat:&f error:NULL];
        [values addObject:[NSString stringWithFormat:@"%g", f]];
    }
    return [values componentsJoinedByString:@" "];
}

static NSNumber *UDFXParseFloat(idLexer *src) {
    float f = 0.0f;
    [src parseFloat:&f error:NULL];
    return @(f);
}

// A port of idDeclFX::ParseSingleFXAction (neo/framework/DeclFX.cpp),
// keeping the keywords' values as written rather than the game's (an axis
// normalized into a matrix, a sibling found by name, the media precached).
static UDFXAction *UDFXParseSingleAction(idLexer *src) {
    idToken token;
    idToken_Init(&token);
    UDFXAction *action = [[UDFXAction alloc] init];

    while (1) {
        if ( ![src readToken:&token error:NULL] ) {
            break;
        }
        if ( !strcasecmp( token.text, "}" ) ) {
            break;
        }
        if ( !strcasecmp( token.text, "shake" ) ) {
            action.kind = @"shake";
            action.shakeTime = UDFXParseFloat( src );
            [src expectTokenString:@"," error:NULL];
            action.shakeAmplitude = UDFXParseFloat( src );
            [src expectTokenString:@"," error:NULL];
            action.shakeDistance = UDFXParseFloat( src );
            [src expectTokenString:@"," error:NULL];
            BOOL falloff = NO;
            [src parseBool:&falloff error:NULL];
            action.shakeFalloff = falloff;
            [src expectTokenString:@"," error:NULL];
            action.shakeImpulse = UDFXParseFloat( src );
            continue;
        }
        if ( !strcasecmp( token.text, "noshadows" ) ) {
            action.noshadows = YES;
            continue;
        }
        if ( !strcasecmp( token.text, "name" ) ) {
            [src readToken:&token error:NULL];
            action.name = UDTokenString( &token );
            continue;
        }
        if ( !strcasecmp( token.text, "fire" ) ) {
            [src readToken:&token error:NULL];
            action.fire = UDTokenString( &token );
            continue;
        }
        if ( !strcasecmp( token.text, "random" ) ) {
            action.random1 = UDFXParseFloat( src );
            [src expectTokenString:@"," error:NULL];
            action.random2 = UDFXParseFloat( src );
            action.delay = nil;                                     // check random
            continue;
        }
        static const struct { const char *keyword; const char *key; } floats[] = {
            { "delay", "delay" }, { "rotate", "rotate" }, { "duration", "duration" }, { "restart", "restart" },
            { "fadeIn", "fadeIn" }, { "fadeOut", "fadeOut" }, { "size", "size" },
        };
        BOOL matched = NO;
        for ( size_t i = 0; i < sizeof( floats ) / sizeof( floats[0] ); i++ ) {
            if ( !strcasecmp( token.text, floats[i].keyword ) ) {
                [action setValue:UDFXParseFloat( src ) forKey:[NSString stringWithUTF8String:floats[i].key]];
                matched = YES;
                break;
            }
        }
        if ( matched ) {
            continue;
        }
        if ( !strcasecmp( token.text, "trackorigin" ) ) {
            BOOL b = NO;
            [src parseBool:&b error:NULL];
            action.trackOrigin = b;
            continue;
        }
        if ( !strcasecmp( token.text, "offset" ) ) {
            action.offset = UDFXParseCommaFloats( src, 3 );
            continue;
        }
        if ( !strcasecmp( token.text, "axis" ) ) {
            action.axis = UDFXParseCommaFloats( src, 3 );
            continue;
        }
        if ( !strcasecmp( token.text, "angle" ) ) {
            action.angle = UDFXParseCommaFloats( src, 3 );
            continue;
        }
        if ( !strcasecmp( token.text, "light" ) ) {
            [src readToken:&token error:NULL];
            action.data = UDTokenString( &token );
            [src expectTokenString:@"," error:NULL];
            action.lightColor = UDFXParseCommaFloats( src, 3 );
            [src expectTokenString:@"," error:NULL];
            action.lightRadius = UDFXParseFloat( src );
            action.kind = @"light";
            continue;
        }
        // The keywords that name what the action uses, and are its kind.
        static const char *const named[] = {
            "uselight", "attachlight", "attachentity", "launch", "useModel", "model", "particle", "decal", "sound", "shockwave",
        };
        for ( size_t i = 0; i < sizeof( named ) / sizeof( named[0] ); i++ ) {
            if ( !strcasecmp( token.text, named[i] ) ) {
                NSString *kind = [NSString stringWithUTF8String:named[i]].lowercaseString;
                [src readToken:&token error:NULL];
                action.data = UDTokenString( &token );
                action.kind = kind;
                matched = YES;
                break;
            }
        }
        if ( matched ) {
            continue;
        }
        if ( !strcasecmp( token.text, "particleTrackVelocity" ) ) {
            action.particleTrackVelocity = YES;
            continue;
        }
        if ( !strcasecmp( token.text, "ignoreMaster" ) ) {
            action.ignoreMaster = YES;
            continue;
        }
        [src warning:@"FX File: bad token"];
        continue;
    }
    return action;
}

@implementation UDDeclFX

@dynamic bindTo, actions;

UD_ELEMENT_ARRAY_SETTER(setActions, @"actions")

// actions is transient: read from the text here.
- (void)awakeFromFetch {
    [super awakeFromFetch];
    NSArray *actions = UDParsedSourceText(self)[@"actions"] ?: @[];
    [self setPrimitiveValue:actions forKey:@"actions"];
    UDAdoptElements(actions, self, @"actions");
}

// idDeclFX::DefaultDefinition
+ (NSString *)ud_defaultDefinition {
    return
        @"{\n"
        @"\t"    @"{\n"
        @"\t\t"        @"duration\t5\n"
        @"\t\t"        @"model\t\t_default\n"
        @"\t"    @"}\n"
        @"}";
}

// A port of idDeclFX::Parse. A parse error is warned about and the actions
// read are kept: idDeclLocal::ParseLocal makes no default of an FX that
// failed.
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
    NSMutableDictionary<NSString *, id> *values = [NSMutableDictionary dictionary];
    NSMutableArray<UDFXAction *> *actions = [NSMutableArray array];

    // scan through, identifying each individual parameter
    while( 1 ) {
        if ( ![src readToken:&token error:NULL] ) {
            break;
        }
        if ( !strcmp( token.text, "}" ) ) {
            break;
        }
        if ( !strcasecmp( token.text, "bindto" ) ) {
            [src readToken:&token error:NULL];
            values[@"bindTo"] = UDTokenString( &token );
            continue;
        }
        if ( !strcasecmp( token.text, "{" ) ) {
            [actions addObject:UDFXParseSingleAction( src )];
            continue;
        }
    }
    if ( [src hadError] ) {
        [src warning:@"FX decl '%@' had a parse error", name];
    }
    values[@"actions"] = actions;
    return values;
}

static void UDFXWriteNumber(NSMutableString *out, NSString *keyword, NSNumber *value) {
    if (value != nil) [out appendFormat:@"\t\t%@ %g\n", keyword, value.doubleValue];
}

/// A value's "x y z" as the decl's "x, y, z".
static NSString *UDFXCommaList(NSString *spaced) {
    NSArray<NSString *> *numbers = [[spaced componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceCharacterSet]]
                                    filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"length > 0"]];
    return numbers.count > 0 ? [numbers componentsJoinedByString:@", "] : @"0, 0, 0";
}

// What ParseSingleFXAction reads, a keyword a line, as the retail .fx files
// have them: the timing, what the action does, then its other keywords.
+ (NSData *)ud_textByUnparsingName:(NSString *)name
                            values:(NSDictionary<NSString *, id> *)values
                             error:(NSError **)error {
    NSMutableString *out = [NSMutableString stringWithFormat:@"fx %@\n{\n", name];
    NSString *bindTo = values[@"bindTo"];
    if (bindTo.length > 0) [out appendFormat:@"\tbindto \"%@\"\n", bindTo];
    for (UDFXAction *action in values[@"actions"]) {
        [out appendString:@"\t{\n"];
        if (action.name.length > 0) [out appendFormat:@"\t\tname \"%@\"\n", action.name];
        UDFXWriteNumber(out, @"delay", action.delay);
        if (action.random1 != nil || action.random2 != nil) {
            [out appendFormat:@"\t\trandom %g, %g\n", action.random1.doubleValue, action.random2.doubleValue];
        }
        UDFXWriteNumber(out, @"duration", action.duration);
        UDFXWriteNumber(out, @"restart", action.restart);
        NSString *kind = action.kind;
        if ([kind isEqualToString:@"light"]) {
            [out appendFormat:@"\t\tlight \"%@\", %@, %g\n", action.data ?: @"", UDFXCommaList(action.lightColor ?: @""),
                              action.lightRadius.doubleValue];
        } else if ([kind isEqualToString:@"shake"]) {
            [out appendFormat:@"\t\tshake %g, %g, %g, %d, %g\n", action.shakeTime.doubleValue, action.shakeAmplitude.doubleValue,
                              action.shakeDistance.doubleValue, action.shakeFalloff ? 1 : 0, action.shakeImpulse.doubleValue];
        } else if (kind.length > 0) {
            NSString *keyword = [kind isEqualToString:@"usemodel"] ? @"useModel" : [kind isEqualToString:@"uselight"] ? @"useLight" : kind;
            [out appendFormat:@"\t\t%@ \"%@\"\n", keyword, action.data ?: @""];
        }
        if (action.fire.length > 0) [out appendFormat:@"\t\tfire \"%@\"\n", action.fire];
        UDFXWriteNumber(out, @"size", action.size);
        UDFXWriteNumber(out, @"rotate", action.rotate);
        if (action.offset.length > 0) [out appendFormat:@"\t\toffset %@\n", UDFXCommaList(action.offset)];
        if (action.axis.length > 0) [out appendFormat:@"\t\taxis %@\n", UDFXCommaList(action.axis)];
        if (action.angle.length > 0) [out appendFormat:@"\t\tangle %@\n", UDFXCommaList(action.angle)];
        UDFXWriteNumber(out, @"fadeIn", action.fadeIn);
        UDFXWriteNumber(out, @"fadeOut", action.fadeOut);
        if (action.trackOrigin) [out appendString:@"\t\ttrackorigin 1\n"];
        if (action.noshadows) [out appendString:@"\t\tnoshadows\n"];
        if (action.particleTrackVelocity) [out appendString:@"\t\tparticleTrackVelocity\n"];
        if (action.ignoreMaster) [out appendString:@"\t\tignoreMaster\n"];
        [out appendString:@"\t}\n"];
    }
    [out appendString:@"}"];
    return [out dataUsingEncoding:NSUTF8StringEncoding];
}

@end
