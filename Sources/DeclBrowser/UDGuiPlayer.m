#import "UDGuiPlayer.h"
#import "idFileSystem.h"   // AppKit before UDDeclCodec's CoreData (GNUstep)
#import "UDWorkspace.h"
#import "idUserInterface.h"
#import "idDeviceContext.h"
#import "idGuiModel.h"
#import "UDSoftwareRenderer.h"
#import "UDImageProgram.h"

/// The timer's target: the player, not held (the player holds the timer).
@interface UDGuiPlayerTicker : NSObject
@property (nonatomic, weak) UDGuiPlayer *player;
- (void)tick:(NSTimer *)timer;
@end

@interface UDGuiPlayer ()
@property (nonatomic, weak) UDWorkspace *workspace;
@property (nonatomic, strong, readwrite) idUserInterfaceManager *manager;
@property (nonatomic, strong, readwrite, nullable) idUserInterfaceLocal *gui;
@property (nonatomic, copy, readwrite) NSArray<NSDictionary *> *diagnostics;
@property (nonatomic, readwrite) int time;
@property (nonatomic, strong, readwrite, nullable) NSImage *frame;
@property (nonatomic, strong, readwrite, nullable) UDTriangleList *triangles;
@property (nonatomic, strong) NSMutableArray<NSString *> *logLines;
@property (nonatomic, strong, nullable) NSTimer *timer;
/// When the clock last moved on, while it runs.
@property (nonatomic, strong, nullable) NSDate *lastTick;
/// What the last load read, for -restart.
@property (nonatomic, copy, nullable) NSString *path;
@property (nonatomic, copy, nullable) NSString *text;
- (void)_tick;
@end

@implementation UDGuiPlayerTicker

- (void)tick:(NSTimer *)timer {
    UDGuiPlayer *player = self.player;
    if (player == nil) {
        [timer invalidate];
        return;
    }
    [player _tick];
}

@end

@implementation UDGuiPlayer

- (instancetype)initWithWorkspace:(UDWorkspace *)workspace {
    self = [super init];
    if (self) {
        _workspace = workspace;
        _manager = [[idUserInterfaceManager alloc] initWithFileSystem:workspace.fileSystem declManager:workspace.declManager];
        [_manager managerInit];
        _diagnostics = @[];
        _logLines = [NSMutableArray array];
        _playing = YES;
        _drawsPicture = YES;
        [self _takeMessages];
        UDGuiPlayerTicker *ticker = [[UDGuiPlayerTicker alloc] init];
        ticker.player = self;
        _timer = [NSTimer scheduledTimerWithTimeInterval:USERCMD_MSEC / 1000.0 target:ticker selector:@selector(tick:) userInfo:nil repeats:YES];
    }
    return self;
}

- (void)dealloc {
    [_timer invalidate];
}

#pragma mark - Loading

- (BOOL)loadFile:(NSString *)qpath {
    self.path = qpath;
    self.text = nil;
    return [self _load];
}

- (BOOL)loadText:(NSString *)text path:(NSString *)qpath {
    self.path = qpath;
    self.text = text;
    return [self _load];
}

- (void)restart {
    if (self.path != nil) {
        [self _load];
    }
}

- (BOOL)_load {
    if (self.gui != nil) {
        [self.manager deAlloc:self.gui];
    }
    self.gui = [self.manager allocGui];
    BOOL loaded = self.text != nil ? [self.gui initFromText:self.text path:self.path] : [self.gui initFromFile:self.path];
    self.diagnostics = [self.gui.diagnostics copy];
    // idSessionLocal::StartMenu: the key names, then Activate
    [self.gui setKeyBindingNames];
    self.time = 0;
    self.lastTick = [NSDate date];
    [self _handleCommand:[self.gui activate:YES time:self.time]];
    [self renderFrame];
    return loaded;
}

#pragma mark - The clock

- (void)setPlaying:(BOOL)playing {
    _playing = playing;
    self.lastTick = [NSDate date];
}

- (void)_tick {
    if (!self.playing || self.gui == nil) return;
    NSDate *now = [NSDate date];
    NSView *view = self.view;
    if (view != nil && view.window == nil) {
        self.lastTick = now;     // not shown: the clock stands still
        return;
    }
    int elapsed = (int)([now timeIntervalSinceDate:self.lastTick ?: now] * 1000);
    if (elapsed < USERCMD_MSEC) return;
    self.lastTick = now;
    self.time += elapsed;
    [self renderFrame];
}

- (void)step {
    self.time += USERCMD_MSEC;
    self.lastTick = [NSDate date];
    [self renderFrame];
}

- (void)renderFrame {
    if (self.gui == nil) return;
    idUserInterfaceManager *manager = self.manager;
    manager.ticNumber = self.time / USERCMD_MSEC;

    // idSessionLocal::Draw: the GUI redrawn at the frame's time, into the
    // GUI model; the model's surfaces as the ambient pass draws them, over
    // black
    [manager.guiModel clear];
    [self.gui redraw:self.time];
    NSArray *surfaces = [manager.guiModel emitFullScreen];
    UDSoftwareRenderer *renderer = manager.renderer;
    self.triangles = [renderer trianglesOfSurfaces:surfaces time:self.time * 0.001f];
    if (self.drawsPicture) {
        static const float black[4] = { 0, 0, 0, 1 };
        [renderer clearToColor:black];
        [renderer drawTriangles:self.triangles];
        self.frame = [UDGuiPlayer imageOf:[renderer image]];
    }
    [self _takeMessages];

    id target = self.target;
    if (target != nil && self.action != NULL) {
        [NSApp sendAction:self.action to:target from:self];
    }
}

/// The renderer's pixels, opaque: what the screen shows (its alpha is the
/// blending's, never seen).
+ (NSImage *)imageOf:(UDImage *)image {
    NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:image.width pixelsHigh:image.height
                                                                 bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO
                                                                colorSpaceName:NSDeviceRGBColorSpace bytesPerRow:image.width * 4
                                                                  bitsPerPixel:32];
    uint8_t *out = rep.bitmapData;
    memcpy(out, image.pixels.bytes, (size_t)(image.width * image.height * 4));
    for (int i = 0; i < image.width * image.height; i++) {
        out[i * 4 + 3] = 255;
    }
    NSImage *picture = [[NSImage alloc] initWithSize:NSMakeSize(image.width, image.height)];
    [picture addRepresentation:rep];
    return picture;
}

#pragma mark - Input

- (void)_sendEvent:(sysEvent_t)event {
    if (self.gui == nil) return;
    // idSessionLocal::ProcessEvent: guiActive->HandleEvent at the frame's
    // time, what it returns run as the session runs it
    [self _handleCommand:[self.gui handleEvent:&event time:self.time updateVisuals:NULL]];
    [self _takeMessages];
}

- (void)moveMouseTo:(NSPoint)point {
    // dhewm3's in a window: absolute, in a 640x480 "screen" here
    sysEvent_t event = { SE_MOUSE_ABS, (int)lroundf((float)point.x), (int)lroundf((float)point.y) };
    [self _sendEvent:event];
}

- (void)key:(int)key down:(BOOL)down {
    [self.manager setKey:key down:down];
    sysEvent_t event = { SE_KEY, key, down ? 1 : 0 };
    [self _sendEvent:event];
}

- (void)character:(unichar)character {
    sysEvent_t event = { SE_CHAR, character, 0 };
    [self _sendEvent:event];
}

- (void)sendNamedEvent:(NSString *)name {
    if (self.gui == nil) return;
    [self.gui handleNamedEvent:name];
    [self _takeMessages];
}

- (NSArray<NSString *> *)namedEvents {
    NSMutableSet<NSString *> *names = [NSMutableSet set];
    idWindow *desktop = [self.gui getDesktop];
    if (desktop != nil) {
        [self _addNamedEventsOf:desktop to:names];
    }
    return [names.allObjects sortedArrayUsingSelector:@selector(caseInsensitiveCompare:)];
}

- (void)_addNamedEventsOf:(nullable idWindow *)window to:(NSMutableSet<NSString *> *)names {
    if (window == nil) return;
    for (rvNamedEvent *event in window->namedEvents) {
        [names addObject:event->mName];
    }
    for (int i = 0; i < [window getChildCount]; i++) {
        [self _addNamedEventsOf:[window getChild:i] to:names];
    }
}

#pragma mark - The log

- (void)_handleCommand:(NSString *)command {
    if (command.length > 0) {
        [self.logLines addObject:[@"command " stringByAppendingString:command]];
    }
}

/// What the GUI asked of the game since the last time, moved to the log.
- (void)_takeMessages {
    idUserInterfaceManager *manager = self.manager;
    for (NSString *command in manager.bufferedCommands) {
        [self.logLines addObject:[@"command " stringByAppendingString:command]];
    }
    for (NSString *sound in manager.playedSounds) {
        [self.logLines addObject:[@"sound " stringByAppendingString:sound]];
    }
    for (NSString *warning in manager.warnings) {
        [self.logLines addObject:[@"warning " stringByAppendingString:warning]];
    }
    [manager.bufferedCommands removeAllObjects];
    [manager.playedSounds removeAllObjects];
    [manager.warnings removeAllObjects];
}

- (NSArray<NSString *> *)log {
    return [self.logLines copy];
}

- (void)clearLog {
    [self.logLines removeAllObjects];
}

@end
