/*
 * SPDX-License-Identifier: GPL-2.0-or-later
 * UDInspectorIcons.h — Icons for Inspector tabs.
 */

#import "UDInspectorIcons.h"

@interface UDInspectorIcons ()

@property (nonatomic, strong) NSImage *identityInspectorIcon;
@property (nonatomic, strong) NSImage *attributesInspectorIcon;
@property (nonatomic, strong) NSImage *sizeInspectorIcon;
@property (nonatomic, strong) NSImage *connectionsInspectorIcon;
@property (nonatomic, strong) NSImage *effectsInspectorIcon;
@property (nonatomic, strong) NSImage *identityInspectorIconActive;
@property (nonatomic, strong) NSImage *attributesInspectorIconActive;
@property (nonatomic, strong) NSImage *sizeInspectorIconActive;
@property (nonatomic, strong) NSImage *connectionsInspectorIconActive;
@property (nonatomic, strong) NSImage *effectsInspectorIconActive;

@end

@implementation UDInspectorIcons

// Helper macro to reduce boilerplate
#define BEGIN_ICON_DRAWING \
    NSImage *image = [[NSImage alloc] initWithSize:NSMakeSize(16, 16)]; \
    [image lockFocus]; \
    [[NSColor controlTextColor] setStroke]; \
    [[NSColor controlTextColor] setFill]; \
    NSBezierPath *path = [NSBezierPath bezierPath]; \
    [path setLineWidth:1.5]; \
    [path setLineCapStyle:NSRoundLineCapStyle]; \
    [path setLineJoinStyle:NSRoundLineJoinStyle];

// Shared setup for the active (bolder) state
#define BEGIN_ACTIVE_ICON_DRAWING \
    NSImage *image = [[NSImage alloc] initWithSize:NSMakeSize(16, 16)]; \
    [image lockFocus]; \
    [[NSColor controlTextColor] setStroke]; \
    [[NSColor controlTextColor] setFill]; \
    NSBezierPath *path = [NSBezierPath bezierPath]; \
    [path setLineWidth:2.0]; /* Thicker lines for active state */ \
    [path setLineCapStyle:NSRoundLineCapStyle]; \
    [path setLineJoinStyle:NSRoundLineJoinStyle];

#define END_ICON_DRAWING \
    [path stroke]; \
    [image unlockFocus]; \
    return image;

- (instancetype)init {
    self = [super init];
    if (self) {
        self.identityInspectorIcon = [UDInspectorIcons makeIdentityInspectorIcon];
        self.attributesInspectorIcon = [UDInspectorIcons makeAttributesInspectorIcon];
        self.sizeInspectorIcon = [UDInspectorIcons makeSizeInspectorIcon];
        self.connectionsInspectorIcon = [UDInspectorIcons makeConnectionsInspectorIcon];
        self.effectsInspectorIcon = [UDInspectorIcons makeEffectsInspectorIcon];

        self.identityInspectorIconActive = [UDInspectorIcons makeIdentityInspectorIconActive];
        self.attributesInspectorIconActive = [UDInspectorIcons makeAttributesInspectorIconActive];
        self.sizeInspectorIconActive = [UDInspectorIcons makeSizeInspectorIconActive];
        self.connectionsInspectorIconActive = [UDInspectorIcons makeConnectionsInspectorIconActive];
        self.effectsInspectorIconActive = [UDInspectorIcons makeEffectsInspectorIconActive];
    }
    return self;
}

+ (NSImage *)makeIdentityInspectorIcon {
    BEGIN_ICON_DRAWING
    
    // Outer ID Card badge
    [path appendBezierPathWithRoundedRect:NSMakeRect(2, 2, 12, 12) xRadius:2 yRadius:2];
    
    // User Head
    [path appendBezierPathWithOvalInRect:NSMakeRect(6, 7.5, 4, 4)];
    
    // User Shoulders (Arc)
    [path moveToPoint:NSMakePoint(4, 3)];
    [path appendBezierPathWithArcWithCenter:NSMakePoint(8, 3) radius:4 startAngle:180 endAngle:0];
    
    END_ICON_DRAWING
}

+ (NSImage *)makeAttributesInspectorIcon {
    BEGIN_ICON_DRAWING

    // Top track & handle
    [path moveToPoint:NSMakePoint(2, 12)];
    [path lineToPoint:NSMakePoint(14, 12)];
    [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(5, 10, 4, 4)] fill];
    
    // Middle track & handle
    [path moveToPoint:NSMakePoint(2, 8)];
    [path lineToPoint:NSMakePoint(14, 8)];
    [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(9, 6, 4, 4)] fill];
    
    // Bottom track & handle
    [path moveToPoint:NSMakePoint(2, 4)];
    [path lineToPoint:NSMakePoint(14, 4)];
    [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(3, 2, 4, 4)] fill];
    
    END_ICON_DRAWING
}

+ (NSImage *)makeSizeInspectorIcon {
    BEGIN_ICON_DRAWING
    
    // Right-angle Ruler (L-shape)
    [path moveToPoint:NSMakePoint(3, 14)];
    [path lineToPoint:NSMakePoint(3, 3)];
    [path lineToPoint:NSMakePoint(14, 3)];
    [path lineToPoint:NSMakePoint(14, 6)];
    [path lineToPoint:NSMakePoint(6, 6)];
    [path lineToPoint:NSMakePoint(6, 14)];
    [path closePath];
    
    // Inner tick marks
    [path moveToPoint:NSMakePoint(3, 10)];
    [path lineToPoint:NSMakePoint(4.5, 10)];
    
    [path moveToPoint:NSMakePoint(9, 3)];
    [path lineToPoint:NSMakePoint(9, 4.5)];
    
    END_ICON_DRAWING
}

+ (NSImage *)makeConnectionsInspectorIcon {
    BEGIN_ICON_DRAWING
    
    // Top node
    [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(6, 11, 4, 4)] stroke];
    
    // Bottom left node
    [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(2, 2, 4, 4)] stroke];
    
    // Bottom right node
    [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(10, 2, 4, 4)] stroke];
    
    // Connecting lines
    [path moveToPoint:NSMakePoint(8, 11)];
    [path lineToPoint:NSMakePoint(4, 6)];
    
    [path moveToPoint:NSMakePoint(8, 11)];
    [path lineToPoint:NSMakePoint(12, 6)];
    
    END_ICON_DRAWING
}

+ (NSImage *)makeEffectsInspectorIcon {
    BEGIN_ICON_DRAWING
    
    // Magic Wand Stick
    [path moveToPoint:NSMakePoint(3, 3)];
    [path lineToPoint:NSMakePoint(11, 11)];
    
    // Wand Handle (thicker overlap)
    NSBezierPath *handle = [NSBezierPath bezierPath];
    [handle setLineWidth:2.5];
    [handle moveToPoint:NSMakePoint(3, 3)];
    [handle lineToPoint:NSMakePoint(6, 6)];
    [handle stroke];
    
    // Sparkles (solid dots around the tip)
    [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(11, 12, 2, 2)] fill];
    [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(13, 9, 2, 2)] fill];
    [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(8, 13, 2, 2)] fill];
    
    END_ICON_DRAWING
}

+ (NSImage *)makeIdentityInspectorIconActive {
    BEGIN_ACTIVE_ICON_DRAWING
    
    [path setLineWidth:1.5]; // Keep the outer boundary crisp
    
    // Outer ID Card badge (Stroked)
    [path appendBezierPathWithRoundedRect:NSMakeRect(2, 2, 12, 12) xRadius:2 yRadius:2];
    [path stroke];
    
    [path removeAllPoints];
    
    // User Head (Filled)
    [path appendBezierPathWithOvalInRect:NSMakeRect(6, 7.5, 4, 4)];
    
    // User Shoulders (Filled Silhouette)
    [path moveToPoint:NSMakePoint(4, 2)];
    [path lineToPoint:NSMakePoint(4, 3)];
    [path appendBezierPathWithArcWithCenter:NSMakePoint(8, 3) radius:4 startAngle:180 endAngle:0];
    [path lineToPoint:NSMakePoint(12, 2)];
    [path closePath];
    
    [path fill];
    
    END_ICON_DRAWING
}

+ (NSImage *)makeAttributesInspectorIconActive {
    BEGIN_ACTIVE_ICON_DRAWING
    
    // Thicker tracks & larger filled handles (5x5 instead of 4x4)
    [path moveToPoint:NSMakePoint(2, 12)];
    [path lineToPoint:NSMakePoint(14, 12)];
    [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(4.5, 9.5, 5, 5)] fill];
    
    [path moveToPoint:NSMakePoint(2, 8)];
    [path lineToPoint:NSMakePoint(14, 8)];
    [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(8.5, 5.5, 5, 5)] fill];
    
    [path moveToPoint:NSMakePoint(2, 4)];
    [path lineToPoint:NSMakePoint(14, 4)];
    [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(2.5, 1.5, 5, 5)] fill];
    
    [path stroke];
    
    END_ICON_DRAWING
}

+ (NSImage *)makeSizeInspectorIconActive {
    BEGIN_ACTIVE_ICON_DRAWING
    
    // Filled L-shape
    [path moveToPoint:NSMakePoint(3, 14)];
    [path lineToPoint:NSMakePoint(3, 3)];
    [path lineToPoint:NSMakePoint(14, 3)];
    [path lineToPoint:NSMakePoint(14, 6)];
    [path lineToPoint:NSMakePoint(6, 6)];
    [path lineToPoint:NSMakePoint(6, 14)];
    [path closePath];
    [path fill];
    
    // Draw the inner tick marks using the background color to "cut them out" of the fill
    [[NSColor controlBackgroundColor] setStroke];
    NSBezierPath *ticks = [NSBezierPath bezierPath];
    [ticks setLineWidth:1.5];
    [ticks moveToPoint:NSMakePoint(3, 10)];
    [ticks lineToPoint:NSMakePoint(5, 10)];
    [ticks moveToPoint:NSMakePoint(9, 3)];
    [ticks lineToPoint:NSMakePoint(9, 5)];
    [ticks stroke];
    
    END_ICON_DRAWING
}

+ (NSImage *)makeConnectionsInspectorIconActive {
    BEGIN_ACTIVE_ICON_DRAWING
    
    // Draw connecting lines first so they sit under the nodes
    [path moveToPoint:NSMakePoint(8, 11)];
    [path lineToPoint:NSMakePoint(4, 6)];
    
    [path moveToPoint:NSMakePoint(8, 11)];
    [path lineToPoint:NSMakePoint(12, 6)];
    [path stroke];
    
    // Filled nodes (larger: 5x5)
    [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(5.5, 10.5, 5, 5)] fill];
    [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(1.5, 1.5, 5, 5)] fill];
    [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(9.5, 1.5, 5, 5)] fill];
    
    END_ICON_DRAWING
}

+ (NSImage *)makeEffectsInspectorIconActive {
    BEGIN_ACTIVE_ICON_DRAWING
    
    // Magic Wand Stick (Thicker)
    [path moveToPoint:NSMakePoint(3, 3)];
    [path lineToPoint:NSMakePoint(11, 11)];
    [path stroke];
    
    // Wand Handle (Bolded)
    NSBezierPath *handle = [NSBezierPath bezierPath];
    [handle setLineWidth:3.5];
    [handle moveToPoint:NSMakePoint(3, 3)];
    [handle lineToPoint:NSMakePoint(6, 6)];
    [handle stroke];
    
    // Larger Sparkles
    [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(10.5, 12.5, 3, 3)] fill];
    [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(13.5, 8.5, 3, 3)] fill];
    [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(7.5, 13.5, 3, 3)] fill];
    
    END_ICON_DRAWING
}

@end

