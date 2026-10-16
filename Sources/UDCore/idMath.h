/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 * idMath.h — what of idLib's math the ports use, ported: idMath's RSqrt and
 * ClampFloat (math/Math.h), idRandom (math/Random.h), idVec2, idVec3,
 * idVec4, idMat3 and idRotation's ToMat3 (math/Vector.h, Matrix.h,
 * Rotation.cpp), idExtrapolate and idInterpolateAccelDecelLinear<idVec4>
 * (math/Extrapolate.h, Interpolate.h), and idRectangle (ui/Rectangle.h).
 * C++'s operators are functions here.
 */

#ifndef ID_MATH_H
#define ID_MATH_H

#import <Foundation/Foundation.h>
#include <math.h>
#include <string.h>

#ifndef DEG2RAD
#define DEG2RAD(a)          ( (a) * ( (float)M_PI / 180.0f ) )
#endif
#ifndef RAD2DEG
#define RAD2DEG(a)          ( (a) * ( 180.0f / (float)M_PI ) )
#endif

#define MATRIX_EPSILON      1e-6

#pragma mark - idMath

/// idMath::RSqrt: the reciprocal square root, approximated as the engine
/// approximates it
static inline float idMath_RSqrt( float x ) {
    int i;
    float y, r;

    y = x * 0.5f;
    memcpy( &i, &x, sizeof( i ) );
    i = 0x5f3759df - ( i >> 1 );
    memcpy( &r, &i, sizeof( r ) );
    r = r * ( 1.5f - r * r * y );
    return r;
}

/// idMath::ClampFloat( min, max, value )
static inline float idMath_ClampFloat( float min, float max, float value ) {
    if ( value < min ) {
        return min;
    }
    if ( value > max ) {
        return max;
    }
    return value;
}

/// idMath::FtoiFast: dhewm3's, the float truncated toward zero
static inline int idMath_FtoiFast( float f ) {
    return (int)f;
}

#pragma mark - idRandom

#define idRandom_MAX_RAND   0x7fff

typedef struct { int seed; } idRandom;

static inline idRandom idRandom_Make( int seed ) { idRandom r = { seed }; return r; }
static inline void idRandom_SetSeed( idRandom *r, int seed ) { r->seed = seed; }
static inline int idRandom_RandomInt( idRandom *r ) {
    r->seed = (int)( 69069u * (unsigned)r->seed + 1u );
    return ( r->seed & idRandom_MAX_RAND );
}
/// RandomInt( max ): in [0, max[
static inline int idRandom_RandomIntMax( idRandom *r, int max ) {
    if ( max == 0 ) {
        return 0;           // avoid divide by zero error
    }
    return idRandom_RandomInt( r ) % max;
}
static inline float idRandom_RandomFloat( idRandom *r ) {
    return ( idRandom_RandomInt( r ) / ( float )( idRandom_MAX_RAND + 1 ) );
}
static inline float idRandom_CRandomFloat( idRandom *r ) {
    return ( 2.0f * ( idRandom_RandomFloat( r ) - 0.5f ) );
}

#pragma mark - idVec2, idVec3, idVec4, idMat3

typedef struct { float x, y; } idVec2;
typedef struct { float x, y, z; } idVec3;
typedef struct { float x, y, z, w; } idVec4;
typedef struct { idVec3 mat[3]; } idMat3;

static inline idVec2 idVec2_Make( float x, float y ) { idVec2 v = { x, y }; return v; }
static inline idVec3 idVec3_Make( float x, float y, float z ) { idVec3 v = { x, y, z }; return v; }
static inline idVec4 idVec4_Make( float x, float y, float z, float w ) { idVec4 v = { x, y, z, w }; return v; }
static inline float *idVec4_Ptr( idVec4 *v ) { return &v->x; }
static inline idVec4 idVec4_Add( idVec4 a, idVec4 b ) { return idVec4_Make( a.x + b.x, a.y + b.y, a.z + b.z, a.w + b.w ); }
static inline idVec4 idVec4_Sub( idVec4 a, idVec4 b ) { return idVec4_Make( a.x - b.x, a.y - b.y, a.z - b.z, a.w - b.w ); }
static inline idVec4 idVec4_Scale( idVec4 a, float f ) { return idVec4_Make( a.x * f, a.y * f, a.z * f, a.w * f ); }

/// idVec2::NormalizeFast
static inline float idVec2_NormalizeFast( idVec2 *v ) {
    float lengthSqr, invLength;

    lengthSqr = v->x * v->x + v->y * v->y;
    invLength = idMath_RSqrt( lengthSqr );
    v->x *= invLength;
    v->y *= invLength;
    return invLength * lengthSqr;
}

extern const idMat3 mat3_identity;
extern const idVec3 vec3_origin;

static inline void idMat3_Identity( idMat3 *m ) { *m = mat3_identity; }

// idMat3::IsIdentity: Compare( mat3_identity, MATRIX_EPSILON )
static inline BOOL idMat3_IsIdentity( const idMat3 *m ) {
    for ( int i = 0; i < 3; i++ ) {
        const idVec3 *a = &m->mat[i], *b = &mat3_identity.mat[i];
        if ( fabsf( a->x - b->x ) > MATRIX_EPSILON || fabsf( a->y - b->y ) > MATRIX_EPSILON || fabsf( a->z - b->z ) > MATRIX_EPSILON ) {
            return NO;
        }
    }
    return YES;
}

// idMat3::operator*=( const idMat3 &a )
static inline void idMat3_MultiplySelf( idMat3 *m, const idMat3 *a ) {
    float *m1Ptr = &m->mat[0].x, dst[3];
    const float *m2Ptr = &a->mat[0].x;
    for ( int i = 0; i < 3; i++ ) {
        for ( int j = 0; j < 3; j++ ) {
            dst[j]  = m1Ptr[0] * m2Ptr[ 0 * 3 + j ]
                    + m1Ptr[1] * m2Ptr[ 1 * 3 + j ]
                    + m1Ptr[2] * m2Ptr[ 2 * 3 + j ];
        }
        m1Ptr[0] = dst[0]; m1Ptr[1] = dst[1]; m1Ptr[2] = dst[2];
        m1Ptr += 3;
    }
}

// idVec3 *= idMat3 (vec * mat, which is mat * vec)
static inline idVec3 idVec3_TimesMat3( idVec3 vec, const idMat3 *m ) {
    return idVec3_Make(
        m->mat[ 0 ].x * vec.x + m->mat[ 1 ].x * vec.y + m->mat[ 2 ].x * vec.z,
        m->mat[ 0 ].y * vec.x + m->mat[ 1 ].y * vec.y + m->mat[ 2 ].y * vec.z,
        m->mat[ 0 ].z * vec.x + m->mat[ 1 ].z * vec.y + m->mat[ 2 ].z * vec.z );
}

/// idRotation::Set( origin, vec, angle ) then ToMat3 (Rotation.cpp).
idMat3 idRotation_ToMat3( idVec3 vec, float angle );

/// idVec2/3/4::ToString( precision 2 ) (idStr::FloatArrayToString)
NSString *idVec2_ToString( idVec2 v );
NSString *idVec3_ToString( idVec3 v );
NSString *idVec4_ToString( idVec4 v );

#pragma mark - idRectangle (ui/Rectangle.h)

typedef struct {
    float x;    // horiz position
    float y;    // vert position
    float w;    // width
    float h;    // height;
} idRectangle;

static inline idRectangle idRectangle_Make( float ix, float iy, float iw, float ih ) { idRectangle r = { ix, iy, iw, ih }; return r; }
static inline float idRectangle_Bottom( const idRectangle *r ) { return r->y + r->h; }
static inline float idRectangle_Right( const idRectangle *r ) { return r->x + r->w; }
static inline void idRectangle_Offset( idRectangle *r, float x, float y ) {
    r->x += x;
    r->y += y;
}
static inline BOOL idRectangle_Contains( const idRectangle *r, float xt, float yt ) {
    if ( r->w == 0.0 && r->h == 0.0 ) {
        return NO;
    }
    if ( xt >= r->x && xt <= idRectangle_Right( r ) && yt >= r->y && yt <= idRectangle_Bottom( r ) ) {
        return YES;
    }
    return NO;
}
static inline idVec4 idRectangle_ToVec4( const idRectangle *r ) { return idVec4_Make( r->x, r->y, r->w, r->h ); }
// idRectangle::operator=( const idVec4 v )
static inline idRectangle idRectangle_FromVec4( idVec4 v ) { return idRectangle_Make( v.x, v.y, v.z, v.w ); }

#pragma mark - Extrapolation, interpolation (math/Extrapolate.h, Interpolate.h)

typedef enum {
    EXTRAPOLATION_NONE          = 0x01, // no extrapolation, covered distance = duration * 0.001 * ( baseSpeed )
    EXTRAPOLATION_LINEAR        = 0x02, // linear extrapolation, covered distance = duration * 0.001 * ( baseSpeed + speed )
    EXTRAPOLATION_ACCELLINEAR   = 0x04, // linear acceleration, covered distance = duration * 0.001 * ( baseSpeed + 0.5 * speed )
    EXTRAPOLATION_DECELLINEAR   = 0x08, // linear deceleration, covered distance = duration * 0.001 * ( baseSpeed + 0.5 * speed )
    EXTRAPOLATION_ACCELSINE     = 0x10, // sinusoidal acceleration, covered distance = duration * 0.001 * ( baseSpeed + sqrt( 0.5 ) * speed )
    EXTRAPOLATION_DECELSINE     = 0x20, // sinusoidal deceleration, covered distance = duration * 0.001 * ( baseSpeed + sqrt( 0.5 ) * speed )
    EXTRAPOLATION_NOSTOP        = 0x40  // do not stop at startTime + duration
} extrapolation_t;

/// idExtrapolate<idVec4>
typedef struct {
    extrapolation_t extrapolationType;
    float           startTime;
    float           duration;
    idVec4          startValue;
    idVec4          baseSpeed;
    idVec4          speed;
    float           currentTime;
    idVec4          currentValue;
} idExtrapolateVec4;

/// idInterpolateAccelDecelLinear<idVec4>
typedef struct {
    float               startTime;
    float               accelTime;
    float               linearTime;
    float               decelTime;
    idVec4              startValue;
    idVec4              endValue;
    idExtrapolateVec4   extrapolate;
} idInterpolateAccelDecelLinearVec4;

void idInterpolateAccelDecelLinear_Construct( idInterpolateAccelDecelLinearVec4 *self );
void idInterpolateAccelDecelLinear_Init( idInterpolateAccelDecelLinearVec4 *self, const float startTime, const float accelTime, const float decelTime, const float duration, idVec4 startValue, idVec4 endValue );
idVec4 idInterpolateAccelDecelLinear_GetCurrentValue( idInterpolateAccelDecelLinearVec4 *self, float time );
static inline BOOL idInterpolateAccelDecelLinear_IsDone( const idInterpolateAccelDecelLinearVec4 *self, float time ) {
    return ( time >= self->startTime + self->accelTime + self->linearTime + self->decelTime );
}
static inline idVec4 idInterpolateAccelDecelLinear_GetEndValue( const idInterpolateAccelDecelLinearVec4 *self ) { return self->endValue; }

#endif
