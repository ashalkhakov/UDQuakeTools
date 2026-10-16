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
/// Or a material, its name and its text (an editor's, unsaved): drawn on a
/// square facing the view, lit by a point light (the interaction pass, the
/// game's glprogs/interaction.vfp), then its ambient stages.
@property (nonatomic, copy, nullable) NSString *materialName;
@property (nonatomic, copy, nullable) NSString *materialText;
/// Why the lit part is not drawn, if it is not (no interaction.vfp, or one
/// that does not run).
@property (nonatomic, copy, readonly, nullable) NSString *lightingProblem;
/// Plays from the start again.
- (void)restart;
/// Whether it plays (YES at first); paused, it shows the time it is at.
@property (nonatomic) BOOL playing;
/// Paused at @a msec, that frame drawn: a time slider's.
- (void)showTime:(int)msec;
/// The time it goes over, in milliseconds, from its start again after it:
/// an FX's Duration and a frame; a particle system's stages' time offsets,
/// and their cycles (two for a system that does not stop).
@property (nonatomic, readonly) int span;
/// The time it is at, in milliseconds since its start (its FX's, looped).
@property (nonatomic, readonly) int time;
/// An FX's actions' states at the time drawn (idEntityFx::Run's), and its
/// Duration in milliseconds.
@property (nonatomic, copy, readonly) NSArray<UDFXActionState *> *fxStates;
@property (nonatomic, readonly) int fxDuration;
/// The controls it keeps up to date at each frame: a time slider (its range
/// the span), a label of the time, a Play/Pause button.
@property (nonatomic, weak, nullable) NSSlider *timeSlider;
@property (nonatomic, weak, nullable) NSTextField *timeLabel;
@property (nonatomic, weak, nullable) NSButton *playButton;
/// Told the time at each frame drawn (an FX editor's timeline).
@property (nonatomic, weak, nullable) id target;
@property (nonatomic, nullable) SEL action;
/// One frame at @a msec, drawn now (the timer's, and a test's).
- (void)renderAtTime:(int)msec;

@end

NS_ASSUME_NONNULL_END
