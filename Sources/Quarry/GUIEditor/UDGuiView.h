#import <AppKit/AppKit.h>

@class UDGuiPlayer, UDTriangleList, UDOverlay, rvGEWorkspace, UDGuiView;

/// What a designing view asks its owner.
@protocol UDGuiViewDesignDelegate <NSObject>
/// The menu for a right click at @a point (the view's): the design's
/// commands, the windows under it to select.
- (nullable NSMenu *)guiView:(UDGuiView *)view designMenuAt:(NSPoint)point;
@end

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

/// A frame shown: its triangles (drawn with GL) or its picture (in
/// software), in a picture of @a pictureSize; @a overlay over it, in the
/// view's points (the GUI editor's grid and selections).
- (void)showTriangles:(nullable UDTriangleList *)triangles picture:(nullable NSImage *)picture
          pictureSize:(NSSize)pictureSize overlay:(nullable UDOverlay *)overlay;

/// Designing: the workspace the mouse edits instead of the player's GUI
/// being run (rvGEWorkspace's HandleLButtonDown, …), its rect kept the
/// GUI's in the view; the cursor what it would do. Nil, and it runs.
@property (nonatomic, weak, nullable) rvGEWorkspace *workspace;
/// Told after the mouse has edited the workspace or its selection
/// (target-action; the sender is the view).
@property (nonatomic, weak, nullable) id designTarget;
@property (nonatomic, nullable) SEL designAction;
@property (nonatomic, weak, nullable) id<UDGuiViewDesignDelegate> designDelegate;

/// Edit's Copy, Paste and Delete, while designing: the selected windows'.
- (IBAction)copy:(nullable id)sender;
- (IBAction)paste:(nullable id)sender;
- (IBAction)delete:(nullable id)sender;

/// The GUI's 640x480 in the view, and the scale it is drawn at.
@property (nonatomic, readonly) NSRect guiRect;
@property (nonatomic, readonly) CGFloat scale;

/// rvGEWorkspace's zoom: one of its levels (EZoomLevel, 1 to 8: 25% to
/// 300%), or UDGuiZoomFit, the GUI fitted to the view (not the engine's;
/// the view opens so). Changed, the GUI centered again.
@property (nonatomic) NSInteger zoom;
/// The scale as a percentage, as the status bar shows it.
@property (nonatomic, readonly) int zoomPercent;
/// ZoomIn and ZoomOut: a level up or down (from fitted, the next one past
/// the fitted scale); the wheel's with ⌘, and a pinch's.
- (IBAction)zoomIn:(nullable id)sender;
- (IBAction)zoomOut:(nullable id)sender;
- (IBAction)zoomToFit:(nullable id)sender;
/// How far the GUI is scrolled from centered, in the view's points (the
/// engine's scroll bars): only while it is larger than the view.
@property (nonatomic) NSPoint scrollOffset;
/// Told after the zoom or the scroll changed (target-action; the sender
/// is the view).
@property (nonatomic, weak, nullable) id zoomTarget;
@property (nonatomic, nullable) SEL zoomAction;
/// A point of the view in the GUI's space (y down), and back.
- (NSPoint)guiPointFromView:(NSPoint)point;
- (NSPoint)viewPointFromGui:(NSPoint)point;

@end

/// UDGuiView's zoom when the GUI is fitted to the view.
extern const NSInteger UDGuiZoomFit;

/// The engine's key (keyNum_t) for a key event's key; 0 when it has none.
int UDGuiKeyForEvent(NSEvent *event);

NS_ASSUME_NONNULL_END
