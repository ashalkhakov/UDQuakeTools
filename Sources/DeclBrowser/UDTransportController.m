#import "UDTransportController.h"

/// A frame: the engine's USERCMD_MSEC.
static const int UDTransportStep = 16;

@implementation UDTransportController

- (instancetype)init {
    self = [super initWithNibName:@"UDTransportBar" bundle:[NSBundle bundleForClass:[UDTransportController class]]];
    if (self) {
        _allowsPlaying = YES;
    }
    return self;
}

- (void)installInView:(NSView *)placeholder {
    NSView *bar = self.view;
    bar.frame = placeholder.bounds;
    bar.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [placeholder addSubview:bar];
    [self update];
}

- (void)setAllowsPlaying:(BOOL)allowsPlaying {
    _allowsPlaying = allowsPlaying;
    [self update];
}

- (void)update {
    (void)self.view;
    id<UDTransportPlayable> playable = self.playable;
    int time = playable.time;
    NSSlider *slider = self.timeSlider;
    double span = MAX(MAX(playable.span, 1), time);
    if (slider.maxValue != span) {
        slider.maxValue = span;
    }
    slider.doubleValue = time;
    self.timeLabel.stringValue = [NSString stringWithFormat:@"%.2f s", time / 1000.0];
    self.playButton.enabled = self.allowsPlaying;
    self.playButton.title = playable.playing && self.allowsPlaying ? @"Pause" : @"Play";
}

- (void)_moved {
    [self update];
    id target = self.target;
    if (target != nil && self.action != NULL) {
        [NSApp sendAction:self.action to:target from:self];
    }
}

- (IBAction)seek:(id)sender {
    id<UDTransportPlayable> playable = self.playable;
    playable.playing = NO;
    [playable seekTo:(int)lround(self.timeSlider.doubleValue)];
    [self _moved];
}

- (IBAction)togglePlaying:(id)sender {
    id<UDTransportPlayable> playable = self.playable;
    if (!self.allowsPlaying) return;
    playable.playing = !playable.playing;
    [self _moved];
}

- (IBAction)step:(id)sender {
    id<UDTransportPlayable> playable = self.playable;
    playable.playing = NO;
    [playable seekTo:playable.time + UDTransportStep];
    [self _moved];
}

- (IBAction)restart:(id)sender {
    [self.playable restart];
    [self _moved];
}

@end
