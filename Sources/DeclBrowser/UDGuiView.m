#import "UDGuiView.h"
#import "UDGuiPlayer.h"
#import "idWindow.h"
#import "idDeviceContext.h"
#import "idUserInterface.h"
#import "UDGuiGLView.h"
#import "UDSoftwareRenderer.h"

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
    if (_glView == nil) {
        self.needsDisplay = YES;
        return;
    }
    UDSoftwareRenderer *renderer = self.player.manager.renderer;
    _glView.pictureSize = NSMakeSize(renderer.width, renderer.height);
    _glView.guiRect = self.guiRect;
    _glView.triangles = self.player.triangles;
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
    NSImage *frame = self.player.frame;
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

- (void)_moveMouse:(NSEvent *)event {
    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    [self.player moveMouseTo:[self guiPointFromView:point]];
}

- (void)mouseMoved:(NSEvent *)event        { [self _moveMouse:event]; }
- (void)mouseDragged:(NSEvent *)event      { [self _moveMouse:event]; }
- (void)rightMouseDragged:(NSEvent *)event { [self _moveMouse:event]; }
- (void)otherMouseDragged:(NSEvent *)event { [self _moveMouse:event]; }

- (void)_button:(int)key event:(NSEvent *)event down:(BOOL)down {
    if (down) {
        [self.window makeFirstResponder:self];
    }
    [self _moveMouse:event];
    [self.player key:key down:down];
}

- (void)mouseDown:(NSEvent *)event       { [self _button:K_MOUSE1 event:event down:YES]; }
- (void)mouseUp:(NSEvent *)event         { [self _button:K_MOUSE1 event:event down:NO]; }
- (void)rightMouseDown:(NSEvent *)event  { [self _button:K_MOUSE2 event:event down:YES]; }
- (void)rightMouseUp:(NSEvent *)event    { [self _button:K_MOUSE2 event:event down:NO]; }
- (void)otherMouseDown:(NSEvent *)event  { [self _button:K_MOUSE3 event:event down:YES]; }
- (void)otherMouseUp:(NSEvent *)event    { [self _button:K_MOUSE3 event:event down:NO]; }

- (void)scrollWheel:(NSEvent *)event {
    CGFloat delta = event.deltaY;
    if (delta == 0) return;
    // a wheel notch is a key pressed and let go (Sys_GetEvent's)
    int key = delta > 0 ? K_MWHEELUP : K_MWHEELDOWN;
    [self.player key:key down:YES];
    [self.player key:key down:NO];
}

#pragma mark - Keys

- (void)keyDown:(NSEvent *)event {
    if (event.modifierFlags & NSEventModifierFlagCommand) {
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
    int key = UDGuiKeyForEvent(event);
    if (key != 0) {
        [self.player key:key down:NO];
    }
}

- (void)flagsChanged:(NSEvent *)event {
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
