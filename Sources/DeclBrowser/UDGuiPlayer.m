#import "UDGuiPlayer.h"
#import "idFileSystem.h"   // AppKit before UDDeclCodec's CoreData (GNUstep)
#import "UDWorkspace.h"
#import "idUserInterface.h"
#import "idStr.h"
#import "idDeviceContext.h"
#import "idGuiModel.h"
#import "UDSoftwareRenderer.h"
#import "UDImageProgram.h"

/// A named event sent, and when.
@interface UDGuiPlayerEvent : NSObject
@property (nonatomic, copy) NSString *name;
@property (nonatomic) int time;
@end

@implementation UDGuiPlayerEvent
@end

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
/// The named events sent since the last restart, in time order; how many
/// of them were sent since the last load.
@property (nonatomic, strong) NSMutableArray<UDGuiPlayerEvent *> *eventTrack;
@property (nonatomic) NSUInteger replayed;
/// The visible vars -windowVisibility names, each followed by what it is
/// to be; nil until found, after each load.
@property (nonatomic, strong, nullable) NSArray *visibilityVars;
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
        _eventTrack = [NSMutableArray array];
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
    return [self loadText:nil path:qpath time:0];
}

- (BOOL)loadText:(NSString *)text path:(NSString *)qpath {
    return [self loadText:text path:qpath time:0];
}

- (BOOL)loadText:(nullable NSString *)text path:(NSString *)qpath time:(int)time {
    self.path = qpath;
    self.text = text;
    BOOL loaded = [self _load];
    [self seekTo:time];
    return loaded;
}

- (void)restart {
    if (self.path != nil) {
        [self.eventTrack removeAllObjects];
        [self _askForText];
        [self _load];
        [self renderFrame];
    }
}

/// The text to load again, from its text source, if it has another.
- (void)_askForText {
    id source = self.textSource;
    SEL action = self.textSourceAction;
    if (source == nil || action == NULL || ![source respondsToSelector:action]) return;
    NSString *text = ((NSString *(*)(id, SEL, id))[source methodForSelector:action])(source, action, self);
    if (text != nil) {
        self.text = text;
    }
}

- (BOOL)_load {
    if (self.gui != nil) {
        [self.manager deAlloc:self.gui];
    }
    self.manager.editing = self.editing;
    self.gui = [self.manager allocGui];
    BOOL loaded = self.text != nil ? [self.gui initFromText:self.text path:self.path] : [self.gui initFromFile:self.path];
    self.diagnostics = [self.gui.diagnostics copy];
    // idSessionLocal::StartMenu: the key names, then Activate
    [self.gui setKeyBindingNames];
    self.time = 0;
    self.lastTick = [NSDate date];
    self.replayed = 0;
    self.visibilityVars = nil;
    _span = MAX(5000, [UDGuiPlayer _timelineLengthOf:[self.gui getDesktop]]);
    _runsEveryFrame = [UDGuiPlayer _runsEveryFrame:[self.gui getDesktop]];
    [self _handleCommand:[self.gui activate:YES time:self.time]];
    return loaded;
}

/// The latest "onTime" of @a window's and its children's, and a second.
+ (int)_timelineLengthOf:(nullable idWindow *)window {
    if (window == nil) return 0;
    int length = 0;
    for (idTimeLineEvent *event in window->timeLineEvents) {
        length = MAX(length, event->time + 1000);
    }
    for (int i = 0; i < [window getChildCount]; i++) {
        length = MAX(length, [self _timelineLengthOf:[window getChild:i]]);
    }
    return length;
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

- (void)seekTo:(int)time {
    if (self.gui == nil) return;
    time = MAX(time, 0);
    if (time < self.time) {
        [self _askForText];
        [self _load];
    }
    // the frames between, run and not drawn; but for a GUI that runs no
    // scripts every frame (onEvent), only those where something is due:
    // the others would only take its transitions and registers on, which
    // the next frame run takes from the time and the state as they are
    idUserInterfaceManager *manager = self.manager;
    BOOL everyFrame = self.stepsEveryFrame || self.runsEveryFrame;
    while (self.time + USERCMD_MSEC < time) {
        int next = self.time + USERCMD_MSEC;
        if (!everyFrame) {
            int due = [self _nextDueFrame];
            next = MAX(next, due);
            if (next >= time) break;
        }
        self.time = next;
        [self _runFrameDrawing:NO];
    }
    if (!everyFrame) {
        // the last frame before it run too: the frame drawn at the time,
        // under USERCMD_MSEC after it, runs no time events of its own
        // (RunTimeEvents's), so shows them as that one left them
        int last = self.time + (time - self.time - 1) / USERCMD_MSEC * USERCMD_MSEC;
        if (last > self.time) {
            self.time = last;
            [self _runFrameDrawing:NO];
        }
    }
    self.time = time;
    self.lastTick = [NSDate date];
    [self renderFrame];
    [manager.guiModel clear];
}

/// A frame at the time it is at, into the GUI model (@a drawing; else its
/// time events alone): the named events sent before it (again, after a
/// load) sent, the hidden windows hidden, the GUI redrawn.
- (void)_runFrameDrawing:(BOOL)drawing {
    idUserInterfaceManager *manager = self.manager;
    manager.ticNumber = self.time / USERCMD_MSEC;
    NSArray<UDGuiPlayerEvent *> *track = self.eventTrack;
    while (self.replayed < track.count && track[self.replayed].time < self.time) {
        [self.gui handleNamedEvent:track[self.replayed].name];
        self.replayed++;
    }
    [self _applyVisibility];
    if (drawing) {
        [manager.guiModel clear];
        [self.gui redraw:self.time];
    } else {
        [self.gui runTimeEvents:self.time];
    }
    [self _takeMessages];
}

/// The first frame (on this one's grid, USERCMD_MSEC apart) where a time
/// event is due (idWindow::Time's: its window's timeLine and its time
/// passed), a named event sent is to be sent again, or a window's
/// timeline starts (its first Time sets it).
- (int)_nextDueFrame {
    long due = INT_MAX;
    NSArray<UDGuiPlayerEvent *> *track = self.eventTrack;
    if (self.replayed < track.count) {
        due = track[self.replayed].time + 1;      // sent before the first frame after it
    }
    due = MIN(due, [self _nextDueOf:[self.gui getDesktop]]);
    if (due == INT_MAX) return INT_MAX;
    long frames = (due - self.time + USERCMD_MSEC - 1) / USERCMD_MSEC;
    return (int)MIN((long)INT_MAX, self.time + MAX(frames, 1L) * USERCMD_MSEC);
}

- (long)_nextDueOf:(nullable idWindow *)window {
    if (window == nil) return INT_MAX;
    long due = INT_MAX;
    if (!window->noTime.data) {
        if (window->timeLine == -1) {
            if (window->timeLineEvents.count > 0) due = self.time + 1;
        } else {
            for (idTimeLineEvent *event in window->timeLineEvents) {
                if (event->pending) due = MIN(due, (long)window->timeLine + event->time);
            }
        }
    }
    for (int i = 0; i < [window getChildCount]; i++) {
        due = MIN(due, [self _nextDueOf:[window getChild:i]]);
    }
    return due;
}

/// Whether a window of @a window's tree has an onEvent script (ON_FRAME,
/// run each frame).
+ (BOOL)_runsEveryFrame:(nullable idWindow *)window {
    if (window == nil) return NO;
    if (window->scripts[ON_FRAME] != nil) return YES;
    for (int i = 0; i < [window getChildCount]; i++) {
        if ([self _runsEveryFrame:[window getChild:i]]) return YES;
    }
    return NO;
}

/// The windows the editor shows or hides, so, whatever a script made them
/// (and, as a script's "set" does, no longer what an expression makes them).
- (void)_applyVisibility {
    if (self.visibilityVars == nil) {
        // found once a load
        NSMutableArray<idWinVar *> *vars = [NSMutableArray array];
        idWindow *desktop = [self.gui getDesktop];
        NSDictionary<NSString *, NSNumber *> *visibility = self.windowVisibility;
        for (NSString *name in visibility) {
            if (desktop == nil) break;
            idDrawWin *window = [name ud_iequals:[desktop getName]] ? nil : [desktop findChildByName:name];
            idWinVar *visible = window == nil ? [desktop getWinVarByName:@"visible"]
                              : window.win != nil ? [window.win getWinVarByName:@"visible"] : [window.simp getWinVarByName:@"visible"];
            if ([visible isKindOfClass:[idWinBool class]]) {
                [vars addObject:visible];
                [vars addObject:(idWinVar *)visibility[name]];
            }
        }
        self.visibilityVars = vars;
    }
    NSArray *vars = self.visibilityVars;
    for (NSUInteger i = 0; i + 1 < vars.count; i += 2) {
        idWinBool *visible = vars[i];
        [visible setData:[vars[i + 1] boolValue]];
        [visible setEval:NO];
    }
}

- (void)setWindowVisibility:(NSDictionary<NSString *, NSNumber *> *)windowVisibility {
    _windowVisibility = [windowVisibility copy];
    self.visibilityVars = nil;
}

- (void)renderFrame {
    if (self.gui == nil) return;
    idUserInterfaceManager *manager = self.manager;

    // idSessionLocal::Draw: the GUI redrawn at the frame's time, into the
    // GUI model; the model's surfaces as the ambient pass draws them, over
    // black
    [self _runFrameDrawing:YES];
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
    // after those sent before it, and in the track at its time: a seek back
    // sends it again
    NSMutableArray<UDGuiPlayerEvent *> *track = self.eventTrack;
    while (self.replayed < track.count && track[self.replayed].time <= self.time) {
        [self.gui handleNamedEvent:track[self.replayed].name];
        self.replayed++;
    }
    UDGuiPlayerEvent *event = [[UDGuiPlayerEvent alloc] init];
    event.name = name;
    event.time = self.time;
    [track insertObject:event atIndex:self.replayed];
    self.replayed++;
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
