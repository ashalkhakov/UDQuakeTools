/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 * idMath.m — see idMath.h.
 */

#import <Foundation/Foundation.h>
#include <stdarg.h>
#include <stdio.h>
#include <ctype.h>
#import "idMath.h"
#import "idStr.h"

const idMat3 mat3_identity = { { { 1, 0, 0 }, { 0, 1, 0 }, { 0, 0, 1 } } };
const idVec3 vec3_origin = { 0, 0, 0 };

/*
=================
idRotation::ToMat3
=================
*/
idMat3 idRotation_ToMat3( idVec3 vec, float angle ) {
    float wx, wy, wz;
    float xx, yy, yz;
    float xy, xz, zz;
    float x2, y2, z2;
    float a, c, s, x, y, z;
    idMat3 axis;

    a = angle * ( ( (float)M_PI / 180.0f ) * 0.5f );
    s = sinf( a );
    c = cosf( a );

    x = vec.x * s;
    y = vec.y * s;
    z = vec.z * s;

    x2 = x + x;
    y2 = y + y;
    z2 = z + z;

    xx = x * x2;
    xy = x * y2;
    xz = x * z2;

    yy = y * y2;
    yz = y * z2;
    zz = z * z2;

    wx = c * x2;
    wy = c * y2;
    wz = c * z2;

    axis.mat[ 0 ].x = 1.0f - ( yy + zz );
    axis.mat[ 0 ].y = xy - wz;
    axis.mat[ 0 ].z = xz + wy;

    axis.mat[ 1 ].x = xy + wz;
    axis.mat[ 1 ].y = 1.0f - ( xx + zz );
    axis.mat[ 1 ].z = yz - wx;

    axis.mat[ 2 ].x = xz - wy;
    axis.mat[ 2 ].y = yz + wx;
    axis.mat[ 2 ].z = 1.0f - ( xx + yy );

    return axis;
}

NSString *idVec2_ToString( idVec2 v ) { return idStr_FloatArrayToString( &v.x, 2, 2 ); }
NSString *idVec3_ToString( idVec3 v ) { return idStr_FloatArrayToString( &v.x, 3, 2 ); }
NSString *idVec4_ToString( idVec4 v ) { return idStr_FloatArrayToString( &v.x, 4, 2 ); }

#pragma mark - idExtrapolate<idVec4>

static void idExtrapolate_Construct( idExtrapolateVec4 *self ) {
    self->extrapolationType = EXTRAPOLATION_NONE;
    self->startTime = self->duration = 0.0f;
    memset( &self->startValue, 0, sizeof( self->startValue ) );
    memset( &self->baseSpeed, 0, sizeof( self->baseSpeed ) );
    memset( &self->speed, 0, sizeof( self->speed ) );
    self->currentTime = -1;
    self->currentValue = self->startValue;
}

static void idExtrapolate_Init( idExtrapolateVec4 *self, const float startTime, const float duration, idVec4 startValue, idVec4 baseSpeed, idVec4 speed, const extrapolation_t extrapolationType ) {
    self->extrapolationType = extrapolationType;
    self->startTime = startTime;
    self->duration = duration;
    self->startValue = startValue;
    self->baseSpeed = baseSpeed;
    self->speed = speed;
    self->currentTime = -1;
    self->currentValue = startValue;
}

static idVec4 idExtrapolate_GetCurrentValue( idExtrapolateVec4 *self, float time ) {
    float deltaTime, s;

    if ( time == self->currentTime ) {
        return self->currentValue;
    }

    self->currentTime = time;

    if ( time < self->startTime ) {
        return self->startValue;
    }

    if ( !( self->extrapolationType & EXTRAPOLATION_NOSTOP ) && ( time > self->startTime + self->duration ) ) {
        time = self->startTime + self->duration;
    }

    switch( self->extrapolationType & ~EXTRAPOLATION_NOSTOP ) {
        case EXTRAPOLATION_NONE: {
            deltaTime = ( time - self->startTime ) * 0.001f;
            self->currentValue = idVec4_Add( self->startValue, idVec4_Scale( self->baseSpeed, deltaTime ) );
            break;
        }
        case EXTRAPOLATION_LINEAR: {
            deltaTime = ( time - self->startTime ) * 0.001f;
            self->currentValue = idVec4_Add( self->startValue, idVec4_Scale( idVec4_Add( self->baseSpeed, self->speed ), deltaTime ) );
            break;
        }
        case EXTRAPOLATION_ACCELLINEAR: {
            if ( !self->duration ) {
                self->currentValue = self->startValue;
            } else {
                deltaTime = ( time - self->startTime ) / self->duration;
                s = ( 0.5f * deltaTime * deltaTime ) * ( self->duration * 0.001f );
                self->currentValue = idVec4_Add( idVec4_Add( self->startValue, idVec4_Scale( self->baseSpeed, deltaTime ) ), idVec4_Scale( self->speed, s ) );
            }
            break;
        }
        case EXTRAPOLATION_DECELLINEAR: {
            if ( !self->duration ) {
                self->currentValue = self->startValue;
            } else {
                deltaTime = ( time - self->startTime ) / self->duration;
                s = ( deltaTime - ( 0.5f * deltaTime * deltaTime ) ) * ( self->duration * 0.001f );
                self->currentValue = idVec4_Add( idVec4_Add( self->startValue, idVec4_Scale( self->baseSpeed, deltaTime ) ), idVec4_Scale( self->speed, s ) );
            }
            break;
        }
        case EXTRAPOLATION_ACCELSINE: {
            if ( !self->duration ) {
                self->currentValue = self->startValue;
            } else {
                deltaTime = ( time - self->startTime ) / self->duration;
                s = ( 1.0f - cosf( deltaTime * (float)M_PI * 0.5f ) ) * self->duration * 0.001f * (float)M_SQRT1_2;
                self->currentValue = idVec4_Add( idVec4_Add( self->startValue, idVec4_Scale( self->baseSpeed, deltaTime ) ), idVec4_Scale( self->speed, s ) );
            }
            break;
        }
        case EXTRAPOLATION_DECELSINE: {
            if ( !self->duration ) {
                self->currentValue = self->startValue;
            } else {
                deltaTime = ( time - self->startTime ) / self->duration;
                s = sinf( deltaTime * (float)M_PI * 0.5f ) * self->duration * 0.001f * (float)M_SQRT1_2;
                self->currentValue = idVec4_Add( idVec4_Add( self->startValue, idVec4_Scale( self->baseSpeed, deltaTime ) ), idVec4_Scale( self->speed, s ) );
            }
            break;
        }
    }
    return self->currentValue;
}

#pragma mark - idInterpolateAccelDecelLinear<idVec4>

void idInterpolateAccelDecelLinear_Construct( idInterpolateAccelDecelLinearVec4 *self ) {
    self->startTime = self->accelTime = self->linearTime = self->decelTime = 0;
    memset( &self->startValue, 0, sizeof( self->startValue ) );
    self->endValue = self->startValue;
    idExtrapolate_Construct( &self->extrapolate );
}

void idInterpolateAccelDecelLinear_Init( idInterpolateAccelDecelLinearVec4 *self, const float startTime, const float accelTime, const float decelTime, const float duration, idVec4 startValue, idVec4 endValue ) {
    idVec4 speed;

    self->startTime = startTime;
    self->accelTime = accelTime;
    self->decelTime = decelTime;
    self->startValue = startValue;
    self->endValue = endValue;

    if ( duration <= 0.0f ) {
        return;
    }

    if ( self->accelTime + self->decelTime > duration ) {
        self->accelTime = self->accelTime * duration / ( self->accelTime + self->decelTime );
        self->decelTime = duration - self->accelTime;
    }
    self->linearTime = duration - self->accelTime - self->decelTime;
    speed = idVec4_Scale( idVec4_Sub( endValue, startValue ), ( 1000.0f / ( (float) self->linearTime + ( self->accelTime + self->decelTime ) * 0.5f ) ) );

    idVec4 zero = idVec4_Sub( startValue, startValue );
    if ( self->accelTime ) {
        idExtrapolate_Init( &self->extrapolate, startTime, self->accelTime, startValue, zero, speed, EXTRAPOLATION_ACCELLINEAR );
    } else if ( self->linearTime ) {
        idExtrapolate_Init( &self->extrapolate, startTime, self->linearTime, startValue, zero, speed, EXTRAPOLATION_LINEAR );
    } else {
        idExtrapolate_Init( &self->extrapolate, startTime, self->decelTime, startValue, zero, speed, EXTRAPOLATION_DECELLINEAR );
    }
}

static void idInterpolateAccelDecelLinear_SetPhase( idInterpolateAccelDecelLinearVec4 *self, float time ) {
    float deltaTime;
    idExtrapolateVec4 *extrapolate = &self->extrapolate;

    deltaTime = time - self->startTime;
    if ( deltaTime < self->accelTime ) {
        if ( extrapolate->extrapolationType != EXTRAPOLATION_ACCELLINEAR ) {
            idExtrapolate_Init( extrapolate, self->startTime, self->accelTime, self->startValue, extrapolate->baseSpeed, extrapolate->speed, EXTRAPOLATION_ACCELLINEAR );
        }
    } else if ( deltaTime < self->accelTime + self->linearTime ) {
        if ( extrapolate->extrapolationType != EXTRAPOLATION_LINEAR ) {
            idExtrapolate_Init( extrapolate, self->startTime + self->accelTime, self->linearTime, idVec4_Add( self->startValue, idVec4_Scale( extrapolate->speed, ( self->accelTime * 0.001f * 0.5f ) ) ), extrapolate->baseSpeed, extrapolate->speed, EXTRAPOLATION_LINEAR );
        }
    } else {
        if ( extrapolate->extrapolationType != EXTRAPOLATION_DECELLINEAR ) {
            idExtrapolate_Init( extrapolate, self->startTime + self->accelTime + self->linearTime, self->decelTime, idVec4_Sub( self->endValue, idVec4_Scale( extrapolate->speed, ( self->decelTime * 0.001f * 0.5f ) ) ), extrapolate->baseSpeed, extrapolate->speed, EXTRAPOLATION_DECELLINEAR );
        }
    }
}

idVec4 idInterpolateAccelDecelLinear_GetCurrentValue( idInterpolateAccelDecelLinearVec4 *self, float time ) {
    idInterpolateAccelDecelLinear_SetPhase( self, time );
    return idExtrapolate_GetCurrentValue( &self->extrapolate, time );
}
