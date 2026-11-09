/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 * UQTestWindow.h — what Quarry's editors are tested in: a window that is a
 * UDCode window to UDCode's UDQuakeTools extension (UDCodeKit's UDWorkbench,
 * as far as the extension asks one): its project a folder with a
 * .qworkspace, the extension's Decls navigator on its left (UDTreeView), an
 * item chosen opened through the extension (its custom documents, its
 * editors in UQEditorHost), the front editor's inspector panes on its
 * right; Save, undo and an issue chosen as UDCode's window has them.
 */

#import <AppKit/AppKit.h>
#import <UDCodeKit/UDCodeKit.h>

@class UQExtension, UQProject, UQEditorHost, UDGameWorkspace, UDBaseEditorViewController;

NS_ASSUME_NONNULL_BEGIN

@interface UQTestWindow : NSObject <NSWindowDelegate>

/// The window of @a folder (a project with a .qworkspace), its game started;
/// nil when it doesn't start in @a timeout seconds (*error says why).
+ (nullable instancetype)windowOfFolder:(NSString *)folder extension:(UQExtension *)extension
                                timeout:(NSTimeInterval)timeout error:(NSError *_Nullable *_Nullable)error;

@property (nonatomic, readonly) NSWindow *window;
@property (nonatomic, readonly) UQExtension *extension;
@property (nonatomic, readonly) UQProject *quarry;
@property (nonatomic, readonly, nullable) UDGameWorkspace *workspace;

/// The Decls navigator: its tree view, its outline, its filter field.
@property (nonatomic, readonly) UDTreeViewController *tree;
@property (nonatomic, readonly) NSOutlineView *outlineView;
@property (nonatomic, readonly, nullable) NSSearchField *nameFilterField;
- (IBAction)nameFilterChanged:(nullable id)sender;

/// The tabs: each a document, with its editor (a custom document's), the
/// front one shown.
@property (nonatomic, readonly, nullable) UDCodeDocument *selectedDocument;
@property (nonatomic, readonly, nullable) UQEditorHost *selectedHost;
/// The front tab's Quarry editor; nil: a text document's (UDCode's own editor).
@property (nonatomic, readonly, nullable) UDBaseEditorViewController *selectedEditor;
@property (nonatomic, readonly) NSArray<UDBaseEditorViewController *> *allEditors;
@property (nonatomic, readonly) NSArray<UDCodeDocument *> *documents;
- (void)closeAllTabs;

/// The front editor's inspector panes, and where the chosen one is shown.
@property (nonatomic, readonly) NSView *inspectorHost;
@property (nonatomic, readonly) NSArray<NSViewController *> *inspectors;

/// UDWorkbench: a URL (a decl's, a game file's) in its tab.
- (void)showURL:(NSURL *)url;
- (BOOL)showDocument:(UDCodeDocument *)document;
- (BOOL)showEditorInspector:(NSViewController *)inspector;
- (void)showInspectorPaneTitled:(NSString *)title;
/// A game file's tab, at a line (as a definition's place is shown).
- (void)openFileAtPath:(NSString *)path line:(NSInteger)line character:(NSInteger)character length:(NSInteger)length;

/// File > Save: the front document saved, as UDCode's window saves it.
- (IBAction)saveDocument:(nullable id)sender;
/// An issue chosen in the Issues navigator: its editor shows what it is about.
- (void)errorsViewController:(nullable id)controller didSelectDiagnostic:(UDDiagnosticItem *)diagnostic
                     inStore:(nullable UDDiagnosticStore *)store;

/// The Editor menu's commands (UQCommands); the window answers them, and
/// what the front tab's editor answers (UDCode's -supplementalTargetForAction:).
@property (nonatomic, readonly) id commands;
- (BOOL)validateMenuItem:(NSMenuItem *)item;

/// Its tabs closed and its game shut down.
- (void)close;

@end

NS_ASSUME_NONNULL_END
