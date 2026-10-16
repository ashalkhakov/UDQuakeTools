#import <AppKit/AppKit.h>

@class UDTriangleList;

NS_ASSUME_NONNULL_BEGIN

// GL is deprecated on macOS (10.14) and still there; if it goes, ANGLE
// (OpenGL ES over Metal) takes its place under the same drawing code.
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"

/**
 * A frame's triangles (UDSoftwareRenderer's list: what the ambient pass
 * draws a GUI with) drawn with GL, as the engine draws them: each texel
 * modulated by its vertex color and its stage's constant color
 * (GL_MODULATE), blended and masked as its stage's drawStateBits set GL
 * (GL_State), bilinear, repeated or clamped as its stage's texture is.
 *
 * A 3.2 core context on macOS; on GNUstep, the context its NSOpenGLView
 * gives (GLX), the shaders' GLSL 1.20 then. It takes no events: its
 * superview, a UDGuiView, has them.
 */
@interface UDGuiGLView : NSOpenGLView

/// A GL view, or nil where there is no GL to draw with (no pixel format).
+ (nullable instancetype)viewWithFrame:(NSRect)frame;

/// What is drawn: a list in a picture of @a pictureSize (the renderer's),
/// fitted into @a guiRect (the view's own coordinates, y down from its
/// top), black around it.
@property (nonatomic, strong, nullable) UDTriangleList *triangles;
@property (nonatomic) NSSize pictureSize;
@property (nonatomic) NSRect guiRect;

/// The GUI's rect as GL drew it last, read back: RGBA, its top row first,
/// at the backing's resolution (a test's).
- (nullable NSBitmapImageRep *)readPicture;

/// What GL says it is (its version and renderer), once it has drawn.
@property (nonatomic, copy, readonly, nullable) NSString *glDescription;

@end

#pragma clang diagnostic pop

NS_ASSUME_NONNULL_END
