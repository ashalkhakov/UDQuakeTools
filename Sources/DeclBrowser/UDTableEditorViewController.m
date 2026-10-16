#import "UDTableEditorViewController.h"
#import "UDDeclManagedObjects.h"

@implementation UDTableEditorViewController

- (instancetype)init {
    return [super initWithNibName:@"UDTableEditorView" bundle:[NSBundle bundleForClass:[UDTableEditorViewController class]]];
}

- (UDDeclTable *)table {
    return (UDDeclTable *)self.declObject;
}

- (NSArray<NSNumber *> *)values {
    return [self.table.values valueForKey:@"number"] ?: @[];
}

- (void)editingContextDidChange {
    self.graphView.values = self.values;
    self.graphView.snap = self.table.snap;
}

- (IBAction)addOrRemoveValue:(NSSegmentedControl *)sender {
    NSMutableArray<UDTableValue *> *values = [self.table.values mutableCopy] ?: [NSMutableArray array];
    NSUInteger selected = self.valuesController.selectionIndex;
    if (sender.selectedSegment == 0) {
        // After the selection (at the end without one), a copy of the value
        // before it.
        NSUInteger at = selected != NSNotFound ? selected + 1 : values.count;
        [values insertObject:(at > 0 ? [values[at - 1] copy] : [UDTableValue valueWithNumber:0]) atIndex:at];
        self.table.values = values;
        [self.valuesController setSelectionIndex:at];
    } else {
        // A table has a value at least: the engine reads one with none as
        // its default.
        if (selected == NSNotFound || values.count <= 1) {
            NSBeep();
            return;
        }
        [values removeObjectAtIndex:selected];
        self.table.values = values;
    }
}

@end

@implementation UDTableGraphView

- (BOOL)isFlipped {
    return NO;
}

- (void)setValues:(NSArray<NSNumber *> *)values {
    _values = [values copy];
    [self setNeedsDisplay:YES];
}

- (void)setSnap:(BOOL)snap {
    _snap = snap;
    [self setNeedsDisplay:YES];
}

/// Where value @a v at index @a i is drawn in @a plot, the values ranging
/// from @a low to @a high.
static NSPoint UDGraphPoint(NSRect plot, CGFloat step, float low, float high, NSUInteger i, float v) {
    return NSMakePoint(NSMinX(plot) + step * (CGFloat)i, NSMinY(plot) + NSHeight(plot) * (CGFloat)((v - low) / (high - low)));
}

- (void)drawRect:(NSRect)dirtyRect {
    [[NSColor controlBackgroundColor] setFill];
    NSRectFill(self.bounds);
    [[NSColor gridColor] setStroke];
    [NSBezierPath strokeRect:NSInsetRect(self.bounds, 0.5, 0.5)];

    NSArray<NSNumber *> *values = self.values;
    if (values.count == 0) return;
    float low = 0, high = 0;
    for (NSNumber *value in values) {
        low = MIN(low, value.floatValue);
        high = MAX(high, value.floatValue);
    }
    if (high - low < 1e-6f) high = low + 1;
    NSRect plot = NSInsetRect(self.bounds, 10, 10);
    CGFloat step = values.count > 1 ? NSWidth(plot) / (CGFloat)(values.count - 1) : 0;

    // Zero, when it is in sight.
    if (low < 0 && high > 0) {
        [[NSColor gridColor] setStroke];
        CGFloat y = UDGraphPoint(plot, step, low, high, 0, 0).y;
        [NSBezierPath strokeLineFromPoint:NSMakePoint(NSMinX(plot), y) toPoint:NSMakePoint(NSMaxX(plot), y)];
    }

    NSBezierPath *curve = [NSBezierPath bezierPath];
    [curve moveToPoint:UDGraphPoint(plot, step, low, high, 0, values[0].floatValue)];
    for (NSUInteger i = 1; i < values.count; i++) {
        NSPoint point = UDGraphPoint(plot, step, low, high, i, values[i].floatValue);
        if (self.snap) [curve lineToPoint:NSMakePoint(point.x, curve.currentPoint.y)];
        [curve lineToPoint:point];
    }
    curve.lineWidth = 1.5;
    [[NSColor colorWithCalibratedRed:0.20 green:0.45 blue:0.85 alpha:1.0] setStroke];
    [curve stroke];

    [[NSColor textColor] setFill];
    for (NSUInteger i = 0; i < values.count; i++) {
        NSPoint point = UDGraphPoint(plot, step, low, high, i, values[i].floatValue);
        [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(point.x - 2.5, point.y - 2.5, 5, 5)] fill];
    }
}

@end
