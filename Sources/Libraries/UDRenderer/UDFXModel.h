/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 * UDFXModel.h — an FX playing, as idEntityFx plays it (game/Fx.cpp):
 * Setup, Start, Run each game frame, ApplyFade; at its Duration, the
 * clean-up Event_ClearFx does.
 */

#import <Foundation/Foundation.h>

@class idDeclManager, UDFXAction, UDParticleSurface, UDPointLight;

NS_ASSUME_NONNULL_BEGIN

/// What an action has in the world at a time: the model or light Run added
/// for it (its renderEntity's or renderLight's parms, ApplyFade's), and
/// whether it is running (between its start and its end).
@interface UDFXActionState : NSObject
@property (nonatomic, readonly) NSInteger index;
@property (nonatomic, readonly) BOOL running;
/// Run's pct for it, 0–1, while it runs.
@property (nonatomic, readonly) float fraction;
@property (nonatomic, readonly) BOOL hasModel;
@property (nonatomic, readonly) BOOL hasLight;
/// The model's or light's shader parms, SHADERPARM_RED… (12 of them).
@property (nonatomic, readonly) const float *shaderParms;
/// When its model or light was added, in milliseconds.
@property (nonatomic, readonly) int spawnTime;
@end

@interface UDFXModel : NSObject

- (instancetype)initWithActions:(NSArray<UDFXAction *> *)actions declManager:(nullable idDeclManager *)declManager;

/// idEntityFx::Duration, in milliseconds.
@property (nonatomic, readonly) int duration;

/// Each action's state @a msec after the FX started (Run stepped at
/// USERCMD_MSEC from the start; past the duration, cleaned up).
- (NSArray<UDFXActionState *> *)statesAtTime:(int)msec;

/// The particle systems of the actions' models (a .prt model is its
/// particle decl) at @a msec, in the world, seen along @a viewAxis.
- (NSArray<UDParticleSurface *> *)surfacesAtTime:(int)msec viewAxis:(const float [_Nonnull 3][3])viewAxis;

/// The lights its actions have added at @a msec (R_DeriveLightData's point
/// lights: at their offsets, their radius, their material, their parms as
/// Run and ApplyFade left them).
- (NSArray<UDPointLight *> *)lightsAtTime:(int)msec;

/// The bounds of the particle systems its actions can add, and of its
/// lights' radiuses, at their offsets: min x y z, max x y z (zero when it
/// has none).
- (void)getBounds:(float [_Nonnull 6])bounds;

@end

NS_ASSUME_NONNULL_END
