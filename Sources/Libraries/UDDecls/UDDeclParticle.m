/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 * UDDeclParticle.m — particles (idDeclParticle).
 */

#import "UDDeclManagedObjects.h"
#import "UDDeclParticle.h"
#import <objc/runtime.h>

#import "UDDeclCodec.h"
#import "UDDeclIncrementalStore.h"
#import "UDDeclTextChecker.h"
#import "idLexer.h"
#import "idToken.h"
#import "idStr.h"

#pragma mark - DeclParticle

// keyword tables ported from idDeclParticle.m
typedef struct UDParticleParmDesc {
    const char *name;
    int count;
} UDParticleParmDesc_t;

static const UDParticleParmDesc_t UDParticleDistributionDesc[] = {
    { "rect", 3 },
    { "cylinder", 4 },
    { "sphere", 3 },
};

static const UDParticleParmDesc_t UDParticleDirectionDesc[] = {
    { "cone", 1 },
    { "outward", 1 },
};

static const UDParticleParmDesc_t UDParticleOrientationDesc[] = {
    { "view", 0 },
    { "aimed", 2 },
    { "x", 0 },
    { "y", 0 },
    { "z", 0 },
};

static const UDParticleParmDesc_t UDParticleCustomDesc[] = {
    { "standard", 0 },
    { "helix", 5 },
    { "flies", 3 },
    { "orbit", 2 },
    { "drip", 2 },
};

#define UDParticleDescCount(table) ((int)(sizeof(table) / sizeof((table)[0])))

static int UDParticleDescIndex(const UDParticleParmDesc_t *table, int tableCount, const char *keyword) {
    for (int i = 0; i < tableCount; i++) {
        if (strcasecmp(table[i].name, keyword) == 0) {
            return i;
        }
    }
    return -1;
}

@implementation UDParticleStage

// The defaults the old idParticleStage's -defaults installed before parsing
// a stage; keywords the decl text doesn't mention keep these values.
- (instancetype)init {
    self = [super init];
    if (self) {
        _material = @"_default";
        _totalParticles = 100;
        _cycles = 0.0f;
        _spawnBunching = 1.0f;
        _particleLife = 1.5f;
        _timeOffset = 0.0f;
        _deadTime = 0.0f;
        _distributionType = 0; // rect
        _distributionParms = @"8 8 8 0";
        _directionType = 0; // cone
        _directionParms = @"90 0 0 0";
        _orientation = 0; // view
        _orientationParms = @"0 0 0 0";
        _customPathType = 0; // standard
        _customPathParms = @"0 0 0 0 0 0 0 0";
        _speedFrom = 150.0f;
        _speedTo = 150.0f;
        _rotationFrom = 0.0f;
        _rotationTo = 0.0f;
        _sizeFrom = 4.0f;
        _sizeTo = 4.0f;
        _aspectFrom = 1.0f;
        _aspectTo = 1.0f;
        _gravity = 1.0f;
        _worldGravity = NO;
        _randomDistribution = YES;
        _entityColor = NO;
        _offset = @"0 0 0";
        _animationFrames = 0;
        _animationRate = 0.0f;
        _initialAngle = 0.0f;
        _color = @"1 1 1 1";
        _fadeColor = @"0 0 0 0";
        _fadeInFraction = 0.1f;
        _fadeOutFraction = 0.25f;
        _fadeIndexFraction = 0.0f;
        _boundsExpansion = 0.0f;
        _softeningRadius = -2.0f;
        _hidden = NO;
    }
    return self;
}

@end

/// The floats @a parms holds, as a stage's parameter string.
static NSString *UDParticleParmString(const float *parms, int count) {
    NSMutableArray<NSString *> *values = [NSMutableArray arrayWithCapacity:count];
    for (int i = 0; i < count; i++) {
        [values addObject:[NSString stringWithFormat:@"%g", parms[i]]];
    }
    return [values componentsJoinedByString:@" "];
}

// idDeclParticle::ParseParms: every token left on the line, as atof reads it.
static void UDParticleParseParms(idLexer *src, float *parms, int maxParms) {
    idToken token;
    idToken_Init(&token);
    memset( parms, 0, maxParms * sizeof( *parms ) );
    int count = 0;
    while( 1 ) {
        if ( ![src readTokenOnLine:&token error:NULL] ) {
            return;
        }
        if ( count == maxParms ) {
            [src error:NULL format:@"too many parms on line"];
            return;
        }
        idToken_StripQuotes( &token );
        parms[count] = atof( token.text );
        count++;
    }
}

// idDeclParticle::ParseParametric, into <prefix>Table / From / To.
static void UDParticleParseParametric(idLexer *src, UDParticleStage *stage, NSString *prefix) {
    idToken token;
    idToken_Init(&token);
    NSString *tableKey = [prefix stringByAppendingString:@"Table"];
    NSString *fromKey = [prefix stringByAppendingString:@"From"];
    NSString *toKey = [prefix stringByAppendingString:@"To"];

    [stage setValue:nil forKey:tableKey];
    [stage setValue:@0.0f forKey:fromKey];
    [stage setValue:@0.0f forKey:toKey];

    if ( ![src readToken:&token error:NULL] ) {
        [src error:NULL format:@"not enough parameters"];
        return;
    }

    if ( idStr_IsNumericCString( token.text ) ) {
        // can have a to + 2nd parm
        float from = atof( token.text );
        [stage setValue:@(from) forKey:fromKey];
        [stage setValue:@(from) forKey:toKey];
        if ( [src readToken:&token error:NULL] ) {
            if ( !strcasecmp( token.text, "to" ) ) {
                if ( ![src readToken:&token error:NULL] ) {
                    [src error:NULL format:@"missing second parameter"];
                    return;
                }
                [stage setValue:@((float)atof( token.text )) forKey:toKey];
            } else {
                [src unreadToken:&token error:NULL];
            }
        }
    } else {
        // table
        [stage setValue:UDTokenString(&token) forKey:tableKey];
    }
}

// idDeclParticle::ParseParticleStage. It always gives a stage: an error
// (an unknown token, a bad type) ends it with what it has read.
static UDParticleStage *UDParticleParseStage(idLexer *src, NSString *name) {
    idToken token;
    idToken_Init(&token);
    UDParticleStage *stage = [[UDParticleStage alloc] init];           // Default()
    float parms[8];

    while (1) {
        if ( [src hadError] ) {
            break;
        }
        if ( ![src readToken:&token error:NULL] ) {
            break;
        }
        if ( !strcasecmp( token.text, "}" ) ) {
            break;
        }
        if ( !strcasecmp( token.text, "material" ) ) {
            [src readToken:&token error:NULL];
            stage.material = UDTokenString(&token);
            continue;
        }
        if ( !strcasecmp( token.text, "count" ) ) {
            int i = 0;
            [src parseInt:&i error:NULL];
            stage.totalParticles = i;
            continue;
        }
        static const struct { const char *keyword; const char *key; } floats[] = {
            { "time", "particleLife" }, { "cycles", "cycles" }, { "timeOffset", "timeOffset" },
            { "deadTime", "deadTime" }, { "bunching", "spawnBunching" }, { "angle", "initialAngle" },
            { "fadeIn", "fadeInFraction" }, { "fadeOut", "fadeOutFraction" }, { "fadeIndex", "fadeIndexFraction" },
            { "animationRate", "animationRate" }, { "boundsExpansion", "boundsExpansion" },
        };
        BOOL matched = NO;
        for ( size_t i = 0; i < sizeof( floats ) / sizeof( floats[0] ); i++ ) {
            if ( !strcasecmp( token.text, floats[i].keyword ) ) {
                float f = 0.0f;
                [src parseFloat:&f error:NULL];
                [stage setValue:@(f) forKey:[NSString stringWithUTF8String:floats[i].key]];
                matched = YES;
                break;
            }
        }
        if ( matched ) {
            continue;
        }
        if ( !strcasecmp( token.text, "randomDistribution" ) ) {
            BOOL b = NO;
            [src parseBool:&b error:NULL];
            stage.randomDistribution = b;
            continue;
        }
        if ( !strcasecmp( token.text, "entityColor" ) ) {
            BOOL b = NO;
            [src parseBool:&b error:NULL];
            stage.entityColor = b;
            continue;
        }
        if ( !strcasecmp( token.text, "animationFrames" ) ) {
            int i = 0;
            [src parseInt:&i error:NULL];
            stage.animationFrames = i;
            continue;
        }
        if ( !strcasecmp( token.text, "distribution" ) ) {
            [src readToken:&token error:NULL];
            int type = UDParticleDescIndex( UDParticleDistributionDesc, UDParticleDescCount( UDParticleDistributionDesc ), token.text );
            if ( type >= 0 ) {
                stage.distributionType = type;
            } else {
                [src error:NULL format:@"bad distribution type: %s\n", token.text];
            }
            UDParticleParseParms( src, parms, 4 );
            stage.distributionParms = UDParticleParmString( parms, 4 );
            continue;
        }
        if ( !strcasecmp( token.text, "direction" ) ) {
            [src readToken:&token error:NULL];
            int type = UDParticleDescIndex( UDParticleDirectionDesc, UDParticleDescCount( UDParticleDirectionDesc ), token.text );
            if ( type >= 0 ) {
                stage.directionType = type;
            } else {
                [src error:NULL format:@"bad direction type: %s\n", token.text];
            }
            UDParticleParseParms( src, parms, 4 );
            stage.directionParms = UDParticleParmString( parms, 4 );
            continue;
        }
        if ( !strcasecmp( token.text, "orientation" ) ) {
            [src readToken:&token error:NULL];
            int type = UDParticleDescIndex( UDParticleOrientationDesc, UDParticleDescCount( UDParticleOrientationDesc ), token.text );
            if ( type >= 0 ) {
                stage.orientation = type;
            } else {
                [src error:NULL format:@"bad orientation type: %s\n", token.text];
            }
            UDParticleParseParms( src, parms, 4 );
            stage.orientationParms = UDParticleParmString( parms, 4 );
            continue;
        }
        if ( !strcasecmp( token.text, "customPath" ) ) {
            [src readToken:&token error:NULL];
            // The parser's names: "spherical" is PPATH_ORBIT (written as "orbit"), and no "drip".
            if ( !strcasecmp( token.text, "standard" ) ) {
                stage.customPathType = 0;
            } else if ( !strcasecmp( token.text, "helix" ) ) {
                stage.customPathType = 1;
            } else if ( !strcasecmp( token.text, "flies" ) ) {
                stage.customPathType = 2;
            } else if ( !strcasecmp( token.text, "spherical" ) ) {
                stage.customPathType = 3;
            } else {
                [src error:NULL format:@"bad path type: %s\n", token.text];
            }
            UDParticleParseParms( src, parms, 8 );
            stage.customPathParms = UDParticleParmString( parms, 8 );
            continue;
        }
        if ( !strcasecmp( token.text, "speed" ) ) {
            UDParticleParseParametric( src, stage, @"speed" );
            continue;
        }
        if ( !strcasecmp( token.text, "rotation" ) ) {
            UDParticleParseParametric( src, stage, @"rotation" );
            continue;
        }
        if ( !strcasecmp( token.text, "size" ) ) {
            UDParticleParseParametric( src, stage, @"size" );
            continue;
        }
        if ( !strcasecmp( token.text, "aspect" ) ) {
            UDParticleParseParametric( src, stage, @"aspect" );
            continue;
        }
        if ( !strcasecmp( token.text, "color" ) || !strcasecmp( token.text, "fadeColor" ) ) {
            float c[4] = { 0, 0, 0, 0 };
            for ( int i = 0; i < 4; i++ ) {
                [src parseFloat:&c[i] error:NULL];
            }
            [stage setValue:UDParticleParmString( c, 4 ) forKey:!strcasecmp( token.text, "color" ) ? @"color" : @"fadeColor"];
            continue;
        }
        if ( !strcasecmp( token.text, "offset" ) ) {
            float o[3] = { 0, 0, 0 };
            for ( int i = 0; i < 3; i++ ) {
                [src parseFloat:&o[i] error:NULL];
            }
            stage.offset = UDParticleParmString( o, 3 );
            continue;
        }
        if ( !strcasecmp( token.text, "gravity" ) ) {
            [src readToken:&token error:NULL];
            if ( !strcasecmp( token.text, "world" ) ) {
                stage.worldGravity = YES;
            } else {
                [src unreadToken:&token error:NULL];
            }
            float f = 0.0f;
            [src parseFloat:&f error:NULL];
            stage.gravity = f;
            continue;
        }
        if ( !strcasecmp( token.text, "softeningRadius" ) ) { // #3878 soft particles
            // dhewm3 warns and ignores it (its value is read next, as a keyword)
            [src warning:@"Particle %@ has stage with \"softeningRadius\" attribute, which is currently ignored (we soften all suitable particles)", name];
            continue;
        }
        [src error:NULL format:@"unknown token %s\n", token.text];
    }
    return stage;
}

static void UDParticleWriteParametric(NSMutableString *out, UDParticleStage *stage, NSString *keyword, NSString *prefix) {
    NSString *table = UDStringValue(stage, [prefix stringByAppendingString:@"Table"]);
    float from = UDFloatValue(stage, [prefix stringByAppendingString:@"From"]);
    float to = UDFloatValue(stage, [prefix stringByAppendingString:@"To"]);

    [out appendFormat:@"\t\t%@\t\t\t\t ", keyword];
    if (table.length > 0) {
        [out appendFormat:@"%@\n", table];
    } else if (from == to) {
        [out appendFormat:@"\"%.3f\" \n", from];
    } else {
        [out appendFormat:@"\"%.3f\"  to \"%.3f\"\n", from, to];
    }
}

static void UDParticleWriteStage(NSMutableString *out, UDParticleStage *stage) {
    [out appendString:@"\t{\n"];
    [out appendFormat:@"\t\tcount\t\t\t\t%i\n", UDIntValue(stage, @"totalParticles")];
    [out appendFormat:@"\t\tmaterial\t\t\t%@\n", UDStringValue(stage, @"material")];
    if (UDIntValue(stage, @"animationFrames")) {
        [out appendFormat:@"\t\tanimationFrames \t%i\n", UDIntValue(stage, @"animationFrames")];
    }
    if (UDFloatValue(stage, @"animationRate")) {
        [out appendFormat:@"\t\tanimationRate \t\t%.3f\n", UDFloatValue(stage, @"animationRate")];
    }
    [out appendFormat:@"\t\ttime\t\t\t\t%.3f\n", UDFloatValue(stage, @"particleLife")];
    [out appendFormat:@"\t\tcycles\t\t\t\t%.3f\n", UDFloatValue(stage, @"cycles")];
    if (UDFloatValue(stage, @"timeOffset")) {
        [out appendFormat:@"\t\ttimeOffset\t\t\t%.3f\n", UDFloatValue(stage, @"timeOffset")];
    }
    if (UDFloatValue(stage, @"deadTime")) {
        [out appendFormat:@"\t\tdeadTime\t\t\t%.3f\n", UDFloatValue(stage, @"deadTime")];
    }
    [out appendFormat:@"\t\tbunching\t\t\t%.3f\n", UDFloatValue(stage, @"spawnBunching")];

    float parms[8];

    int distribution = UDIntValue(stage, @"distributionType");
    if (distribution < 0 || distribution >= UDParticleDescCount(UDParticleDistributionDesc)) {
        distribution = 0;
    }
    UDStringToFloats(UDStringValue(stage, @"distributionParms"), parms, 8);
    [out appendFormat:@"\t\tdistribution\t\t%s ", UDParticleDistributionDesc[distribution].name];
    for (int i = 0; i < UDParticleDistributionDesc[distribution].count; i++) {
        [out appendFormat:@"%.3f ", parms[i]];
    }
    [out appendString:@"\n"];

    int direction = UDIntValue(stage, @"directionType");
    if (direction < 0 || direction >= UDParticleDescCount(UDParticleDirectionDesc)) {
        direction = 0;
    }
    UDStringToFloats(UDStringValue(stage, @"directionParms"), parms, 8);
    [out appendFormat:@"\t\tdirection\t\t\t%s ", UDParticleDirectionDesc[direction].name];
    for (int i = 0; i < UDParticleDirectionDesc[direction].count; i++) {
        [out appendFormat:@"\"%.3f\" ", parms[i]];
    }
    [out appendString:@"\n"];

    int orientation = UDIntValue(stage, @"orientation");
    if (orientation < 0 || orientation >= UDParticleDescCount(UDParticleOrientationDesc)) {
        orientation = 0;
    }
    UDStringToFloats(UDStringValue(stage, @"orientationParms"), parms, 8);
    [out appendFormat:@"\t\torientation\t\t\t%s ", UDParticleOrientationDesc[orientation].name];
    for (int i = 0; i < UDParticleOrientationDesc[orientation].count; i++) {
        [out appendFormat:@"%.3f ", parms[i]];
    }
    [out appendString:@"\n"];

    int customPath = UDIntValue(stage, @"customPathType");
    if (customPath < 0 || customPath >= UDParticleDescCount(UDParticleCustomDesc)) {
        customPath = 0;
    }
    if (customPath != 0) {
        UDStringToFloats(UDStringValue(stage, @"customPathParms"), parms, 8);
        [out appendFormat:@"\t\tcustomPath %s ", UDParticleCustomDesc[customPath].name];
        for (int i = 0; i < UDParticleCustomDesc[customPath].count; i++) {
            [out appendFormat:@"%.3f ", parms[i]];
        }
        [out appendString:@"\n"];
    }

    if (UDBoolValue(stage, @"entityColor")) {
        [out appendString:@"\t\tentityColor\t\t\t1\n"];
    }

    UDParticleWriteParametric(out, stage, @"speed", @"speed");
    UDParticleWriteParametric(out, stage, @"size", @"size");
    UDParticleWriteParametric(out, stage, @"aspect", @"aspect");

    // As WriteStage has it: only when rotationSpeed.from is not 0 (a
    // rotation by a table is not written).
    if (UDFloatValue(stage, @"rotationFrom")) {
        UDParticleWriteParametric(out, stage, @"rotation", @"rotation");
    }

    if (UDFloatValue(stage, @"initialAngle")) {
        [out appendFormat:@"\t\tangle\t\t\t\t%.3f\n", UDFloatValue(stage, @"initialAngle")];
    }

    [out appendFormat:@"\t\trandomDistribution\t\t\t\t%i\n", UDBoolValue(stage, @"randomDistribution") ? 1 : 0];
    [out appendFormat:@"\t\tboundsExpansion\t\t\t\t%.3f\n", UDFloatValue(stage, @"boundsExpansion")];

    [out appendFormat:@"\t\tfadeIn\t\t\t\t%.3f\n", UDFloatValue(stage, @"fadeInFraction")];
    [out appendFormat:@"\t\tfadeOut\t\t\t\t%.3f\n", UDFloatValue(stage, @"fadeOutFraction")];
    [out appendFormat:@"\t\tfadeIndex\t\t\t\t%.3f\n", UDFloatValue(stage, @"fadeIndexFraction")];

    float c[4];
    UDStringToFloats(UDStringValue(stage, @"color"), c, 4);
    [out appendFormat:@"\t\tcolor \t\t\t\t%.3f %.3f %.3f %.3f\n", c[0], c[1], c[2], c[3]];
    UDStringToFloats(UDStringValue(stage, @"fadeColor"), c, 4);
    [out appendFormat:@"\t\tfadeColor \t\t\t%.3f %.3f %.3f %.3f\n", c[0], c[1], c[2], c[3]];

    float o[3];
    UDStringToFloats(UDStringValue(stage, @"offset"), o, 3);
    [out appendFormat:@"\t\toffset \t\t\t\t%.3f %.3f %.3f\n", o[0], o[1], o[2]];

    [out appendString:@"\t\tgravity \t\t\t"];
    if (UDBoolValue(stage, @"worldGravity")) {
        [out appendString:@"world "];
    }
    [out appendFormat:@"%.3f\n", UDFloatValue(stage, @"gravity")];
    [out appendString:@"\t}\n"];
}

@implementation UDDeclParticle

@dynamic depthHack;

@dynamic stages;

UD_ELEMENT_ARRAY_SETTER(setStages, @"stages")

// stages is transient: read from the text here.
- (void)awakeFromFetch {
    [super awakeFromFetch];
    NSArray *stages = UDParsedSourceText(self)[@"stages"] ?: @[];
    [self setPrimitiveValue:stages forKey:@"stages"];
    UDAdoptElements(stages, self, @"stages");
}

+ (NSString *)ud_defaultDefinition {
    return
        @"{\n"
    @"\t"    @"{\n"
    @"\t\t"        @"material\t_default\n"
    @"\t\t"        @"count\t20\n"
    @"\t\t"        @"time\t\t1.0\n"
    @"\t"    @"}\n"
        @"}";
}

// idDeclParticle::Parse. Where it gives up, MakeDefault(): the values are
// the default definition's.
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

    float depthHack = 0.0f;
    NSMutableArray<UDParticleStage *> *stages = [NSMutableArray array];
    while (1) {
        if ( ![src readToken:&token error:NULL] ) {
            break;
        }
        if ( !strcasecmp( token.text, "}" ) ) {
            break;
        }
        if ( !strcasecmp( token.text, "{" ) ) {
            [stages addObject:UDParticleParseStage( src, name )];
            continue;
        }
        if ( !strcasecmp( token.text, "depthHack" ) ) {
            [src parseFloat:&depthHack error:NULL];
            continue;
        }
        [src warning:@"bad token %s", token.text];
        return [self ud_defaultValuesNamed:name];
    }
    return @{
        @"depthHack": @(depthHack),
        @"stages": stages,
    };
}

/// MakeDefault()'s values: the default definition, parsed.
+ (NSDictionary<NSString *, id> *)ud_defaultValuesNamed:(NSString *)name {
    NSData *text = [[self ud_defaultDefinition] dataUsingEncoding:NSUTF8StringEncoding];
    return [self ud_parseValuesFromText:text name:name fileName:nil lineNum:1 fileSystem:nil error:NULL];
}

+ (NSData *)ud_textByUnparsingName:(NSString *)name
                            values:(NSDictionary<NSString *, id> *)values
                             error:(NSError **)error {
    NSMutableString *out = [NSMutableString string];
    [out appendFormat:@"particle %@ {\n", name];

    float depthHack = UDFloatValue(values, @"depthHack");
    if (depthHack) {
        [out appendFormat:@"\tdepthHack\t%f\n", depthHack];
    }

    for (UDParticleStage *stage in values[@"stages"] ?: @[]) {
        UDParticleWriteStage(out, stage);
    }

    [out appendString:@"}"];
    return [out dataUsingEncoding:NSUTF8StringEncoding];
}

@end
