/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 * UDParticleModel.m — idRandom (Random.h), idMath's 16-bit trigonometry
 * (Math.h), idParticleParm, idParticleStage's Default values, origin, verts,
 * texcoords, colors and CreateParticle, idDeclParticle::GetStageBounds
 * (DeclParticle.cpp), and idRenderModelPrt::InstantiateDynamicModel
 * (Model_prt.cpp), ported.
 */

#import "UDParticleModel.h"
#import "idMath.h"
#import "UDDeclCodec.h"
#import "UDDeclParticle.h"
#import "UDDeclTable.h"

#pragma mark - idMath

static const float idMath_PI = 3.14159265358979323846f;
static const float idMath_TWO_PI = 2.0f * 3.14159265358979323846f;
static const float idMath_HALF_PI = 0.5f * 3.14159265358979323846f;
static const float idMath_M_DEG2RAD = 3.14159265358979323846f / 180.0f;

static float idMath_Sin16( float a ) {
    float s;

    if ( ( a < 0.0f ) || ( a >= idMath_TWO_PI ) ) {
        a -= floorf( a / idMath_TWO_PI ) * idMath_TWO_PI;
    }
    if ( a < idMath_PI ) {
        if ( a > idMath_HALF_PI ) {
            a = idMath_PI - a;
        }
    } else {
        if ( a > idMath_PI + idMath_HALF_PI ) {
            a = a - idMath_TWO_PI;
        } else {
            a = idMath_PI - a;
        }
    }
    s = a * a;
    return a * ( ( ( ( ( -2.39e-08f * s + 2.7526e-06f ) * s - 1.98409e-04f ) * s + 8.3333315e-03f ) * s - 1.666666664e-01f ) * s + 1.0f );
}

static float idMath_Cos16( float a ) {
    float s, d;

    if ( ( a < 0.0f ) || ( a >= idMath_TWO_PI ) ) {
        a -= floorf( a / idMath_TWO_PI ) * idMath_TWO_PI;
    }
    if ( a < idMath_PI ) {
        if ( a > idMath_HALF_PI ) {
            a = idMath_PI - a;
            d = -1.0f;
        } else {
            d = 1.0f;
        }
    } else {
        if ( a > idMath_PI + idMath_HALF_PI ) {
            a = a - idMath_TWO_PI;
            d = 1.0f;
        } else {
            a = idMath_PI - a;
            d = -1.0f;
        }
    }
    s = a * a;
    return d * ( ( ( ( ( -2.605e-07f * s + 2.47609e-05f ) * s - 1.3888397e-03f ) * s + 4.16666418e-02f ) * s - 4.999999963e-01f ) * s + 1.0f );
}

static void idMath_SinCos16( float a, float *s, float *c ) {
    float t, d;

    if ( ( a < 0.0f ) || ( a >= idMath_TWO_PI ) ) {
        a -= floorf( a / idMath_TWO_PI ) * idMath_TWO_PI;
    }
    if ( a < idMath_PI ) {
        if ( a > idMath_HALF_PI ) {
            a = idMath_PI - a;
            d = -1.0f;
        } else {
            d = 1.0f;
        }
    } else {
        if ( a > idMath_PI + idMath_HALF_PI ) {
            a = a - idMath_TWO_PI;
            d = 1.0f;
        } else {
            a = idMath_PI - a;
            d = -1.0f;
        }
    }
    t = a * a;
    *s = a * ( ( ( ( ( -2.39e-08f * t + 2.7526e-06f ) * t - 1.98409e-04f ) * t + 8.3333315e-03f ) * t - 1.666666664e-01f ) * t + 1.0f );
    *c = d * ( ( ( ( ( -2.605e-07f * t + 2.47609e-05f ) * t - 1.3888397e-03f ) * t + 4.16666418e-02f ) * t - 4.999999963e-01f ) * t + 1.0f );
}

// idVec3, as float[3]
static float Vec3_Dot( const float a[3], const float b[3] ) { return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]; }

static void Vec3_Normalize( float v[3] ) {
    float sqrLength = v[0] * v[0] + v[1] * v[1] + v[2] * v[2];
    float invLength = 1.0f / sqrtf( sqrLength );        // idMath::InvSqrt
    v[0] *= invLength;
    v[1] *= invLength;
    v[2] *= invLength;
}

// idVec3::ProjectSelfOntoSphere
static void Vec3_ProjectSelfOntoSphere( float v[3], const float radius ) {
    float rsqr = radius * radius;
    float len = sqrtf( v[0] * v[0] + v[1] * v[1] + v[2] * v[2] );
    if ( len  < rsqr * 0.5f ) {
        v[2] = sqrtf( rsqr - len );
    } else {
        v[2] = rsqr / ( 2.0f * sqrtf( len ) );
    }
}

// idRandom: idMath.h's

#pragma mark - DeclParticle.h

typedef enum {
    PDIST_RECT,                // ( sizeX sizeY sizeZ )
    PDIST_CYLINDER,            // ( sizeX sizeY sizeZ )
    PDIST_SPHERE            // ( sizeX sizeY sizeZ ringFraction )
} prtDistribution_t;

typedef enum {
    PDIR_CONE,                // parm0 is the solid cone angle
    PDIR_OUTWARD            // direction is relative to offset from origin, parm0 is an upward bias
} prtDirection_t;

typedef enum {
    PPATH_STANDARD,
    PPATH_HELIX,            // ( sizeX sizeY sizeZ radialSpeed climbSpeed )
    PPATH_FLIES,
    PPATH_ORBIT,
    PPATH_DRIP
} prtCustomPth_t;

typedef enum {
    POR_VIEW,
    POR_AIMED,                // angle and aspect are disregarded
    POR_X,
    POR_Y,
    POR_Z
} prtOrientation_t;

// idParticleParm: its table by name
typedef struct {
    __unsafe_unretained NSString *table;
    float from;
    float to;
} idParticleParm;

typedef struct {
    float   shaderParms[12];
    float   axis[3][3];
} renderEntity_t;

typedef struct {
    int     time;
    float   viewaxis[3][3];
} renderView_t;

typedef struct {
    const renderEntity_t *    renderEnt;            // for shaderParms, etc
    const renderView_t *    renderView;
    int                        index;                // particle number in the system
    float                    frac;                // 0.0 to 1.0
    idRandom                random;
    float                    origin[3];                // dynamic smoke particles can have individual origins and axis
    float                    axis[3][3];

    float                    age;                // in seconds, calculated as fraction * stage->particleLife
    idRandom                originalRandom;        // needed so aimed particles can reset the random for another origin calculation
    float                    animationFrameFrac;    // set by ParticleTexCoords, used to make the cross faded version
} particleGen_t;

typedef struct {
    int                        totalParticles;        // total number of particles, although some may be invisible at a given time
    float                    cycles;                // allows things to oneShot ( 1 cycle ) or run for a set number of cycles

    int                        cycleMsec;            // ( particleLife + deadTime ) in msec
    float                    spawnBunching;        // 0.0 = all come out at first instant, 1.0 = evenly spaced over cycle time
    float                    particleLife;        // total seconds of life for each particle
    float                    timeOffset;            // time offset from system start for the first particle to spawn
    float                    deadTime;            // time after particleLife before respawning
    prtDistribution_t        distributionType;
    float                    distributionParms[4];

    prtDirection_t            directionType;
    float                    directionParms[4];

    idParticleParm            speed;
    float                    gravity;                // can be negative to float up
    BOOL                    worldGravity;            // apply gravity in world space
    BOOL                    randomDistribution;        // randomly orient the quad on emission ( defaults to true )
    BOOL                    entityColor;            // force color from render entity ( fadeColor is still valid )
    prtCustomPth_t            customPathType;        // use custom C code routines for determining the origin
    float                    customPathParms[8];

    float                    offset[3];                // offset from origin to spawn all particles, also applies to customPath
    int                        animationFrames;    // if > 1, subdivide the texture S axis into frames and crossfade
    float                    animationRate;        // frames per second

    float                    initialAngle;        // in degrees, random angle is used if zero ( default )
    idParticleParm            rotationSpeed;        // half the particles will have negative rotation speeds

    prtOrientation_t        orientation;    // view, aimed, or axis fixed
    float                    orientationParms[4];

    idParticleParm            size;
    idParticleParm            aspect;                // greater than 1 makes the T axis longer

    float                    color[4];
    float                    fadeColor[4];            // either 0 0 0 0 for additive, or 1 1 1 0 for blended materials
    float                    fadeInFraction;        // in 0.0 to 1.0 range
    float                    fadeOutFraction;    // in 0.0 to 1.0 range
    float                    fadeIndexFraction;    // in 0.0 to 1.0 range, causes later index smokes to be more faded

    BOOL                    hidden;                // for editor use

    float                    boundsExpansion;    // user tweak to fix poorly calculated bounds

    float                    bounds[6];            // derived
} idParticleStage;

@interface UDParticleSurface () {
@public
    NSMutableData *vertData;
    NSData *indexData;
    float parms[12];
}
@property (nonatomic, copy, readwrite) NSString *material;
@property (nonatomic, readwrite) NSInteger stageIndex;
@property (nonatomic, readwrite) int numVerts;
@end

@implementation UDParticleSurface

- (const UDDrawVert *)verts {
    return vertData.bytes;
}

- (const float *)shaderParms {
    return parms;
}

- (const int *)indexes {
    return indexData.bytes;
}

- (int)numIndexes {
    return (int)( indexData.length / sizeof( int ) );
}

+ (instancetype)surfaceWithMaterial:(NSString *)material verts:(const UDDrawVert *)verts numVerts:(int)numVerts
                            indexes:(const int *)indexes numIndexes:(int)numIndexes
                        shaderParms:(const float *)shaderParms {
    UDParticleSurface *surf = [self surfaceWithMaterial:material verts:verts numVerts:numVerts shaderParms:shaderParms];
    surf->indexData = [NSData dataWithBytes:indexes length:(NSUInteger)numIndexes * sizeof( int )];
    return surf;
}

+ (instancetype)surfaceWithMaterial:(NSString *)material verts:(const UDDrawVert *)verts numVerts:(int)numVerts
                        shaderParms:(const float *)shaderParms {
    UDParticleSurface *surf = [[UDParticleSurface alloc] init];
    surf.material = material;
    surf.stageIndex = -1;
    surf->vertData = [NSMutableData dataWithBytes:verts length:(NSUInteger)numVerts * sizeof( UDDrawVert )];
    surf.numVerts = numVerts;
    memcpy( surf->parms, shaderParms, sizeof( surf->parms ) );
    return surf;
}

@end

@interface UDParticleModel () {
    idParticleStage *stages;
    int numStages;
}
@property (nonatomic, strong, nullable) idDeclManager *declManager;
@property (nonatomic, copy) NSArray<NSString *> *materials;
@property (nonatomic, copy) NSArray<NSString *> *tableNames;   // the parms' tables, held
@end

@implementation UDParticleModel

#pragma mark - idParticleParm

/*
================
idParticleParm::Eval
================
*/
- (float)eval:(const idParticleParm *)parm frac:(float)frac random:(idRandom *)rand {
    if ( parm->table ) {
        return [UDDeclTable ud_lookup:frac inTableNamed:parm->table declManager:self.declManager];
    }
    return parm->from + frac * ( parm->to - parm->from );
}

/*
================
idParticleParm::Integrate
================
*/
- (float)integrate:(const idParticleParm *)parm frac:(float)frac random:(idRandom *)rand {
    if ( parm->table ) {
        // common->Printf( "idParticleParm::Integrate: can't integrate tables\n" );
        return 0;
    }
    return ( parm->from + frac * ( parm->to - parm->from ) * 0.5f ) * frac;
}

#pragma mark - Our stages as idParticleStage

- (instancetype)initWithStages:(NSArray<UDParticleStage *> *)source declManager:(idDeclManager *)declManager {
    self = [super init];
    if (self) {
        _declManager = declManager;
        numStages = (int)source.count;
        stages = calloc( MAX( numStages, 1 ), sizeof( idParticleStage ) );
        NSMutableArray<NSString *> *materials = [NSMutableArray array];
        NSMutableArray<NSString *> *tables = [NSMutableArray array];
        for (int i = 0; i < numStages; i++) {
            UDParticleStage *from = source[(NSUInteger)i];
            idParticleStage *stage = &stages[i];
            [materials addObject:from.material ?: @""];
            stage->totalParticles = from.totalParticles;
            stage->cycles = from.cycles;
            stage->spawnBunching = from.spawnBunching;
            stage->particleLife = from.particleLife;
            stage->timeOffset = from.timeOffset;
            stage->deadTime = from.deadTime;
            stage->distributionType = (prtDistribution_t)from.distributionType;
            UDStringToFloats( from.distributionParms, stage->distributionParms, 4 );
            stage->directionType = (prtDirection_t)from.directionType;
            UDStringToFloats( from.directionParms, stage->directionParms, 4 );
            stage->orientation = (prtOrientation_t)from.orientation;
            UDStringToFloats( from.orientationParms, stage->orientationParms, 4 );
            stage->customPathType = (prtCustomPth_t)from.customPathType;
            UDStringToFloats( from.customPathParms, stage->customPathParms, 8 );
            struct { idParticleParm *parm; __unsafe_unretained NSString *table; float from, to; } parms[] = {
                { &stage->speed, from.speedTable, from.speedFrom, from.speedTo },
                { &stage->rotationSpeed, from.rotationTable, from.rotationFrom, from.rotationTo },
                { &stage->size, from.sizeTable, from.sizeFrom, from.sizeTo },
                { &stage->aspect, from.aspectTable, from.aspectFrom, from.aspectTo },
            };
            for (size_t p = 0; p < sizeof( parms ) / sizeof( parms[0] ); p++) {
                NSString *table = parms[p].table.length > 0 ? [parms[p].table copy] : nil;
                if (table != nil) [tables addObject:table];
                parms[p].parm->table = table;
                parms[p].parm->from = parms[p].from;
                parms[p].parm->to = parms[p].to;
            }
            stage->gravity = from.gravity;
            stage->worldGravity = from.worldGravity;
            stage->randomDistribution = from.randomDistribution;
            stage->entityColor = from.entityColor;
            UDStringToFloats( from.offset, stage->offset, 3 );
            stage->animationFrames = from.animationFrames;
            stage->animationRate = from.animationRate;
            stage->initialAngle = from.initialAngle;
            UDStringToFloats( from.color, stage->color, 4 );
            UDStringToFloats( from.fadeColor, stage->fadeColor, 4 );
            stage->fadeInFraction = from.fadeInFraction;
            stage->fadeOutFraction = from.fadeOutFraction;
            stage->fadeIndexFraction = from.fadeIndexFraction;
            stage->boundsExpansion = from.boundsExpansion;
            stage->hidden = from.hidden;
            // idDeclParticle::ParseParticleStage
            stage->cycleMsec = ( stage->particleLife + stage->deadTime ) * 1000;
            [self getStageBounds:stage];
        }
        _materials = materials;
        _tableNames = tables;
    }
    return self;
}

- (void)dealloc {
    free( stages );
}

#pragma mark - idParticleStage

/*
================
idParticleStage::NumQuadsPerParticle

includes trails and cross faded animations
================
*/
static int NumQuadsPerParticle( const idParticleStage *stage ) {
    int    count = 1;

    if ( stage->orientation == POR_AIMED ) {
        int    trails = (int)( stage->orientationParms[0] );        // idMath::Ftoi
        // each trail stage will add an extra quad
        count *= ( 1 + trails );
    }

    // if we are doing strip-animation, we need to double the number and cross fade them
    if ( stage->animationFrames > 1 ) {
        count *= 2;
    }

    return count;
}

/*
===============
idParticleStage::ParticleOrigin
===============
*/
- (void)particleOrigin:(const idParticleStage *)stage gen:(particleGen_t *)g origin:(float [3])origin {
    if ( stage->customPathType == PPATH_STANDARD ) {
        //
        // find intial origin distribution
        //
        float radiusSqr, angle1, angle2;

        switch( stage->distributionType ) {
            case PDIST_RECT: {    // ( sizeX sizeY sizeZ )
                origin[0] = ( ( stage->randomDistribution ) ? idRandom_CRandomFloat( &g->random ) : 1.0f ) * stage->distributionParms[0];
                origin[1] = ( ( stage->randomDistribution ) ? idRandom_CRandomFloat( &g->random ) : 1.0f ) * stage->distributionParms[1];
                origin[2] = ( ( stage->randomDistribution ) ? idRandom_CRandomFloat( &g->random ) : 1.0f ) * stage->distributionParms[2];
                break;
            }
            case PDIST_CYLINDER: {    // ( sizeX sizeY sizeZ ringFraction )
                angle1 = ( ( stage->randomDistribution ) ? idRandom_CRandomFloat( &g->random ) : 1.0f ) * idMath_TWO_PI;

                idMath_SinCos16( angle1, &origin[0], &origin[1] );
                origin[2] = ( ( stage->randomDistribution ) ? idRandom_CRandomFloat( &g->random ) : 1.0f );

                // reproject points that are inside the ringFraction to the outer band
                if ( stage->distributionParms[3] > 0.0f ) {
                    radiusSqr = origin[0] * origin[0] + origin[1] * origin[1];
                    if ( radiusSqr < stage->distributionParms[3] * stage->distributionParms[3] ) {
                        // if we are inside the inner reject zone, rescale to put it out into the good zone
                        float f = sqrtf( radiusSqr ) / stage->distributionParms[3];
                        float invf = 1.0f / f;
                        float newRadius = stage->distributionParms[3] + f * ( 1.0f - stage->distributionParms[3] );
                        float rescale = invf * newRadius;

                        origin[0] *= rescale;
                        origin[1] *= rescale;
                    }
                }
                origin[0] *= stage->distributionParms[0];
                origin[1] *= stage->distributionParms[1];
                origin[2] *= stage->distributionParms[2];
                break;
            }
            case PDIST_SPHERE: {    // ( sizeX sizeY sizeZ ringFraction )
                // iterating with rejection is the only way to get an even distribution over a sphere
                if ( stage->randomDistribution ) {
                    do {
                        origin[0] = idRandom_CRandomFloat( &g->random );
                        origin[1] = idRandom_CRandomFloat( &g->random );
                        origin[2] = idRandom_CRandomFloat( &g->random );
                        radiusSqr = origin[0] * origin[0] + origin[1] * origin[1] + origin[2] * origin[2];
                    } while( radiusSqr > 1.0f );
                } else {
                    origin[0] = origin[1] = origin[2] = 1.0f;
                    radiusSqr = 3.0f;
                }

                if ( stage->distributionParms[3] > 0.0f ) {
                    // we could iterate until we got something that also satisfied ringFraction,
                    // but for narrow rings that could be a lot of work, so reproject inside points instead
                    if ( radiusSqr < stage->distributionParms[3] * stage->distributionParms[3] ) {
                        // if we are inside the inner reject zone, rescale to put it out into the good zone
                        float f = sqrtf( radiusSqr ) / stage->distributionParms[3];
                        float invf = 1.0f / f;
                        float newRadius = stage->distributionParms[3] + f * ( 1.0f - stage->distributionParms[3] );
                        float rescale = invf * newRadius;

                        origin[0] *= rescale;
                        origin[1] *= rescale;
                        origin[2] *= rescale;
                    }
                }
                origin[0] *= stage->distributionParms[0];
                origin[1] *= stage->distributionParms[1];
                origin[2] *= stage->distributionParms[2];
                break;
            }
        }

        // offset will effect all particle origin types
        // add this before the velocity and gravity additions
        origin[0] += stage->offset[0];
        origin[1] += stage->offset[1];
        origin[2] += stage->offset[2];

        //
        // add the velocity over time
        //
        float    dir[3] = { 0, 0, 0 };

        switch( stage->directionType ) {
            case PDIR_CONE: {
                // angle is the full angle, so 360 degrees is any spherical direction
                angle1 = idRandom_CRandomFloat( &g->random ) * stage->directionParms[0] * idMath_M_DEG2RAD;
                angle2 = idRandom_CRandomFloat( &g->random ) * idMath_PI;

                float s1, c1, s2, c2;
                idMath_SinCos16( angle1, &s1, &c1 );
                idMath_SinCos16( angle2, &s2, &c2 );

                dir[0] = s1 * c2;
                dir[1] = s1 * s2;
                dir[2] = c1;
                break;
            }
            case PDIR_OUTWARD: {
                dir[0] = origin[0];
                dir[1] = origin[1];
                dir[2] = origin[2];
                Vec3_Normalize( dir );
                dir[2] += stage->directionParms[0];
                break;
            default:
                // common->Error( "idParticleStage::ParticleOrigin: bad direction" );
                return;
            }
        }

        // add speed
        float iSpeed = [self integrate:&stage->speed frac:g->frac random:&g->random];
        origin[0] += dir[0] * iSpeed * stage->particleLife;
        origin[1] += dir[1] * iSpeed * stage->particleLife;
        origin[2] += dir[2] * iSpeed * stage->particleLife;

    } else {
        //
        // custom paths completely override both the origin and velocity calculations, but still
        // use the standard gravity
        //
        float angle1, angle2, speed1, speed2;
        switch( stage->customPathType ) {
            case PPATH_HELIX: {        // ( sizeX sizeY sizeZ radialSpeed axialSpeed )
                speed1 = idRandom_CRandomFloat( &g->random );
                speed2 = idRandom_CRandomFloat( &g->random );
                angle1 = idRandom_RandomFloat( &g->random ) * idMath_TWO_PI + stage->customPathParms[3] * speed1 * g->age;

                float s1, c1;
                idMath_SinCos16( angle1, &s1, &c1 );

                origin[0] = c1 * stage->customPathParms[0];
                origin[1] = s1 * stage->customPathParms[1];
                origin[2] = idRandom_RandomFloat( &g->random ) * stage->customPathParms[2] + stage->customPathParms[4] * speed2 * g->age;
                break;
            }
            case PPATH_FLIES: {        // ( radialSpeed axialSpeed size )
                speed1 = idMath_ClampFloat( 0.4f, 1.0f, idRandom_CRandomFloat( &g->random ) );
                speed2 = idMath_ClampFloat( 0.4f, 1.0f, idRandom_CRandomFloat( &g->random ) );
                angle1 = idRandom_RandomFloat( &g->random ) * idMath_PI * 2 + stage->customPathParms[0] * speed1 * g->age;
                angle2 = idRandom_RandomFloat( &g->random ) * idMath_PI * 2 + stage->customPathParms[1] * speed1 * g->age;

                float s1, c1, s2, c2;
                idMath_SinCos16( angle1, &s1, &c1 );
                idMath_SinCos16( angle2, &s2, &c2 );

                origin[0] = c1 * c2;
                origin[1] = s1 * c2;
                origin[2] = -s2;
                origin[0] *= stage->customPathParms[2];
                origin[1] *= stage->customPathParms[2];
                origin[2] *= stage->customPathParms[2];
                break;
            }
            case PPATH_ORBIT: {        // ( radius speed axis )
                angle1 = idRandom_RandomFloat( &g->random ) * idMath_TWO_PI + stage->customPathParms[1] * g->age;

                float s1, c1;
                idMath_SinCos16( angle1, &s1, &c1 );

                origin[0] = c1 * stage->customPathParms[0];
                origin[1] = s1 * stage->customPathParms[0];
                Vec3_ProjectSelfOntoSphere( origin, stage->customPathParms[0] );
                break;
            }
            case PPATH_DRIP: {        // ( speed )
                origin[0] = 0.0f;
                origin[1] = 0.0f;
                origin[2] = -( g->age * stage->customPathParms[0] );
                break;
            }
            default: {
                // common->Error( "idParticleStage::ParticleOrigin: bad customPathType" );
                break;
            }
        }

        origin[0] += stage->offset[0];
        origin[1] += stage->offset[1];
        origin[2] += stage->offset[2];
    }

    // adjust for the per-particle smoke offset
    // origin *= g->axis (idVec3 * idMat3: the rows, weighted)
    float rotated[3];
    for ( int i = 0; i < 3; i++ ) {
        rotated[i] = origin[0] * g->axis[0][i] + origin[1] * g->axis[1][i] + origin[2] * g->axis[2][i];
    }
    origin[0] = rotated[0] + g->origin[0];
    origin[1] = rotated[1] + g->origin[1];
    origin[2] = rotated[2] + g->origin[2];

    // add gravity after adjusting for axis
    if ( stage->worldGravity ) {
        // gra *= g->renderEnt->axis.Transpose()
        float gra[3] = { 0, 0, -stage->gravity };
        float worldGra[3];
        for ( int i = 0; i < 3; i++ ) {
            worldGra[i] = gra[0] * g->renderEnt->axis[i][0] + gra[1] * g->renderEnt->axis[i][1] + gra[2] * g->renderEnt->axis[i][2];
        }
        origin[0] += worldGra[0] * g->age * g->age;
        origin[1] += worldGra[1] * g->age * g->age;
        origin[2] += worldGra[2] * g->age * g->age;
    } else {
        origin[2] -= stage->gravity * g->age * g->age;
    }
}

/// idMat3::ProjectVector: each of @a axis' rows' dot with @a src.
static void Mat3_ProjectVector( const float axis[3][3], const float src[3], float dst[3] ) {
    dst[0] = Vec3_Dot( src, axis[0] );
    dst[1] = Vec3_Dot( src, axis[1] );
    dst[2] = Vec3_Dot( src, axis[2] );
}

/*
==================
idParticleStage::ParticleVerts
==================
*/
- (int)particleVerts:(const idParticleStage *)stage gen:(particleGen_t *)g origin:(const float [3])origin verts:(UDDrawVert *)verts {
    float    psize = [self eval:&stage->size frac:g->frac random:&g->random];
    float    paspect = [self eval:&stage->aspect frac:g->frac random:&g->random];

    float    width = psize;
    float    height = psize * paspect;

    float    left[3], up[3];

    if ( stage->orientation == POR_AIMED ) {
        // reset the values to an earlier time to get a previous origin
        idRandom    currentRandom = g->random;
        float        currentAge = g->age;
        float        currentFrac = g->frac;
        UDDrawVert *verts_p = verts;
        float        stepOrigin[3] = { origin[0], origin[1], origin[2] };
        float        stepLeft[3] = { 0, 0, 0 };
        int            numTrails = (int)( stage->orientationParms[0] );     // idMath::Ftoi
        float        trailTime = stage->orientationParms[1];

        if ( trailTime == 0 ) {
            trailTime = 0.5f;
        }

        float height = 1.0f / ( 1 + numTrails );
        float t = 0;

        for ( int i = 0 ; i <= numTrails ; i++ ) {
            g->random = g->originalRandom;
            g->age = currentAge - ( i + 1 ) * trailTime / ( numTrails + 1 );    // time to back up
            g->frac = g->age / stage->particleLife;

            float    oldOrigin[3];
            [self particleOrigin:stage gen:g origin:oldOrigin];

            up[0] = stepOrigin[0] - oldOrigin[0];    // along the direction of travel
            up[1] = stepOrigin[1] - oldOrigin[1];
            up[2] = stepOrigin[2] - oldOrigin[2];

            float    forwardDir[3];
            Mat3_ProjectVector( g->renderEnt->axis, g->renderView->viewaxis[0], forwardDir );

            float upDotForward = Vec3_Dot( up, forwardDir );
            up[0] -= upDotForward * forwardDir[0];
            up[1] -= upDotForward * forwardDir[1];
            up[2] -= upDotForward * forwardDir[2];

            Vec3_Normalize( up );


            // left = up.Cross( forwardDir )
            left[0] = up[1] * forwardDir[2] - up[2] * forwardDir[1];
            left[1] = up[2] * forwardDir[0] - up[0] * forwardDir[2];
            left[2] = up[0] * forwardDir[1] - up[1] * forwardDir[0];
            left[0] *= psize;
            left[1] *= psize;
            left[2] *= psize;

            verts_p[0] = verts[0];
            verts_p[1] = verts[1];
            verts_p[2] = verts[2];
            verts_p[3] = verts[3];

            for ( int k = 0; k < 3; k++ ) {
                if ( i == 0 ) {
                    verts_p[0].xyz[k] = stepOrigin[k] - left[k];
                    verts_p[1].xyz[k] = stepOrigin[k] + left[k];
                } else {
                    verts_p[0].xyz[k] = stepOrigin[k] - stepLeft[k];
                    verts_p[1].xyz[k] = stepOrigin[k] + stepLeft[k];
                }
                verts_p[2].xyz[k] = oldOrigin[k] - left[k];
                verts_p[3].xyz[k] = oldOrigin[k] + left[k];
            }

            // modify texcoords
            verts_p[0].st[0] = verts[0].st[0];
            verts_p[0].st[1] = t;

            verts_p[1].st[0] = verts[1].st[0];
            verts_p[1].st[1] = t;

            verts_p[2].st[0] = verts[2].st[0];
            verts_p[2].st[1] = t+height;

            verts_p[3].st[0] = verts[3].st[0];
            verts_p[3].st[1] = t+height;

            t += height;

            verts_p += 4;

            stepOrigin[0] = oldOrigin[0];
            stepOrigin[1] = oldOrigin[1];
            stepOrigin[2] = oldOrigin[2];
            stepLeft[0] = left[0];
            stepLeft[1] = left[1];
            stepLeft[2] = left[2];
        }

        g->random = currentRandom;
        g->age = currentAge;
        g->frac = currentFrac;

        return 4 * (numTrails+1);
    }

    //
    // constant rotation
    //
    float    angle;

    angle = ( stage->initialAngle ) ? stage->initialAngle : 360 * idRandom_RandomFloat( &g->random );

    float    angleMove = [self integrate:&stage->rotationSpeed frac:g->frac random:&g->random] * stage->particleLife;
    // have hald the particles rotate each way
    if ( g->index & 1 ) {
        angle += angleMove;
    } else {
        angle -= angleMove;
    }

    angle = angle / 180 * idMath_PI;
    float c = idMath_Cos16( angle );
    float s = idMath_Sin16( angle );

    if ( stage->orientation  == POR_Z ) {
        // oriented in entity space
        left[0] = s;
        left[1] = c;
        left[2] = 0;
        up[0] = c;
        up[1] = -s;
        up[2] = 0;
    } else if ( stage->orientation == POR_X ) {
        // oriented in entity space
        left[0] = 0;
        left[1] = c;
        left[2] = s;
        up[0] = 0;
        up[1] = -s;
        up[2] = c;
    } else if ( stage->orientation == POR_Y ) {
        // oriented in entity space
        left[0] = c;
        left[1] = 0;
        left[2] = s;
        up[0] = -s;
        up[1] = 0;
        up[2] = c;
    } else {
        // oriented in viewer space
        float    entityLeft[3], entityUp[3];

        Mat3_ProjectVector( g->renderEnt->axis, g->renderView->viewaxis[1], entityLeft );
        Mat3_ProjectVector( g->renderEnt->axis, g->renderView->viewaxis[2], entityUp );

        for ( int k = 0; k < 3; k++ ) {
            left[k] = entityLeft[k] * c + entityUp[k] * s;
            up[k] = entityUp[k] * c - entityLeft[k] * s;
        }
    }

    for ( int k = 0; k < 3; k++ ) {
        left[k] *= width;
        up[k] *= height;

        verts[0].xyz[k] = origin[k] - left[k] + up[k];
        verts[1].xyz[k] = origin[k] + left[k] + up[k];
        verts[2].xyz[k] = origin[k] - left[k] - up[k];
        verts[3].xyz[k] = origin[k] + left[k] - up[k];
    }

    return 4;
}

/*
==================
idParticleStage::ParticleTexCoords
==================
*/
static void ParticleTexCoords( const idParticleStage *stage, particleGen_t *g, UDDrawVert *verts ) {
    float    s, width;
    float    t, height;

    if ( stage->animationFrames > 1 ) {
        width = 1.0f / stage->animationFrames;
        float    floatFrame;
        if ( stage->animationRate ) {
            // explicit, cycling animation
            floatFrame = g->age * stage->animationRate;
        } else {
            // single animation cycle over the life of the particle
            floatFrame = g->frac * stage->animationFrames;
        }
        int    intFrame = (int)floatFrame;
        g->animationFrameFrac = floatFrame - intFrame;
        s = width * intFrame;
    } else {
        s = 0.0f;
        width = 1.0f;
    }

    t = 0.0f;
    height = 1.0f;

    verts[0].st[0] = s;
    verts[0].st[1] = t;

    verts[1].st[0] = s+width;
    verts[1].st[1] = t;

    verts[2].st[0] = s;
    verts[2].st[1] = t+height;

    verts[3].st[0] = s+width;
    verts[3].st[1] = t+height;
}

/*
==================
idParticleStage::ParticleColors
==================
*/
static void ParticleColors( const idParticleStage *stage, particleGen_t *g, UDDrawVert *verts ) {
    float    fadeFraction = 1.0f;

    // most particles fade in at the beginning and fade out at the end
    if ( g->frac < stage->fadeInFraction ) {
        fadeFraction *= ( g->frac / stage->fadeInFraction );
    }
    if ( 1.0f - g->frac < stage->fadeOutFraction ) {
        fadeFraction *= ( ( 1.0f - g->frac ) / stage->fadeOutFraction );
    }

    // individual gun smoke particles get more and more faded as the
    // cycle goes on (note that totalParticles won't be correct for a surface-particle deform)
    if ( stage->fadeIndexFraction ) {
        float    indexFrac = ( stage->totalParticles - g->index ) / (float)stage->totalParticles;
        if ( indexFrac < stage->fadeIndexFraction ) {
            fadeFraction *= indexFrac / stage->fadeIndexFraction;
        }
    }

    for ( int i = 0 ; i < 4 ; i++ ) {
        float    fcolor = ( ( stage->entityColor ) ? g->renderEnt->shaderParms[i] : stage->color[i] ) * fadeFraction + stage->fadeColor[i] * ( 1.0f - fadeFraction );
        int        icolor = (int)( fcolor * 255.0f );           // idMath::FtoiFast
        if ( icolor < 0 ) {
            icolor = 0;
        } else if ( icolor > 255 ) {
            icolor = 255;
        }
        verts[0].color[i] =
        verts[1].color[i] =
        verts[2].color[i] =
        verts[3].color[i] = icolor;
    }
}

/*
================
idParticleStage::CreateParticle

Returns 0 if no particle is created because it is completely faded out
Returns 4 if a normal quad is created
Returns 8 if two cross faded quads are created

Vertex order is:

0 1
2 3
================
*/
- (int)createParticle:(const idParticleStage *)stage gen:(particleGen_t *)g verts:(UDDrawVert *)verts {
    float    origin[3];

    memset( verts, 0, 4 * sizeof( UDDrawVert ) );        // idDrawVert::Clear

    ParticleColors( stage, g, verts );

    // if we are completely faded out, kill the particle
    if ( verts[0].color[0] == 0 && verts[0].color[1] == 0 && verts[0].color[2] == 0 && verts[0].color[3] == 0 ) {
        return 0;
    }

    [self particleOrigin:stage gen:g origin:origin];

    ParticleTexCoords( stage, g, verts );

    int    numVerts = [self particleVerts:stage gen:g origin:origin verts:verts];

    if ( stage->animationFrames <= 1 ) {
        return numVerts;
    }

    // if we are doing strip-animation, we need to double the quad and cross fade it
    float    width = 1.0f / stage->animationFrames;
    float    frac = g->animationFrameFrac;
    float    iFrac = 1.0f - frac;
    for ( int i = 0 ; i < numVerts ; i++ ) {
        verts[numVerts + i] = verts[i];

        verts[numVerts + i].st[0] += width;

        verts[numVerts + i].color[0] *= frac;
        verts[numVerts + i].color[1] *= frac;
        verts[numVerts + i].color[2] *= frac;
        verts[numVerts + i].color[3] *= frac;

        verts[i].color[0] *= iFrac;
        verts[i].color[1] *= iFrac;
        verts[i].color[2] *= iFrac;
        verts[i].color[3] *= iFrac;
    }

    return numVerts * 2;
}

static void UDIdentity( float axis[3][3] ) {
    memset( axis, 0, 9 * sizeof( float ) );
    axis[0][0] = axis[1][1] = axis[2][2] = 1;
}

/*
=====================
idDeclParticle::GetStageBounds
=====================
*/
- (void)getStageBounds:(idParticleStage *)stage {
    float *bounds = stage->bounds;
    // idBounds::Clear
    bounds[0] = bounds[1] = bounds[2] = INFINITY;
    bounds[3] = bounds[4] = bounds[5] = -INFINITY;

    // this isn't absolutely guaranteed, but it should be close

    particleGen_t g;
    memset( &g, 0, sizeof( g ) );

    renderEntity_t    renderEntity;
    memset( &renderEntity, 0, sizeof( renderEntity ) );
    UDIdentity( renderEntity.axis );

    renderView_t    renderView;
    memset( &renderView, 0, sizeof( renderView ) );
    UDIdentity( renderView.viewaxis );

    g.renderEnt = &renderEntity;
    g.renderView = &renderView;
    UDIdentity( g.axis );

    idRandom    steppingRandom;
    idRandom_SetSeed( &steppingRandom, 0 );

    // just step through a lot of possible particles as a representative sampling
    for ( int i = 0 ; i < 1000 ; i++ ) {
        g.random = g.originalRandom = steppingRandom;

        int    maxMsec = stage->particleLife * 1000;
        for ( int inCycleTime = 0 ; inCycleTime < maxMsec ; inCycleTime += 16 ) {

            // make sure we get the very last tic, which may make up an extreme edge
            if ( inCycleTime + 16 > maxMsec ) {
                inCycleTime = maxMsec - 1;
            }

            g.frac = (float)inCycleTime / ( stage->particleLife * 1000 );
            g.age = inCycleTime * 0.001f;

            // if the particle doesn't get drawn because it is faded out or beyond a kill region,
            // don't increment the verts

            float    origin[3];
            [self particleOrigin:stage gen:&g origin:origin];
            // idBounds::AddPoint
            for ( int k = 0; k < 3; k++ ) {
                if ( origin[k] < bounds[k] ) bounds[k] = origin[k];
                if ( origin[k] > bounds[3 + k] ) bounds[3 + k] = origin[k];
            }
        }
    }

    // find the max size
    float    maxSize = 0;

    for ( float f = 0; f <= 1.0f; f += 1.0f / 64 ) {
        float size = [self eval:&stage->size frac:f random:&steppingRandom];
        float aspect = [self eval:&stage->aspect frac:f random:&steppingRandom];
        if ( aspect > 1 ) {
            size *= aspect;
        }
        if ( size > maxSize ) {
            maxSize = size;
        }
    }

    maxSize += 8;    // just for good measure
    // users can specify a per-stage bounds expansion to handle odd cases
    // idBounds::ExpandSelf
    for ( int k = 0; k < 3; k++ ) {
        bounds[k] -= maxSize + stage->boundsExpansion;
        bounds[3 + k] += maxSize + stage->boundsExpansion;
    }
}

- (void)getBounds:(float [6])bounds {
    bounds[0] = bounds[1] = bounds[2] = INFINITY;
    bounds[3] = bounds[4] = bounds[5] = -INFINITY;
    for ( int i = 0; i < numStages; i++ ) {
        if ( stages[i].hidden || stages[i].particleLife <= 0 ) continue;
        for ( int k = 0; k < 3; k++ ) {
            bounds[k] = MIN( bounds[k], stages[i].bounds[k] );
            bounds[3 + k] = MAX( bounds[3 + k], stages[i].bounds[3 + k] );
        }
    }
    if ( bounds[0] > bounds[3] ) {
        for ( int k = 0; k < 6; k++ ) bounds[k] = 0;
    }
}

#pragma mark - idRenderModelPrt

#define SHADERPARM_TIMEOFFSET           4
#define SHADERPARM_DIVERSITY            5
#define SHADERPARM_PARTICLE_STOPTIME    8

/*
====================
idRenderModelPrt::InstantiateDynamicModel
====================
*/
- (NSArray<UDParticleSurface *> *)surfacesAtTime:(int)msec viewAxis:(const float [3][3])viewAxis {
    // an entity's color, its shaderParms 0 to 3, white; at the origin, unrotated
    float shaderParms[12] = { 1, 1, 1, 1 };
    float origin[3] = { 0, 0, 0 };
    float axis[3][3];
    UDIdentity( axis );
    return [self surfacesAtTime:msec viewAxis:viewAxis shaderParms:shaderParms origin:origin axis:axis];
}

- (NSArray<UDParticleSurface *> *)surfacesAtTime:(int)msec viewAxis:(const float [3][3])viewAxis
                                     shaderParms:(const float *)shaderParms
                                          origin:(const float [3])entityOrigin
                                            axis:(const float [3][3])entityAxis {
    NSMutableArray<UDParticleSurface *> *surfaces = [NSMutableArray array];

    renderEntity_t renderEntityStorage;
    memset( &renderEntityStorage, 0, sizeof( renderEntityStorage ) );
    memcpy( renderEntityStorage.axis, entityAxis, sizeof( renderEntityStorage.axis ) );
    memcpy( renderEntityStorage.shaderParms, shaderParms, sizeof( renderEntityStorage.shaderParms ) );
    const renderEntity_t *renderEntity = &renderEntityStorage;

    renderView_t renderView;
    renderView.time = msec;
    memcpy( renderView.viewaxis, viewAxis, sizeof( renderView.viewaxis ) );

    particleGen_t g;
    memset( &g, 0, sizeof( g ) );

    g.renderEnt = renderEntity;
    g.renderView = &renderView;
    g.origin[0] = g.origin[1] = g.origin[2] = 0;
    UDIdentity( g.axis );

    for ( int stageNum = 0; stageNum < numStages; stageNum++ ) {
        idParticleStage *stage = &stages[stageNum];

        if ( self.materials[(NSUInteger)stageNum].length == 0 ) {
            continue;
        }
        if ( !stage->cycleMsec ) {
            continue;
        }
        if ( stage->hidden ) {        // just for gui particle editor use
            continue;
        }

        idRandom steppingRandom, steppingRandom2;

        int stageAge = g.renderView->time + renderEntity->shaderParms[SHADERPARM_TIMEOFFSET] * 1000 - stage->timeOffset * 1000;
        int    stageCycle = stageAge / stage->cycleMsec;

        // some particles will be in this cycle, some will be in the previous cycle
        idRandom_SetSeed( &steppingRandom, (( stageCycle << 10 ) & idRandom_MAX_RAND) ^ (int)( renderEntity->shaderParms[SHADERPARM_DIVERSITY] * idRandom_MAX_RAND )  );
        idRandom_SetSeed( &steppingRandom2, (( (stageCycle-1) << 10 ) & idRandom_MAX_RAND) ^ (int)( renderEntity->shaderParms[SHADERPARM_DIVERSITY] * idRandom_MAX_RAND )  );

        int    count = stage->totalParticles * NumQuadsPerParticle( stage );

        UDParticleSurface *surf = [[UDParticleSurface alloc] init];
        surf.material = self.materials[(NSUInteger)stageNum];
        surf.stageIndex = stageNum;
        memcpy( surf->parms, shaderParms, sizeof( surf->parms ) );
        surf->vertData = [NSMutableData dataWithLength:(NSUInteger)MAX( 4 * count, 0 ) * sizeof( UDDrawVert )];

        int numVerts = 0;
        UDDrawVert *verts = surf->vertData.mutableBytes;

        for ( int index = 0; index < stage->totalParticles; index++ ) {
            g.index = index;

            // bump the random
            idRandom_RandomInt( &steppingRandom );
            idRandom_RandomInt( &steppingRandom2 );

            // calculate local age for this index
            int    bunchOffset = stage->particleLife * 1000 * stage->spawnBunching * index / stage->totalParticles;

            int particleAge = stageAge - bunchOffset;
            int    particleCycle = particleAge / stage->cycleMsec;
            if ( particleCycle < 0 ) {
                // before the particleSystem spawned
                continue;
            }
            if ( stage->cycles && particleCycle >= stage->cycles ) {
                // cycled systems will only run cycle times
                continue;
            }

            if ( particleCycle == stageCycle ) {
                g.random = steppingRandom;
            } else {
                g.random = steppingRandom2;
            }

            int    inCycleTime = particleAge - particleCycle * stage->cycleMsec;

            if ( renderEntity->shaderParms[SHADERPARM_PARTICLE_STOPTIME] &&
                g.renderView->time - inCycleTime >= renderEntity->shaderParms[SHADERPARM_PARTICLE_STOPTIME]*1000 ) {
                // don't fire any more particles
                continue;
            }

            // supress particles before or after the age clamp
            g.frac = (float)inCycleTime / ( stage->particleLife * 1000 );
            if ( g.frac < 0.0f ) {
                // yet to be spawned
                continue;
            }
            if ( g.frac > 1.0f ) {
                // this particle is in the deadTime band
                continue;
            }

            // this is needed so aimed particles can calculate origins at different times
            g.originalRandom = g.random;

            g.age = g.frac * stage->particleLife;

            // if the particle doesn't get drawn because it is faded out or beyond a kill region, don't increment the verts
            numVerts += [self createParticle:stage gen:&g verts:verts + numVerts];
        }

        // the renderer's model to world: origin + v * axis
        for ( int v = 0; v < numVerts; v++ ) {
            float *xyz = verts[v].xyz;
            float world[3];
            for ( int k = 0; k < 3; k++ ) {
                world[k] = entityOrigin[k] + xyz[0] * entityAxis[0][k] + xyz[1] * entityAxis[1][k] + xyz[2] * entityAxis[2][k];
            }
            memcpy( xyz, world, sizeof( world ) );
        }

        surf.numVerts = numVerts;
        [surfaces addObject:surf];
    }

    return surfaces;
}

@end
