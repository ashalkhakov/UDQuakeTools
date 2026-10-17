#import "UDFXTimelineView.h"
#import "UDDeclManagedObjects.h"
#import "UDFXModel.h"

@interface UDFXTimelineView ()
@property (nonatomic, readwrite) int scrubTime;
@end

@implementation UDFXTimelineView

static const CGFloat UDTimelineLabelWidth = 90;

- (void)scrubToEvent:(NSEvent *)event {
    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    CGFloat left = UDTimelineLabelWidth + 4, width = NSWidth(self.bounds) - left - 4;
    CGFloat fraction = MIN(MAX((point.x - left) / width, 0), 1);
    self.scrubTime = (int)(fraction * MAX(self.duration, 1));
    if (self.target != nil && self.action != NULL) {
        [NSApp sendAction:self.action to:self.target from:self];
    }
}

- (void)mouseDown:(NSEvent *)event {
    [self scrubToEvent:event];
}

- (void)mouseDragged:(NSEvent *)event {
    [self scrubToEvent:event];
}

- (BOOL)isFlipped {
    return YES;
}

- (void)setActions:(NSArray<UDFXAction *> *)actions {
    _actions = [actions copy];
    [self setNeedsDisplay:YES];
}

- (void)setStates:(NSArray<UDFXActionState *> *)states {
    _states = [states copy];
    [self setNeedsDisplay:YES];
}

- (void)setTime:(int)time {
    _time = time;
    [self setNeedsDisplay:YES];
}

- (void)drawRect:(NSRect)dirtyRect {
    [[NSColor controlBackgroundColor] setFill];
    NSRectFill(self.bounds);
    NSArray<UDFXAction *> *actions = self.actions;
    if (actions.count == 0) return;

    CGFloat labelWidth = UDTimelineLabelWidth, laneHeight = MIN(20, NSHeight(self.bounds) / actions.count);
    CGFloat left = labelWidth + 4, width = NSWidth(self.bounds) - left - 4;
    float span = MAX(self.duration, 1) / 1000.0f;
    NSDictionary *attributes = @{NSFontAttributeName: [NSFont systemFontOfSize:10],
                                 NSForegroundColorAttributeName: [NSColor textColor]};
    for (NSUInteger i = 0; i < actions.count; i++) {
        UDFXAction *action = actions[i];
        CGFloat y = i * laneHeight;
        NSString *label = action.name.length > 0 ? action.name : [NSString stringWithFormat:@"%@ %@", action.kind ?: @"", action.data ?: @""];
        [label drawInRect:NSMakeRect(2, y + 2, labelWidth, laneHeight - 2) withAttributes:attributes];

        float delay = action.delay.floatValue, duration = action.duration.floatValue;
        float from = delay, to = delay;
        if (action.random1 != nil || action.random2 != nil) {
            from = action.random1.floatValue;
            to = action.random2.floatValue;
        }
        UDFXActionState *state = i < self.states.count ? self.states[i] : nil;
        NSColor *bar = state.running ? [NSColor colorWithCalibratedRed:0.95 green:0.60 blue:0.20 alpha:1.0]
                                     : [NSColor colorWithCalibratedWhite:0.55 alpha:1.0];
        // a random start: its range, lighter
        if (to > from) {
            [[bar colorWithAlphaComponent:0.35] setFill];
            NSRectFill(NSMakeRect(left + width * from / span, y + 4, width * (to - from) / span, laneHeight - 8));
        }
        [bar setFill];
        NSRectFill(NSMakeRect(left + width * to / span, y + 4, MAX(width * duration / span, 2), laneHeight - 8));
    }
    [[NSColor redColor] setFill];
    NSRectFill(NSMakeRect(left + width * (self.time / 1000.0f) / span, 0, 1, NSHeight(self.bounds)));
}

@end
