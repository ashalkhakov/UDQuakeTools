#import "UDTableEditorViewController.h"
#import "UDDeclManagedObjects.h"

/// A table's values attribute ("0, 0.5, 1"), as numbers.
static NSArray<NSNumber *> *UDTableValues(NSString *text) {
    NSMutableArray<NSNumber *> *values = [NSMutableArray array];
    for (NSString *part in [text componentsSeparatedByString:@","]) {
        NSString *trimmed = [part stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (trimmed.length > 0) [values addObject:@(trimmed.floatValue)];
    }
    return values;
}

static NSString *UDTableText(NSArray<NSNumber *> *values) {
    NSMutableArray<NSString *> *parts = [NSMutableArray arrayWithCapacity:values.count];
    for (NSNumber *value in values) [parts addObject:[NSString stringWithFormat:@"%g", value.floatValue]];
    return [parts componentsJoinedByString:@", "];
}

@implementation UDTableEditorViewController

- (instancetype)init {
    return [super initWithNibName:@"UDTableEditorView" bundle:[NSBundle bundleForClass:[UDTableEditorViewController class]]];
}

- (UDDeclTable *)table {
    return (UDDeclTable *)self.declObject;
}

- (NSArray<NSNumber *> *)values {
    return UDTableValues(self.table.values);
}

/// The values written back: one edit, one undo, the tab edited.
- (void)_setValues:(NSArray<NSNumber *> *)values {
    self.table.values = UDTableText(values);
    [self editingContextDidChange];                     // now: the context tells at the end of the event
}

- (void)editingContextDidChange {
    [self.valuesTable reloadData];
    self.graphView.values = self.values;
    self.graphView.snap = self.table.snap;
}

#pragma mark - The values

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    return (NSInteger)self.values.count;
}

- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)column row:(NSInteger)row {
    NSArray<NSNumber *> *values = self.values;
    if (row < 0 || row >= (NSInteger)values.count) return nil;
    if ([column.identifier isEqualToString:@"index"]) return @(row);
    return [NSString stringWithFormat:@"%g", values[(NSUInteger)row].floatValue];
}

- (void)tableView:(NSTableView *)tableView setObjectValue:(id)object forTableColumn:(NSTableColumn *)column row:(NSInteger)row {
    NSMutableArray<NSNumber *> *values = [self.values mutableCopy];
    if (row < 0 || row >= (NSInteger)values.count) return;
    NSScanner *scanner = [NSScanner scannerWithString:[object description]];
    float value;
    if (![scanner scanFloat:&value] || !scanner.isAtEnd) {
        NSBeep();                                       // not a number: as it was
        return;
    }
    values[(NSUInteger)row] = @(value);
    [self _setValues:values];
}

- (IBAction)addOrRemoveValue:(NSSegmentedControl *)sender {
    NSMutableArray<NSNumber *> *values = [self.values mutableCopy];
    NSInteger selected = self.valuesTable.selectedRow;
    if (sender.selectedSegment == 0) {
        // After the selection (at the end without one), a copy of the value
        // before it.
        NSUInteger at = selected >= 0 ? (NSUInteger)selected + 1 : values.count;
        [values insertObject:(at > 0 ? values[at - 1] : @0) atIndex:at];
        [self _setValues:values];
        [self.valuesTable selectRowIndexes:[NSIndexSet indexSetWithIndex:at] byExtendingSelection:NO];
    } else {
        // A table has a value at least: the engine reads one with none as
        // its default.
        if (selected < 0 || values.count <= 1) {
            NSBeep();
            return;
        }
        [values removeObjectAtIndex:(NSUInteger)selected];
        [self _setValues:values];
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
