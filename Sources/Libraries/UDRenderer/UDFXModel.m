/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 * UDFXModel.m — idEntityFx's Setup, Start, Duration, ApplyFade, Run and
 * CleanUp (game/Fx.cpp), and what idDeclFX::ParseSingleFXAction derives
 * (DeclFX.cpp: an action's type, its sibling, a used light's color and
 * radius, its explicit axis), ported. The world is not there: a light and a
 * model are their renderLight's and renderEntity's parms, a sound, shake,
 * decal or launch the flag Run sets for it; the entity is at the origin,
 * unrotated. gameLocal.random is an idRandom seeded 0, as a map's start
 * seeds it.
 */

#import "idMath.h"
#import "UDFXModel.h"
#import "UDDeclCodec.h"
#import "UDDeclFX.h"
#import "UDDeclParticle.h"
#import "UDParticleModel.h"
#import "UDSoftwareRenderer.h"
#import "idDeclManager.h"

#define MAX_ENTITY_SHADER_PARMS     12
#define SHADERPARM_RED              0
#define SHADERPARM_GREEN            1
#define SHADERPARM_BLUE             2
#define SHADERPARM_TIMESCALE        3
#define SHADERPARM_TIMEOFFSET       4
#define USERCMD_MSEC                ( 1000 / 60 )

#define MS2SEC( t )                 ( ( t ) * 0.001f )

typedef enum {
    FX_LIGHT,
    FX_PARTICLE,
    FX_DECAL,
    FX_MODEL,
    FX_SOUND,
    FX_SHAKE,
    FX_ATTACHLIGHT,
    FX_ATTACHENTITY,
    FX_LAUNCH,
    FX_SHOCKWAVE
} fx_enum;

// idFXSingleAction: what Run reads of it
typedef struct {
    int         type;
    int         sibling;

    __unsafe_unretained NSString *data;
    __unsafe_unretained NSString *name;
    __unsafe_unretained NSString *fire;

    float       delay;
    float       duration;
    float       restart;
    float       fadeInTime;
    float       fadeOutTime;
    float       random1;
    float       random2;

    float       lightColor[3];
    float       lightRadius;
    float       offset[3];
    float       axis[3][3];

    BOOL        explicitAxis;
    BOOL        trackOrigin;
} idFXSingleAction;

typedef struct {
    BOOL        lightDef;                // lightDefHandle != -1
    float       lightShaderParms[MAX_ENTITY_SHADER_PARMS];
    BOOL        modelDef;                // modelDefHandle != -1
    float       entityShaderParms[MAX_ENTITY_SHADER_PARMS];
    float       delay;
    int         start;
    int         spawnTime;
    BOOL        soundStarted;
    BOOL        shakeStarted;
    BOOL        decalDropped;
    BOOL        launched;
    // (the state, for the editor)
    BOOL        running;
    float       pct;
} idFXLocalAction;

// idRandom: idMath.h's

#pragma mark - idMath, idVec3, idAngles

static void UDIdentity( float axis[3][3] ) {
    memset( axis, 0, 9 * sizeof( float ) );
    axis[0][0] = axis[1][1] = axis[2][2] = 1;
}

/*
=============
idVec3::ToMat3
=============
*/
static void Vec3_ToMat3( const float v[3], float mat[3][3] ) {
    float    d;

    mat[0][0] = v[0]; mat[0][1] = v[1]; mat[0][2] = v[2];
    d = v[0] * v[0] + v[1] * v[1];
    if ( !d ) {
        mat[1][0] = 1.0f;
        mat[1][1] = 0.0f;
        mat[1][2] = 0.0f;
    } else {
        d = 1.0f / sqrtf( d );             // idMath::InvSqrt
        mat[1][0] = -v[1] * d;
        mat[1][1] = v[0] * d;
        mat[1][2] = 0.0f;
    }
    // mat[2] = mat[0].Cross( mat[1] )
    mat[2][0] = mat[0][1] * mat[1][2] - mat[0][2] * mat[1][1];
    mat[2][1] = mat[0][2] * mat[1][0] - mat[0][0] * mat[1][2];
    mat[2][2] = mat[0][0] * mat[1][1] - mat[0][1] * mat[1][0];
}

/*
=================
idAngles::ToMat3
=================
*/
static void Angles_ToMat3( float pitch, float yaw, float roll, float mat[3][3] ) {
    float sr, sp, sy, cr, cp, cy;
    const float deg2rad = 3.14159265358979323846f / 180.0f;

    sy = sinf( yaw * deg2rad ); cy = cosf( yaw * deg2rad );        // idMath::SinCos
    sp = sinf( pitch * deg2rad ); cp = cosf( pitch * deg2rad );
    sr = sinf( roll * deg2rad ); cr = cosf( roll * deg2rad );

    mat[0][0] = cp * cy; mat[0][1] = cp * sy; mat[0][2] = -sp;
    mat[1][0] = sr * sp * cy + cr * -sy; mat[1][1] = sr * sp * sy + cr * cy; mat[1][2] = sr * cp;
    mat[2][0] = cr * sp * cy + -sr * -sy; mat[2][1] = cr * sp * sy + -sr * cy; mat[2][2] = cr * cp;
}

#pragma mark -

@interface UDFXActionState () {
@public
    float parms[MAX_ENTITY_SHADER_PARMS];
}
@property (nonatomic, readwrite) NSInteger index;
@property (nonatomic, readwrite) BOOL running;
@property (nonatomic, readwrite) float fraction;
@property (nonatomic, readwrite) BOOL hasModel;
@property (nonatomic, readwrite) BOOL hasLight;
@property (nonatomic, readwrite) int spawnTime;
@end

@implementation UDFXActionState

- (const float *)shaderParms {
    return parms;
}

@end

@interface UDFXModel () {
    idFXSingleAction *events;
    int numEvents;
    idFXLocalAction *actions;
    idRandom random;            // gameLocal.random
}
@property (nonatomic, strong, nullable) idDeclManager *declManager;
@property (nonatomic, copy) NSArray<NSString *> *strings;     // what the events' strings are, held
@property (nonatomic, strong) NSMutableDictionary<NSString *, id> *particleModels;
@end

@implementation UDFXModel

/// idDeclFX::ParseSingleFXAction's type for our action's keyword.
static int UDFXType( NSString *kind ) {
    NSDictionary<NSString *, NSNumber *> *types = @{
        @"light": @(FX_LIGHT), @"uselight": @(FX_LIGHT), @"attachlight": @(FX_ATTACHLIGHT),
        @"model": @(FX_MODEL), @"usemodel": @(FX_MODEL), @"particle": @(FX_PARTICLE), @"decal": @(FX_DECAL),
        @"sound": @(FX_SOUND), @"shake": @(FX_SHAKE), @"attachentity": @(FX_ATTACHENTITY), @"launch": @(FX_LAUNCH),
        @"shockwave": @(FX_SHOCKWAVE) };
    NSNumber *type = kind != nil ? types[kind.lowercaseString] : nil;
    return type != nil ? type.intValue : -1;
}

- (instancetype)initWithActions:(NSArray<UDFXAction *> *)source declManager:(idDeclManager *)declManager {
    self = [super init];
    if (self) {
        _declManager = declManager;
        _particleModels = [NSMutableDictionary dictionary];
        numEvents = (int)source.count;
        events = calloc( MAX( numEvents, 1 ), sizeof( idFXSingleAction ) );
        actions = calloc( MAX( numEvents, 1 ), sizeof( idFXLocalAction ) );
        NSMutableArray<NSString *> *strings = [NSMutableArray array];
        for ( int i = 0; i < numEvents; i++ ) {
            UDFXAction *from = source[(NSUInteger)i];
            idFXSingleAction *FXAction = &events[i];
            // ParseSingleFXAction's defaults
            FXAction->sibling = -1;
            NSString *data = from.data ?: @"<none>", *name = from.name ?: @"<none>", *fire = from.fire ?: @"<none>";
            [strings addObjectsFromArray:@[data, name, fire]];
            FXAction->data = data;
            FXAction->name = name;
            FXAction->fire = fire;
            FXAction->type = UDFXType( from.kind );
            FXAction->delay = from.delay.floatValue;
            FXAction->duration = from.duration.floatValue;
            FXAction->restart = from.restart.floatValue;
            FXAction->fadeInTime = from.fadeIn.floatValue;
            FXAction->fadeOutTime = from.fadeOut.floatValue;
            FXAction->random1 = from.random1.floatValue;
            FXAction->random2 = from.random2.floatValue;
            UDStringToFloats( from.lightColor, FXAction->lightColor, 3 );
            FXAction->lightRadius = from.lightRadius.floatValue;
            UDStringToFloats( from.offset, FXAction->offset, 3 );
            FXAction->trackOrigin = from.trackOrigin;
            UDIdentity( FXAction->axis );
            if ( from.axis.length > 0 ) {
                float v[3];
                UDStringToFloats( from.axis, v, 3 );
                float length = sqrtf( v[0] * v[0] + v[1] * v[1] + v[2] * v[2] );      // v.Normalize()
                if ( length > 0 ) { v[0] /= length; v[1] /= length; v[2] /= length; }
                Vec3_ToMat3( v, FXAction->axis );
                FXAction->explicitAxis = YES;
            }
            if ( from.angle.length > 0 ) {
                float a[3];
                UDStringToFloats( from.angle, a, 3 );
                Angles_ToMat3( a[0], a[1], a[2], FXAction->axis );
                FXAction->explicitAxis = YES;
            }
            // uselight and useModel: the earlier action named so is its sibling
            NSString *kind = from.kind.lowercaseString;
            if ( [kind isEqualToString:@"uselight"] || [kind isEqualToString:@"usemodel"] ) {
                for ( int j = 0; j < i; j++ ) {
                    if ( [events[j].name caseInsensitiveCompare:data] == NSOrderedSame ) {
                        FXAction->sibling = j;
                        if ( [kind isEqualToString:@"uselight"] ) {
                            memcpy( FXAction->lightColor, events[j].lightColor, sizeof( FXAction->lightColor ) );
                            FXAction->lightRadius = events[j].lightRadius;
                        }
                    }
                }
            }
        }
        _strings = strings;
    }
    return self;
}

- (void)dealloc {
    free( events );
    free( actions );
}

/*
================
idEntityFx::Setup
================
*/
- (void)setup {
    random.seed = 0;
    memset( actions, 0, MAX( numEvents, 1 ) * sizeof( idFXLocalAction ) );
    for( int i = 0; i<numEvents; i++ ) {
        const idFXSingleAction *fxaction = &events[i];

        idFXLocalAction *laction = &actions[i];
        if ( fxaction->random1 || fxaction->random2 ) {
            laction->delay = fxaction->random1 + idRandom_RandomFloat( &random ) * ( fxaction->random2 - fxaction->random1 );
        } else {
            laction->delay = fxaction->delay;
        }
        laction->start = -1;
        laction->lightDef = NO;
        laction->modelDef = NO;
        laction->shakeStarted = NO;
        laction->decalDropped = NO;
        laction->launched = NO;
    }
}

/*
================
idEntityFx::Start
================
*/
- (void)start:(int)time {
    for( int i = 0; i < numEvents; i++ ) {
        idFXLocalAction *laction = &actions[i];
        laction->start = time;
        laction->soundStarted = NO;
        laction->shakeStarted = NO;
        laction->decalDropped = NO;
        laction->launched = NO;
    }
}

/*
================
idEntityFx::Duration
================
*/
- (int)duration {
    int max = 0;

    for( int i = 0; i < numEvents; i++ ) {
        const idFXSingleAction *fxaction = &events[i];
        int d = ( fxaction->delay + fxaction->duration ) * 1000.0f;
        if ( d > max ) {
            max = d;
        }
    }

    return max;
}

/*
================
idEntityFx::CleanUp, CleanUpSingleAction
================
*/
- (void)cleanUp {
    for( int i = 0; i < numEvents; i++ ) {
        const idFXSingleAction *fxaction = &events[i];
        idFXLocalAction *laction = &actions[i];
        if ( laction->lightDef && fxaction->sibling == -1 && fxaction->type != FX_ATTACHLIGHT ) {
            laction->lightDef = NO;
        }
        if ( laction->modelDef && fxaction->sibling == -1 && fxaction->type != FX_ATTACHENTITY ) {
            laction->modelDef = NO;
        }
        laction->start = -1;
    }
}

/*
================
idEntityFx::ApplyFade
================
*/
- (void)applyFade:(const idFXSingleAction *)fxaction laction:(idFXLocalAction *)laction time:(const int)time actualStart:(const int)actualStart {
    if ( fxaction->fadeInTime || fxaction->fadeOutTime ) {
        float fadePct = (float)( time - actualStart ) / ( 1000.0f * ( ( fxaction->fadeInTime != 0 ) ? fxaction->fadeInTime : fxaction->fadeOutTime ) );
        if (fadePct > 1.0) {
            fadePct = 1.0;
        }
        if ( laction->modelDef ) {
            laction->entityShaderParms[SHADERPARM_RED] = (fxaction->fadeInTime) ? fadePct : 1.0f - fadePct;
            laction->entityShaderParms[SHADERPARM_GREEN] = (fxaction->fadeInTime) ? fadePct : 1.0f - fadePct;
            laction->entityShaderParms[SHADERPARM_BLUE] = (fxaction->fadeInTime) ? fadePct : 1.0f - fadePct;
        }
        if ( laction->lightDef ) {
            laction->lightShaderParms[SHADERPARM_RED] = fxaction->lightColor[0] * ( (fxaction->fadeInTime) ? fadePct : 1.0f - fadePct );
            laction->lightShaderParms[SHADERPARM_GREEN] = fxaction->lightColor[1] * ( (fxaction->fadeInTime) ? fadePct : 1.0f - fadePct );
            laction->lightShaderParms[SHADERPARM_BLUE] = fxaction->lightColor[2] * ( (fxaction->fadeInTime) ? fadePct : 1.0f - fadePct );
        }
    }
}

/*
================
idEntityFx::Run
================
*/
- (void)run:(int)time {
    int ieff, j;

    for( ieff = 0; ieff < numEvents; ieff++ ) {
        const idFXSingleAction *fxaction = &events[ieff];
        idFXLocalAction *laction = &actions[ieff];
        laction->running = NO;

        //
        // if we're currently done with this one
        //
        if ( laction->start == -1 ) {
            continue;
        }

        //
        // see if it's delayed
        //
        if ( laction->delay ) {
            if ( laction->start + (time - laction->start) < laction->start + (laction->delay * 1000) ) {
                continue;
            }
        }

        //
        // each event can have it's own delay and restart
        //
        int actualStart = laction->delay ? laction->start + (int)( laction->delay * 1000 ) : laction->start;
        float pct = (float)( time - actualStart ) / (1000 * fxaction->duration );
        if ( pct >= 1.0f ) {
            laction->start = -1;
            float totalDelay = 0.0f;
            if ( fxaction->restart ) {
                if ( fxaction->random1 || fxaction->random2 ) {
                    totalDelay = fxaction->random1 + idRandom_RandomFloat( &random ) * (fxaction->random2 - fxaction->random1);
                } else {
                    totalDelay = fxaction->delay;
                }
                laction->delay = totalDelay;
                laction->start = time;
            }
            continue;
        }
        laction->running = YES;
        laction->pct = pct;

        if ( fxaction->fire.length ) {
            for( j = 0; j < numEvents; j++ ) {
                if ( [events[j].name caseInsensitiveCompare:fxaction->fire] == NSOrderedSame ) {
                    actions[j].delay = 0;
                }
            }
        }

        idFXLocalAction *useAction;
        if ( fxaction->sibling == -1 ) {
            useAction = laction;
        } else {
            useAction = &actions[fxaction->sibling];
        }

        switch( fxaction->type ) {
            case FX_ATTACHLIGHT:
            case FX_LIGHT: {
                if ( !useAction->lightDef ) {
                    if ( fxaction->type == FX_LIGHT ) {
                        memset( useAction->lightShaderParms, 0, sizeof( useAction->lightShaderParms ) );
                        useAction->lightShaderParms[ SHADERPARM_RED ]    = fxaction->lightColor[0];
                        useAction->lightShaderParms[ SHADERPARM_GREEN ]    = fxaction->lightColor[1];
                        useAction->lightShaderParms[ SHADERPARM_BLUE ]    = fxaction->lightColor[2];
                        useAction->lightShaderParms[ SHADERPARM_TIMESCALE ]    = 1.0f;
                        useAction->lightShaderParms[ SHADERPARM_TIMEOFFSET ] = -MS2SEC( time );
                        useAction->lightDef = YES;
                        useAction->spawnTime = time;
                    }
                }
                [self applyFade:fxaction laction:useAction time:time actualStart:actualStart];
                break;
            }
            case FX_SOUND: {
                if ( !useAction->soundStarted ) {
                    useAction->soundStarted = YES;
                }
                break;
            }
            case FX_DECAL: {
                if ( !useAction->decalDropped ) {
                    useAction->decalDropped = YES;
                }
                break;
            }
            case FX_SHAKE: {
                if ( !useAction->shakeStarted ) {
                    useAction->shakeStarted = YES;
                }
                break;
            }
            case FX_ATTACHENTITY:
            case FX_PARTICLE:
            case FX_MODEL: {
                if ( !useAction->modelDef ) {
                    memset( useAction->entityShaderParms, 0, sizeof( useAction->entityShaderParms ) );
                    useAction->entityShaderParms[ SHADERPARM_RED ]        = 1.0f;
                    useAction->entityShaderParms[ SHADERPARM_GREEN ]        = 1.0f;
                    useAction->entityShaderParms[ SHADERPARM_BLUE ]        = 1.0f;
                    useAction->entityShaderParms[ SHADERPARM_TIMEOFFSET ] = -MS2SEC( time );
                    useAction->entityShaderParms[3] = 1.0f;
                    useAction->entityShaderParms[5] = 0.0f;
                    useAction->modelDef = YES;
                    useAction->spawnTime = time;
                }
                [self applyFade:fxaction laction:useAction time:time actualStart:actualStart];
                break;
            }
            case FX_LAUNCH: {
                if ( !useAction->launched ) {
                    useAction->launched = YES;
                }
                break;
            }
        }
    }
}

/// Setup, Start at 0, and Run at each game frame to @a msec; at the
/// duration, Event_ClearFx's Stop and CleanUp.
- (void)simulateTo:(int)msec {
    [self setup];
    [self start:0];
    int duration = self.duration;
    for ( int time = 0; time <= msec; time += USERCMD_MSEC ) {
        if ( time >= duration ) {
            [self cleanUp];
            for ( int i = 0; i < numEvents; i++ ) actions[i].running = NO;
            break;
        }
        [self run:time];
    }
}

- (NSArray<UDFXActionState *> *)statesAtTime:(int)msec {
    [self simulateTo:msec];
    NSMutableArray<UDFXActionState *> *states = [NSMutableArray arrayWithCapacity:(NSUInteger)numEvents];
    for ( int i = 0; i < numEvents; i++ ) {
        idFXLocalAction *laction = &actions[i];
        UDFXActionState *state = [[UDFXActionState alloc] init];
        state.index = i;
        state.running = laction->running;
        state.fraction = laction->running ? laction->pct : 0;
        state.hasModel = laction->modelDef;
        state.hasLight = laction->lightDef;
        state.spawnTime = laction->spawnTime;
        memcpy( state->parms, laction->modelDef ? laction->entityShaderParms : laction->lightShaderParms, sizeof( state->parms ) );
        [states addObject:state];
    }
    return states;
}

#pragma mark - Its particle systems

/// renderModelManager->FindModel( @a data )'s particle system: a .prt
/// model is idRenderModelPrt, its decl the name (FindType's canonical name,
/// its extension off); nil for a model of any other type.
- (nullable UDParticleModel *)particleModelFor:(NSString *)data {
    if ( [data.pathExtension caseInsensitiveCompare:@"prt"] != NSOrderedSame ) {
        return nil;
    }
    id model = self.particleModels[data];
    if ( model == nil ) {
        model = [NSNull null];
        NSString *declName = data.stringByDeletingPathExtension;
        idDeclBase *decl = [self.declManager findDeclWithoutParsing:DECL_PARTICLE name:declName makeDefault:NO];
        if ( decl != nil ) {
            NSMutableData *buffer = [NSMutableData data];
            [decl text:buffer];
            if ( buffer.length > 0 ) [buffer setLength:buffer.length - 1];
            NSDictionary *values = [UDDeclParticle ud_parseValuesFromText:buffer name:declName fileName:nil lineNum:1
                                                               fileSystem:nil error:NULL];
            NSArray *stages = values[@"stages"];
            if ( stages.count > 0 ) {
                model = [[UDParticleModel alloc] initWithStages:stages declManager:self.declManager];
            }
        }
        self.particleModels[data] = model;
    }
    return model == [NSNull null] ? nil : model;
}

- (NSArray<UDParticleSurface *> *)surfacesAtTime:(int)msec viewAxis:(const float [3][3])viewAxis {
    [self simulateTo:msec];
    NSMutableArray<UDParticleSurface *> *surfaces = [NSMutableArray array];
    for ( int i = 0; i < numEvents; i++ ) {
        const idFXSingleAction *fxaction = &events[i];
        // the model is the action's own, its sibling's for a useModel
        if ( fxaction->sibling != -1 ) continue;
        idFXLocalAction *laction = &actions[i];
        if ( !laction->modelDef ) continue;
        UDParticleModel *model = [self particleModelFor:fxaction->data];
        if ( model == nil ) continue;
        [surfaces addObjectsFromArray:[model surfacesAtTime:msec viewAxis:viewAxis shaderParms:laction->entityShaderParms
                                                     origin:fxaction->offset axis:fxaction->axis]];
    }
    return surfaces;
}

- (NSArray<UDPointLight *> *)lightsAtTime:(int)msec {
    [self simulateTo:msec];
    NSMutableArray<UDPointLight *> *lights = [NSMutableArray array];
    for ( int i = 0; i < numEvents; i++ ) {
        // the light is the action's own (a uselight's is its sibling's)
        const idFXSingleAction *fxaction = &events[i];
        idFXLocalAction *laction = &actions[i];
        if ( !laction->lightDef ) continue;
        UDPointLight *light = [[UDPointLight alloc] init];
        light.material = fxaction->data;
        for ( int k = 0; k < 3; k++ ) {
            light.origin[k] = fxaction->offset[k];
            light.radius[k] = fxaction->lightRadius;
        }
        memcpy( light.shaderParms, laction->lightShaderParms, sizeof( laction->lightShaderParms ) );
        [lights addObject:light];
    }
    return lights;
}

- (void)getBounds:(float [6])bounds {
    bounds[0] = bounds[1] = bounds[2] = INFINITY;
    bounds[3] = bounds[4] = bounds[5] = -INFINITY;
    for ( int i = 0; i < numEvents; i++ ) {
        const idFXSingleAction *fxaction = &events[i];
        if ( fxaction->type == FX_LIGHT && fxaction->sibling == -1 && fxaction->lightRadius > 0 ) {
            for ( int k = 0; k < 3; k++ ) {
                bounds[k] = MIN( bounds[k], fxaction->offset[k] - fxaction->lightRadius );
                bounds[3 + k] = MAX( bounds[3 + k], fxaction->offset[k] + fxaction->lightRadius );
            }
            continue;
        }
        if ( fxaction->type != FX_PARTICLE && fxaction->type != FX_MODEL && fxaction->type != FX_ATTACHENTITY ) continue;
        UDParticleModel *model = [self particleModelFor:fxaction->data];
        if ( model == nil ) continue;
        float b[6];
        [model getBounds:b];
        for ( int k = 0; k < 3; k++ ) {
            bounds[k] = MIN( bounds[k], b[k] + fxaction->offset[k] );
            bounds[3 + k] = MAX( bounds[3 + k], b[3 + k] + fxaction->offset[k] );
        }
    }
    if ( bounds[0] > bounds[3] ) {
        for ( int k = 0; k < 6; k++ ) bounds[k] = 0;
    }
}

@end
