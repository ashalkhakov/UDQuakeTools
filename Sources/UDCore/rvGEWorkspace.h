/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 * rvGEWorkspace.h — the GUI editor's workspace (tools/guied/GEWorkspace.h,
 * GEWorkspace.cpp, GEWorkspaceFile.cpp), ported: a GUI loaded for editing
 * (every window kept, each with its rvGEWindowWrapper) and written back as
 * the editor writes it.
 *
 * Its window — the view, its events, its cursor — is Decl Browser's
 * (UDGuiView); this is the rest: the selection, the edits, what the mouse
 * does to them (HandleLButtonDown, HandleMouseMove, HandleLButtonUp, given
 * the window's points), and what is drawn over the GUI.
 */

#import <Foundation/Foundation.h>
#import "idMath.h"
#import "rvGESelectionMgr.h"

@class idUserInterfaceManager, idUserInterfaceLocal, idWindow, rvGEOptions, rvGEModifierStack, UDOverlay;

NS_ASSUME_NONNULL_BEGIN

@interface rvGEWorkspace : NSObject

/// A workspace on @a manager, which edits from now on (com_editors |=
/// EDITOR_GUI): its GUIs keep every window, wrapped.
- (instancetype)initWithManager:(idUserInterfaceManager *)manager;

@property (nonatomic, strong, readonly) idUserInterfaceManager *manager;
/// The GUI being edited (mInterface).
@property (nonatomic, strong, readonly, nullable) idUserInterfaceLocal *interface;

/// LoadFile: the GUI at @a qpath, read from the file system; or from @a
/// text, as if it were @a qpath's. The desktop expanded. NO when it does
/// not load.
- (BOOL)loadFile:(NSString *)qpath;
- (BOOL)loadText:(NSString *)text path:(NSString *)qpath;

/// SaveFile's text: WriteWindow of the desktop, depth 1 — what saving
/// writes, CRLF and all.
- (NSString *)text;

/// WriteWindow: @a window, and its children, at @a depth, appended to
/// @a out; nothing for a window without a wrapper or deleted.
- (void)writeWindow:(idWindow *)window depth:(int)depth into:(NSMutableString *)out;

#pragma mark The canvas

@property (nonatomic, strong, readonly) rvGEOptions *options;
@property (nonatomic, strong, readonly) rvGESelectionMgr *selections;
@property (nonatomic, strong, readonly) rvGEModifierStack *modifiers;
/// Whether it has been edited since it was loaded (or saved).
@property (nonatomic) BOOL modified;

/// mRect: where the GUI's 640x480 is in the window, its pixels, y down.
@property (nonatomic) idRectangle rect;

- (idVec2)windowToWorkspacePoint:(idVec2)point;
- (idRectangle)windowToWorkspaceRect:(idRectangle)rect;
- (idVec2)workspaceToWindowPoint:(idVec2)point;
- (idRectangle)workspaceToWindowRect:(idRectangle)rect;

/// HandleLButtonDown, HandleMouseMove, HandleLButtonUp: the mouse at
/// ( @a x, @a y ) in the window, the shift key held or not, the time in
/// milliseconds (Sys_Milliseconds).
- (void)mouseDownAtX:(float)x y:(float)y shift:(BOOL)shift time:(int)time;
- (void)mouseMoveToX:(float)x y:(float)y time:(int)time;
- (void)mouseUp;
/// What a drag is doing (HT_NONE when there is none), and what the cursor
/// over ( @a x, @a y ) would do (UpdateCursor's).
@property (nonatomic, readonly) rvGEHitTest dragType;
- (rvGEHitTest)cursorTypeAtX:(float)x y:(float)y;

/// AddModifierMove, AddModifierSize: the selection moved by ( @a x, @a y ),
/// its sides by @a l, @a t, @a r, @a b, in the workspace's units; snapped to
/// the grid if @a snap.
- (void)addModifierMove:(NSString *)modName x:(float)x y:(float)y snap:(BOOL)snap;
- (void)addModifierSize:(NSString *)modName l:(float)l t:(float)t r:(float)r b:(float)b snap:(BOOL)snap;

/// RenderGrid and the selections' Render: what is drawn over the GUI.
- (void)renderOverlayInto:(UDOverlay *)overlay;

@end

NS_ASSUME_NONNULL_END
