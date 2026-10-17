#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

/// What a transport plays: a preview with a clock (a particle system's, an
/// FX's, a material's, a GUI's), its time in milliseconds.
@protocol UDTransportPlayable <NSObject>
/// Whether its clock runs.
@property (nonatomic) BOOL playing;
/// The time it is at.
@property (nonatomic, readonly) int time;
/// How long the slider is: the time it goes over.
@property (nonatomic, readonly) int span;
/// From its start again.
- (void)restart;
/// At @a time, that frame drawn.
- (void)seekTo:(int)time;
@end

/**
 * The editors' time controls, the same for each (UDTransportBar.xib): a
 * slider over the preview's span and the time, a video editor's, and
 * under them Restart, Play/Pause and Step. Dragged, the slider pauses the
 * preview where it is let go; Step is a frame (16 ms) on, paused.
 */
@interface UDTransportController : NSViewController

/// Its bar, in @a placeholder (an editor's XIB's place for it), filling it.
- (void)installInView:(NSView *)placeholder;

@property (nonatomic, weak, nullable) id<UDTransportPlayable> playable;
/// Whether Play is offered (YES at first; a GUI's design does not play).
@property (nonatomic) BOOL allowsPlaying;

/// The controls as the playable is now: its time, its span, Play or
/// Pause. Its owner's to call at each frame drawn.
- (void)update;

/// Told after a control moves the playable (target-action; sender the
/// transport).
@property (nonatomic, weak, nullable) id target;
@property (nonatomic, nullable) SEL action;

@property (weak) IBOutlet NSSlider *timeSlider;
@property (weak) IBOutlet NSTextField *timeLabel;
@property (weak) IBOutlet NSButton *restartButton;
@property (weak) IBOutlet NSButton *playButton;
@property (weak) IBOutlet NSButton *stepButton;

- (IBAction)seek:(nullable id)sender;
- (IBAction)togglePlaying:(nullable id)sender;
- (IBAction)step:(nullable id)sender;
- (IBAction)restart:(nullable id)sender;

@end

NS_ASSUME_NONNULL_END
