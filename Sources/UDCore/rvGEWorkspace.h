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
#import "rvGEWindowWrapper.h"

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
/// Not the engine's: so; or, @a below, the window under the point next
/// below the one selected there (the topmost again after the last) chosen,
/// to be dragged: what is under a window over it reached.
- (void)mouseDownAtX:(float)x y:(float)y shift:(BOOL)shift below:(BOOL)below time:(int)time;
/// Not the engine's: the windows a click, the Select menu and a choice
/// below pass through, and their children (the editor's locked ones, and
/// those not drawn at the time it shows).
@property (nonatomic, copy, nullable) NSSet<idWindow *> *passedWindows;
/// The windows under ( @a x, @a y ) in the window, shown, not deleted or
/// passed through, the topmost first (as a click looks for them).
- (NSArray<idWindow *> *)windowsAtX:(float)x y:(float)y;
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

/// rvGEWorkspace::EModifierType: the edits AddModifiers makes of a window.
typedef NS_ENUM(int, rvGEModifierType) {
    MOD_UNKNOWN,
    MOD_DELETE,
    MOD_HIDE,
    MOD_UNHIDE,
    MOD_SHOWHIDDEN,
    MOD_SEND_BACKWARD,
    MOD_BRING_FORWARD,
    MOD_SEND_BACK,
    MOD_BRING_FRONT,
};

/// AddModifiers: @a type's edit of @a window; of the selection (a group of
/// them for more than one window).
- (void)addModifier:(rvGEModifierType)type window:(idWindow *)window;
- (void)addModifierToSelection:(rvGEModifierType)type;

/// rvGEProperties::AddModifier: the selected window's (the one selected)
/// state key @a name made @a value, checked as the window reads it (as it
/// is, else quoted): a "Property Change". NO, and nothing changed, for a
/// value the window does not read, or no one window selected.
- (BOOL)setProperty:(NSString *)name value:(NSString *)value;

/// rvGEProperties::Update's: the selected window's state keys and their
/// values without their quotes, when one window is selected; else nil.
- (nullable NSArray<NSArray<NSString *> *> *)properties;

/// GEItemScriptsDlg's Init: @a window's variables ("definefloat\t\"x\"",
/// a tab, its value), a blank line, its scripts (each its name on a line,
/// its braced text after, a blank line).
- (NSString *)scriptsTextOf:(idWindow *)window;
/// GEItemScriptsDlg's Apply: @a text read into @a window's variables and
/// scripts, as one undoable "Scripts Change" (the engine's changed them as
/// they were); NO, and what is wrong in @a message, for text it cannot read.
- (BOOL)setScriptsText:(NSString *)text of:(idWindow *)window message:(NSString *_Nullable *_Nullable)message;

/// rvGEWorkspace::EItemAlign
typedef NS_ENUM(int, rvGEItemAlign) {
    ALIGN_LEFTS,
    ALIGN_CENTERS,
    ALIGN_RIGHTS,
    ALIGN_TOPS,
    ALIGN_MIDDLES,
    ALIGN_BOTTOMS,
};

/// DeleteSelected: the selection deleted, as one edit.
- (void)deleteSelected;
/// NewWindow: a window of @a type, from @a state, named after its "name"
/// (made unique among the desktop's), not yet anywhere.
- (nullable idWindow *)newWindow:(nullable idDict *)state type:(rvGEWindowType)type;
/// AddWindow: a new window of @a type, 0,0,100,100, on the desktop and
/// selected ("New").
- (nullable idWindow *)addWindow:(rvGEWindowType)type;
/// BringSelectedForward, BringSelectedToFront, SendSelectedToBack,
/// SendSelectedBackward.
- (void)bringSelectedForward;
- (void)bringSelectedToFront;
- (void)sendSelectedToBack;
- (void)sendSelectedBackward;
/// MakeSelectedSameSize, AlignSelected: the others as the first selected.
- (void)makeSelectedSameSizeWidth:(BOOL)changeWidth height:(BOOL)changeHeight;
- (void)alignSelected:(rvGEItemAlign)align;
/// MakeSelectedAChild: the others children of the first selected; NO when
/// it cannot have any.
- (BOOL)makeSelectedAChild;
/// Copy, Paste: the selection to the editor's clipboard (the engine's,
/// shared by its workspaces), and back as new windows on the desktop.
- (void)copySelected;
- (void)paste;
- (BOOL)canPaste;
/// HandleKeyDown's: AddModifierMoveNudge, AddModifierSizeNudge (the arrows,
/// with shift sizing).
- (void)nudgeX:(float)x y:(float)y size:(BOOL)size;
/// HandleRButtonDown's Select menu: the windows under ( @a x, @a y ) in the
/// window, shown and not deleted, children first; the desktop last.
- (NSArray<idWindow *> *)windowsUnderX:(float)x y:(float)y;

/// HideWindow, UnhideWindow, HideSelected, UnhideSelected.
- (void)hideWindow:(idWindow *)window;
- (void)unhideWindow:(idWindow *)window;
- (void)hideSelected;
- (void)unhideSelected;

/// RenderGrid and the selections' Render: what is drawn over the GUI.
- (void)renderOverlayInto:(UDOverlay *)overlay;

@end

NS_ASSUME_NONNULL_END
