#import <AppKit/AppKit.h>

@class UDWorkspace, idUserInterfaceManager, idUserInterfaceLocal, UDTriangleList, UDImage;

NS_ASSUME_NONNULL_BEGIN

/**
 * A GUI running as the game runs a menu (idSessionLocal's guiActive): on the
 * game's clock, the events the game would send it (the mouse as dhewm3
 * sends it in a window, SE_MOUSE_ABS; keys; characters; named events), and
 * a frame drawn each tick — Redraw into the GUI model, its surfaces drawn by
 * the software renderer in the 640x480 view, the cursor the GUI's own.
 *
 * What the GUI asks of the game is logged: the commands HandleEvent
 * returns and the ones it buffers, the sounds it plays, the warnings.
 */
@interface UDGuiPlayer : NSObject

- (instancetype)initWithWorkspace:(nullable UDWorkspace *)workspace;

@property (nonatomic, strong, readonly) idUserInterfaceManager *manager;
@property (nonatomic, strong, readonly, nullable) idUserInterfaceLocal *gui;

/// The GUI at @a qpath, read from the file system; or its text (an
/// editor's, unsaved), as if it were @a qpath's. Activated at time 0 and
/// drawn; NO when it does not load (the GUI is then what the engine makes).
- (BOOL)loadFile:(NSString *)qpath;
- (BOOL)loadText:(NSString *)text path:(NSString *)qpath;
/// Loaded (from the file for no @a text), and run on to @a time, the named
/// events sent so far sent again (-seekTo:).
- (BOOL)loadText:(nullable NSString *)text path:(NSString *)qpath time:(int)time;

/// The last load's parse errors and warnings (idParser's: "file", "line",
/// "message", "error").
@property (nonatomic, copy, readonly) NSArray<NSDictionary *> *diagnostics;

#pragma mark The clock

/// Whether the clock runs (YES at first): a frame each USERCMD_MSEC.
@property (nonatomic) BOOL playing;
/// The GUI's time, in milliseconds since it was activated.
@property (nonatomic, readonly) int time;
/// One frame on: USERCMD_MSEC later, drawn. (Paused, the clock is still.)
- (void)step;
/// Loaded again, from its time 0, the named events sent forgotten.
- (void)restart;
/// At @a time, drawn: run on to it a frame at a time; before the time it
/// is at, from its time 0 again, the named events sent on the way sent
/// again at their times (the mouse and the keys not).
- (void)seekTo:(int)time;
/// The windows (by name) shown (YES) or hidden (NO) whatever their
/// "visible" and the scripts': the GUI editor's own. Set before a load or a
/// seek.
@property (nonatomic, copy, nullable) NSDictionary<NSString *, NSNumber *> *windowVisibility;
/// A frame at the time it is at, drawn now.
- (void)renderFrame;

/// The last frame's triangles: what the ambient pass draws it with (a GL
/// view draws them).
@property (nonatomic, strong, readonly, nullable) UDTriangleList *triangles;
/// Whether each frame is also drawn in software, into -frame (YES at first:
/// where there is no GL, and for tests).
@property (nonatomic) BOOL drawsPicture;
/// The last frame drawn in software, 640x480.
@property (nonatomic, strong, readonly, nullable) NSImage *frame;

/// The view it is shown in: the clock runs only while that is in a window
/// (its tab the one shown). None, and it runs.
@property (nonatomic, weak, nullable) NSView *view;

/// Told after each frame (target-action; the sender is the player).
@property (nonatomic, weak, nullable) id target;
@property (nonatomic, nullable) SEL action;

/// A renderer's picture as an image, opaque (what the screen shows).
+ (NSImage *)imageOf:(UDImage *)image;

#pragma mark Input

/// The cursor to @a point, in the GUI's 640x480 (y down).
- (void)moveMouseTo:(NSPoint)point;
/// A key (keyNum_t: K_MOUSE1, K_ENTER, 'a', ...) pressed or let go.
- (void)key:(int)key down:(BOOL)down;
/// A character typed.
- (void)character:(unichar)character;
/// A named event, as the game sends it (HandleNamedEvent).
- (void)sendNamedEvent:(NSString *)name;
/// The named events the GUI's windows have (onNamedEvent), sorted, once each.
@property (nonatomic, copy, readonly) NSArray<NSString *> *namedEvents;

#pragma mark What it asks of the game

/// Lines, oldest first: "command …", "sound …", "warning …".
@property (nonatomic, copy, readonly) NSArray<NSString *> *log;
- (void)clearLog;

@end

NS_ASSUME_NONNULL_END
