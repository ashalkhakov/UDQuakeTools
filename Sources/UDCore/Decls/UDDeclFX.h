/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 * UDDeclFX.h — FX (idDeclFX).
 */

#import "UDDeclElement.h"

NS_ASSUME_NONNULL_BEGIN

/// One of an FX's actions, as idDeclFX::ParseSingleFXAction reads it: what
/// it does (its keyword: light, uselight, attachlight, model, usemodel,
/// particle, decal, sound, shake, attachentity, launch, shockwave) on what
/// (data), and the keywords it sets. A number it does not set is nil (0 to
/// the engine); vectors are their numbers, space-separated.
@interface UDFXAction : UDDeclPropertyElement
@property (nonatomic, copy, nullable) NSString *kind;
@property (nonatomic, copy, nullable) NSString *data;
@property (nonatomic, copy, nullable) NSString *name;
@property (nonatomic, copy, nullable) NSString *fire;
@property (nonatomic, copy, nullable) NSNumber *delay;
@property (nonatomic, copy, nullable) NSNumber *duration;
@property (nonatomic, copy, nullable) NSNumber *restart;
@property (nonatomic, copy, nullable) NSNumber *size;
@property (nonatomic, copy, nullable) NSNumber *fadeIn;
@property (nonatomic, copy, nullable) NSNumber *fadeOut;
@property (nonatomic, copy, nullable) NSNumber *rotate;
@property (nonatomic, copy, nullable) NSNumber *random1;
@property (nonatomic, copy, nullable) NSNumber *random2;
@property (nonatomic, copy, nullable) NSString *offset;
@property (nonatomic, copy, nullable) NSString *axis;
@property (nonatomic, copy, nullable) NSString *angle;
@property (nonatomic, copy, nullable) NSString *lightColor;
@property (nonatomic, copy, nullable) NSNumber *lightRadius;
@property (nonatomic, copy, nullable) NSNumber *shakeTime;
@property (nonatomic, copy, nullable) NSNumber *shakeAmplitude;
@property (nonatomic, copy, nullable) NSNumber *shakeDistance;
@property (nonatomic) BOOL shakeFalloff;
@property (nonatomic, copy, nullable) NSNumber *shakeImpulse;
@property (nonatomic) BOOL noshadows, particleTrackVelocity, trackOrigin, ignoreMaster;
@end

/// An FX: the joint it binds to, and its actions, TRANSIENT, as a table's
/// values are.
@interface UDDeclFX : UDDeclBase
@property (nonatomic, copy, nullable) NSString *bindTo;
@property (nonatomic, copy, nullable) NSArray<UDFXAction *> *actions;
@end

NS_ASSUME_NONNULL_END
