#import <AppKit/AppKit.h>

@class UDGuiPlayer;

NS_ASSUME_NONNULL_BEGIN

/**
 * A running GUI on screen: its player's frame, the GUI's 640x480 fitted to
 * the view (its aspect kept, black around it), and the view's mouse and
 * keys sent to the player as the game sends them (dhewm3's SDL events: a
 * key as SE_KEY, the text it types as SE_CHAR; the mouse absolute).
 *
 * The frame is drawn with GL (a UDGuiGLView over the view, its player's
 * triangles), or, where there is no GL, the player's software picture.
 *
 * In the shape of RDLKit's design canvas (RDLCanvasView): flipped, the
 * GUI's space under one transform, drawn in one -drawRect:, hover from a
 * tracking rect (GNUstep has no NSTrackingArea) — so the GUI editor's
 * canvas is this view with selection drawn over it.
 */
@interface UDGuiView : NSView

@property (nonatomic, weak, nullable) UDGuiPlayer *player;

/// Whether the frames are drawn with GL; the GL view, when they are.
@property (nonatomic, readonly) BOOL drawsWithGL;
@property (nonatomic, strong, readonly, nullable) NSView *glView;

/// The player's last frame shown.
- (void)showFrame;

/// The GUI's 640x480 in the view, and the scale it is drawn at.
@property (nonatomic, readonly) NSRect guiRect;
@property (nonatomic, readonly) CGFloat scale;
/// A point of the view in the GUI's space (y down), and back.
- (NSPoint)guiPointFromView:(NSPoint)point;
- (NSPoint)viewPointFromGui:(NSPoint)point;

@end

/// The engine's key (keyNum_t) for a key event's key; 0 when it has none.
int UDGuiKeyForEvent(NSEvent *event);

NS_ASSUME_NONNULL_END
