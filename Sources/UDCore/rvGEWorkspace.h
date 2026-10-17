/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 * rvGEWorkspace.h — the GUI editor's workspace (tools/guied/GEWorkspace.h,
 * GEWorkspace.cpp, GEWorkspaceFile.cpp), ported: a GUI loaded for editing
 * (every window kept, each with its rvGEWindowWrapper) and written back as
 * the editor writes it.
 *
 * What the engine's workspace also is, its window — the canvas, the mouse,
 * zoom — is Decl Browser's (UDGuiView, UDGuiEditorViewController); this is
 * the part that edits the GUI.
 */

#import <Foundation/Foundation.h>

@class idUserInterfaceManager, idUserInterfaceLocal, idWindow;

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

@end

NS_ASSUME_NONNULL_END
