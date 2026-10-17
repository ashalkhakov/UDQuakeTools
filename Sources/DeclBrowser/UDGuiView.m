#import "UDGuiView.h"
#import "UDGuiPlayer.h"
#import "idWindow.h"
#import "idDeviceContext.h"
#import "idUserInterface.h"
#import "UDGuiGLView.h"
#import "UDSoftwareRenderer.h"
#import "UDOverlay.h"
#import "rvGEWorkspace.h"
#import "idMath.h"

#ifdef __APPLE__
#define UDCompositeCopy NSCompositingOperationCopy
#else
#define UDCompositeCopy NSCompositeCopy
#endif

int UDGuiKeyForEvent(NSEvent *event) {
    NSString *characters = event.charactersIgnoringModifiers;
    if (characters.length == 0) return 0;
    unichar c = [characters characterAtIndex:0];
    switch (c) {
        case NSUpArrowFunctionKey:      return K_UPARROW;
        case NSDownArrowFunctionKey:    return K_DOWNARROW;
        case NSLeftArrowFunctionKey:    return K_LEFTARROW;
        case NSRightArrowFunctionKey:   return K_RIGHTARROW;
        case NSInsertFunctionKey:       return K_INS;
        case NSDeleteFunctionKey:       return K_DEL;
        case NSHomeFunctionKey:         return K_HOME;
        case NSEndFunctionKey:          return K_END;
        case NSPageUpFunctionKey:       return K_PGUP;
        case NSPageDownFunctionKey:     return K_PGDN;
        case NSPauseFunctionKey:        return K_PAUSE;
        case '\r': case 3:              return K_ENTER;     // Return, keypad Enter
        case '\t': case 25:             return K_TAB;       // Tab, Shift-Tab
        case 27:                        return K_ESCAPE;
        case 8: case 127:               return K_BACKSPACE;
        default:
            break;
    }
    if (c >= NSF1FunctionKey && c <= NSF12FunctionKey) {
        return K_F1 + (c - NSF1FunctionKey);
    }
    // the rest as Sys_MapCharForKey leaves them: the character, lower case
    if (c >= 'A' && c <= 'Z') return c - 'A' + 'a';
    if (c >= 32 && c < 127) return c;
    return 0;
}

@implementation UDGuiView {
    NSTrackingRectTag _trackingTag;
    NSEventModifierFlags _modifiers;
    UDGuiGLView *_glView;
    NSImage *_picture;
    UDOverlay *_overlay;
}

- (instancetype)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        [self _setUpGL];
    }
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    self = [super initWithCoder:coder];
    if (self) {
        [self _setUpGL];
    }
    return self;
}

/// The GL view over the whole view, if there is GL.
- (void)_setUpGL {
    _glView = [UDGuiGLView viewWithFrame:self.bounds];
    if (_glView == nil) return;
    _glView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [self addSubview:_glView];
}

- (BOOL)drawsWithGL {
    return _glView != nil;
}

- (NSView *)glView {
    return _glView;
}

- (void)setPlayer:(UDGuiPlayer *)player {
    _player = player;
    // with GL, its triangles are enough
    player.drawsPicture = _glView == nil;
}

- (void)showFrame {
    UDSoftwareRenderer *renderer = self.player.manager.renderer;
    [self showTriangles:self.player.triangles picture:self.player.frame
            pictureSize:NSMakeSize(renderer.width, renderer.height) overlay:nil];
}

- (void)showTriangles:(UDTriangleList *)triangles picture:(NSImage *)picture
          pictureSize:(NSSize)pictureSize overlay:(UDOverlay *)overlay {
    _picture = picture;
    _overlay = overlay;
    if (_glView == nil) {
        self.needsDisplay = YES;
        return;
    }
    _glView.pictureSize = pictureSize;
    _glView.guiRect = self.guiRect;
    _glView.overlay = overlay;
    _glView.triangles = triangles;
}

- (BOOL)isFlipped {
    return YES;
}

- (BOOL)isOpaque {
    return YES;
}

- (BOOL)acceptsFirstResponder {
    return YES;
}

- (BOOL)acceptsFirstMouse:(NSEvent *)event {
    return YES;
}

#pragma mark - Geometry

- (CGFloat)scale {
    NSRect bounds = self.bounds;
    CGFloat scale = MIN(NSWidth(bounds) / VIRTUAL_WIDTH, NSHeight(bounds) / VIRTUAL_HEIGHT);
    return scale > 0 ? scale : 1;
}

- (NSRect)guiRect {
    NSRect bounds = self.bounds;
    CGFloat scale = self.scale;
    NSSize size = NSMakeSize(VIRTUAL_WIDTH * scale, VIRTUAL_HEIGHT * scale);
    return NSMakeRect(floor(NSMidX(bounds) - size.width / 2), floor(NSMidY(bounds) - size.height / 2), size.width, size.height);
}

- (NSPoint)guiPointFromView:(NSPoint)point {
    NSRect rect = self.guiRect;
    CGFloat scale = self.scale;
    return NSMakePoint((point.x - NSMinX(rect)) / scale, (point.y - NSMinY(rect)) / scale);
}

- (NSPoint)viewPointFromGui:(NSPoint)point {
    NSRect rect = self.guiRect;
    CGFloat scale = self.scale;
    return NSMakePoint(NSMinX(rect) + point.x * scale, NSMinY(rect) + point.y * scale);
}

#pragma mark - Drawing

- (void)drawRect:(NSRect)dirtyRect {
    // its own bounds only: a view does not clip to them on macOS 14 and
    // later, and its dirty rect can reach past them
    [[NSColor blackColor] setFill];
    NSRectFill(NSIntersectionRect(dirtyRect, self.bounds));
    NSImage *frame = _picture;
    if (frame == nil) return;
    NSRect rect = self.guiRect;
    // the GUI's space under one transform, as RDLKit's canvas draws its page
    [NSGraphicsContext saveGraphicsState];
    NSAffineTransform *transform = [NSAffineTransform transform];
    [transform translateXBy:NSMinX(rect) yBy:NSMinY(rect)];
    [transform scaleBy:self.scale];
    [transform concat];
    [frame drawInRect:NSMakeRect(0, 0, VIRTUAL_WIDTH, VIRTUAL_HEIGHT) fromRect:NSZeroRect
            operation:UDCompositeCopy fraction:1 respectFlipped:YES hints:nil];
    [NSGraphicsContext restoreGraphicsState];
    [self _drawOverlay];
}

/// The overlay in software: its triangles filled, its lines a point wide.
- (void)_drawOverlay {
    UDOverlay *overlay = _overlay;
    if (overlay == nil) return;
    const UDOverlayVertex *t = overlay.triangleVertices;
    for (NSUInteger i = 0; i + 2 < overlay.triangleVertexCount; i += 3) {
        [[NSColor colorWithDeviceRed:t[i].r green:t[i].g blue:t[i].b alpha:t[i].a] setFill];
        NSBezierPath *path = [NSBezierPath bezierPath];
        [path moveToPoint:NSMakePoint(t[i].x, t[i].y)];
        [path lineToPoint:NSMakePoint(t[i + 1].x, t[i + 1].y)];
        [path lineToPoint:NSMakePoint(t[i + 2].x, t[i + 2].y)];
        [path closePath];
        [path fill];
    }
    const UDOverlayVertex *l = overlay.lineVertices;
    for (NSUInteger i = 0; i + 1 < overlay.lineVertexCount; i += 2) {
        [[NSColor colorWithDeviceRed:l[i].r green:l[i].g blue:l[i].b alpha:l[i].a] setStroke];
        NSBezierPath *path = [NSBezierPath bezierPath];
        path.lineWidth = 1;
        [path moveToPoint:NSMakePoint(l[i].x + 0.5, l[i].y + 0.5)];
        [path lineToPoint:NSMakePoint(l[i + 1].x + 0.5, l[i + 1].y + 0.5)];
        [path stroke];
    }
}

#pragma mark - The mouse

- (void)viewDidMoveToWindow {
    [super viewDidMoveToWindow];
    [self.window setAcceptsMouseMovedEvents:YES];
    [self _resetTracking];
}

- (void)setFrameSize:(NSSize)size {
    [super setFrameSize:size];
    [self _resetTracking];
    _glView.guiRect = self.guiRect;
    if (self.workspace != nil) {
        [self _designChanged];      // the overlay is where the GUI is
    }
}

- (void)_resetTracking {
    if (_trackingTag) {
        [self removeTrackingRect:_trackingTag];
        _trackingTag = 0;
    }
    if (self.window != nil) {
        _trackingTag = [self addTrackingRect:self.bounds owner:self userData:NULL assumeInside:NO];
    }
}

#pragma mark - Designing

/// The workspace's rect: the GUI's in the view (its points, y down).
- (void)_syncWorkspaceRect {
    NSRect rect = self.guiRect;
    self.workspace.rect = idRectangle_Make((float)NSMinX(rect), (float)NSMinY(rect), (float)NSWidth(rect), (float)NSHeight(rect));
}

- (NSPoint)_pointOf:(NSEvent *)event {
    return [self convertPoint:event.locationInWindow fromView:nil];
}

/// Sys_Milliseconds, as the events have it.
static int UDEventMilliseconds(NSEvent *event) {
    return (int)(event.timestamp * 1000);
}

- (void)_designChanged {
    id target = self.designTarget;
    if (target != nil && self.designAction != NULL) {
        [NSApp sendAction:self.designAction to:target from:self];
    }
}

/// UpdateCursor: what the selection under the cursor would do.
- (void)_updateCursorAt:(NSPoint)point {
    rvGEHitTest type = [self.workspace cursorTypeAtX:(float)point.x y:(float)point.y];
    NSCursor *cursor;
    switch (type) {
        case HT_MOVE:
            cursor = self.workspace.dragType == HT_MOVE ? [NSCursor closedHandCursor] : [NSCursor openHandCursor];
            break;
        case HT_SIZE_LEFT:
        case HT_SIZE_RIGHT:
            cursor = [NSCursor resizeLeftRightCursor];
            break;
        case HT_SIZE_TOP:
        case HT_SIZE_BOTTOM:
            cursor = [NSCursor resizeUpDownCursor];
            break;
        case HT_SIZE_TOPLEFT:
        case HT_SIZE_TOPRIGHT:
        case HT_SIZE_BOTTOMLEFT:
        case HT_SIZE_BOTTOMRIGHT:
            cursor = [NSCursor crosshairCursor];     // (AppKit has no diagonal one to all)
            break;
        default:
            cursor = [NSCursor arrowCursor];
            break;
    }
    [cursor set];
}

- (BOOL)_designMouseDown:(NSEvent *)event {
    if (self.workspace == nil) return NO;
    [self.window makeFirstResponder:self];
    [self _syncWorkspaceRect];
    NSPoint point = [self _pointOf:event];
    BOOL shift = (event.modifierFlags & NSEventModifierFlagShift) != 0;
    [self.workspace mouseDownAtX:(float)point.x y:(float)point.y shift:shift time:UDEventMilliseconds(event)];
    [self _updateCursorAt:point];
    [self _designChanged];
    return YES;
}

- (BOOL)_designMouseMoved:(NSEvent *)event {
    if (self.workspace == nil) return NO;
    [self _syncWorkspaceRect];
    NSPoint point = [self _pointOf:event];
    rvGEHitTest dragging = self.workspace.dragType;
    [self.workspace mouseMoveToX:(float)point.x y:(float)point.y time:UDEventMilliseconds(event)];
    [self _updateCursorAt:point];
    if (dragging != HT_NONE) {
        [self _designChanged];
    }
    return YES;
}

- (BOOL)_designMouseUp:(NSEvent *)event {
    if (self.workspace == nil) return NO;
    [self.workspace mouseUp];
    [self _updateCursorAt:[self _pointOf:event]];
    [self _designChanged];
    return YES;
}

#pragma mark - Running

- (void)_moveMouse:(NSEvent *)event {
    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    [self.player moveMouseTo:[self guiPointFromView:point]];
}

- (void)mouseMoved:(NSEvent *)event        { if (![self _designMouseMoved:event]) [self _moveMouse:event]; }
- (void)mouseDragged:(NSEvent *)event      { if (![self _designMouseMoved:event]) [self _moveMouse:event]; }
- (void)rightMouseDragged:(NSEvent *)event { [self _moveMouse:event]; }
- (void)otherMouseDragged:(NSEvent *)event { [self _moveMouse:event]; }

- (void)_button:(int)key event:(NSEvent *)event down:(BOOL)down {
    if (self.workspace != nil) return;      // designing: the GUI is not run
    if (down) {
        [self.window makeFirstResponder:self];
    }
    [self _moveMouse:event];
    [self.player key:key down:down];
}

- (void)mouseDown:(NSEvent *)event       { if (![self _designMouseDown:event]) [self _button:K_MOUSE1 event:event down:YES]; }
- (void)mouseUp:(NSEvent *)event         { if (![self _designMouseUp:event]) [self _button:K_MOUSE1 event:event down:NO]; }
- (void)rightMouseDown:(NSEvent *)event  {
    if (self.workspace != nil) {
        [super rightMouseDown:event];       // the design's menu
        return;
    }
    [self _button:K_MOUSE2 event:event down:YES];
}
- (void)rightMouseUp:(NSEvent *)event    { [self _button:K_MOUSE2 event:event down:NO]; }
- (void)otherMouseDown:(NSEvent *)event  { [self _button:K_MOUSE3 event:event down:YES]; }
- (void)otherMouseUp:(NSEvent *)event    { [self _button:K_MOUSE3 event:event down:NO]; }

- (void)scrollWheel:(NSEvent *)event {
    if (self.workspace != nil) {
        [super scrollWheel:event];
        return;
    }
    CGFloat delta = event.deltaY;
    if (delta == 0) return;
    // a wheel notch is a key pressed and let go (Sys_GetEvent's)
    int key = delta > 0 ? K_MWHEELUP : K_MWHEELDOWN;
    [self.player key:key down:YES];
    [self.player key:key down:NO];
}

#pragma mark - Keys

/// rvGEWorkspace::HandleKeyDown, and the arrange menu's keys: the arrows
/// nudge (shift sizes), Escape lets the selection go, Delete deletes,
/// ⌘] ⌘[ bring forward and send backward (shift: to the front, the back).
- (BOOL)_designKeyDown:(NSEvent *)event {
    rvGEWorkspace *design = self.workspace;
    if (design == nil) return NO;
    NSString *characters = event.charactersIgnoringModifiers;
    if (characters.length == 0) return NO;
    unichar c = [characters characterAtIndex:0];
    NSEventModifierFlags flags = event.modifierFlags;
    BOOL shift = (flags & NSEventModifierFlagShift) != 0;
    BOOL command = (flags & NSEventModifierFlagCommand) != 0;
    if (command) {
        if (c == ']' || c == '}') {
            shift ? [design bringSelectedToFront] : [design bringSelectedForward];
        } else if (c == '[' || c == '{') {
            shift ? [design sendSelectedToBack] : [design sendSelectedBackward];
        } else {
            return NO;
        }
    } else {
        switch (c) {
            case NSLeftArrowFunctionKey:  [design nudgeX:-1 y:0 size:shift]; break;
            case NSRightArrowFunctionKey: [design nudgeX:1 y:0 size:shift]; break;
            case NSUpArrowFunctionKey:    [design nudgeX:0 y:-1 size:shift]; break;
            case NSDownArrowFunctionKey:  [design nudgeX:0 y:1 size:shift]; break;
            case 27:                      [design.selections clear]; break;
            case 8: case 127: case NSDeleteFunctionKey: [design deleteSelected]; break;
            default: return NO;
        }
    }
    [self _designChanged];
    return YES;
}

- (BOOL)validateMenuItem:(NSMenuItem *)item {
    rvGEWorkspace *design = self.workspace;
    if (item.action == @selector(copy:) || item.action == @selector(delete:)) {
        return design != nil && [design.selections num] > 0;
    }
    if (item.action == @selector(paste:)) {
        return design != nil && [design canPaste];
    }
    return YES;
}

- (IBAction)copy:(id)sender {
    [self.workspace copySelected];
}

- (IBAction)paste:(id)sender {
    if (self.workspace == nil) return;
    [self.workspace paste];
    [self _designChanged];
}

- (IBAction)delete:(id)sender {
    if (self.workspace == nil) return;
    [self.workspace deleteSelected];
    [self _designChanged];
}

- (NSMenu *)menuForEvent:(NSEvent *)event {
    if (self.workspace == nil) return [super menuForEvent:event];
    [self _syncWorkspaceRect];
    return [self.designDelegate guiView:self designMenuAt:[self _pointOf:event]];
}

- (void)keyDown:(NSEvent *)event {
    if ([self _designKeyDown:event]) return;
    if ((event.modifierFlags & NSEventModifierFlagCommand) || self.workspace != nil) {
        [super keyDown:event];      // the menus'
        return;
    }
    int key = UDGuiKeyForEvent(event);
    if (key != 0) {
        [self.player key:key down:YES];
    }
    // dhewm3 sends the text a key types as SE_CHAR (Latin-1), and Backspace
    if (key == K_BACKSPACE) {
        [self.player character:K_BACKSPACE];
        return;
    }
    NSString *text = event.characters ?: @"";
    for (NSUInteger i = 0; i < text.length; i++) {
        unichar c = [text characterAtIndex:i];
        if (c >= 32 && c != 127 && c <= 0xFF) {
            [self.player character:c];
        }
    }
}

- (void)keyUp:(NSEvent *)event {
    if (self.workspace != nil) return;
    int key = UDGuiKeyForEvent(event);
    if (key != 0) {
        [self.player key:key down:NO];
    }
}

- (void)flagsChanged:(NSEvent *)event {
    if (self.workspace != nil) {
        [super flagsChanged:event];
        return;
    }
    NSEventModifierFlags flags = event.modifierFlags;
    static const struct { NSEventModifierFlags flag; int key; } keys[] = {
        { NSEventModifierFlagShift, K_SHIFT },
        { NSEventModifierFlagControl, K_CTRL },
        { NSEventModifierFlagOption, K_ALT },
    };
    for (size_t i = 0; i < sizeof(keys) / sizeof(keys[0]); i++) {
        BOOL was = (_modifiers & keys[i].flag) != 0, is = (flags & keys[i].flag) != 0;
        if (was != is) {
            [self.player key:keys[i].key down:is];
        }
    }
    _modifiers = flags;
}

@end
