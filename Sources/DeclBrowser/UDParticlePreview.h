#import <AppKit/AppKit.h>

@class UDFXAction, UDFXActionState, UDParticleStage, UDWorkspace;

NS_ASSUME_NONNULL_BEGIN

/**
 * A particle system or an FX playing in an image view: its quads as the
 * engine makes them (UDParticleModel; UDFXModel's actions, their particle
 * systems), drawn as its ambient pass draws them (UDSoftwareRenderer), seen
 * from the side (looking down +X, Z up), framed on GetStageBounds. It plays
 * while its view is in a window; an FX from its start again at its
 * Duration, as a "test" fx entity does.
 */
@interface UDParticlePreview : NSObject

- (instancetype)initWithImageView:(NSImageView *)imageView workspace:(nullable UDWorkspace *)workspace;

/// The particle system's stages to play (set again after an edit: the time
/// goes on).
@property (nonatomic, copy, nullable) NSArray<UDParticleStage *> *stages;
/// Or an FX's actions.
@property (nonatomic, copy, nullable) NSArray<UDFXAction *> *fxActions;
/// Plays from the start again.
- (void)restart;
/// The time it is at, in milliseconds since its start (its FX's, looped).
@property (nonatomic, readonly) int time;
/// An FX's actions' states at the time drawn (idEntityFx::Run's), and its
/// Duration in milliseconds.
@property (nonatomic, copy, readonly) NSArray<UDFXActionState *> *fxStates;
@property (nonatomic, readonly) int fxDuration;
/// Told the time at each frame drawn (an FX editor's timeline).
@property (nonatomic, weak, nullable) id target;
@property (nonatomic, nullable) SEL action;
/// One frame at @a msec, drawn now (the timer's, and a test's).
- (void)renderAtTime:(int)msec;

@end

NS_ASSUME_NONNULL_END
