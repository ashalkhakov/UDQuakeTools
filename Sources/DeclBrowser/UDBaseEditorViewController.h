#import <AppKit/AppKit.h>

@class UDWorkspace;
@class UDWorkspaceItem;

NS_ASSUME_NONNULL_BEGIN

@class UDBaseDocument;

/**
 * Protocol / base class all editor view controllers must conform to.
 * The workspace window controller embeds -view into an NSTabViewItem.
 */
@interface UDBaseEditorViewController : NSViewController

/** The file item being edited/viewed. Set before the view is loaded. */
@property (nonatomic, strong, nullable) UDWorkspaceItem *item;
@property (nonatomic, weak) UDWorkspace *workspace;

/**
 * The backing document of this editor, if it has one. Subclasses that
 * declare a typed `document` property (text editor, PDA editor, image
 * viewer) are picked up automatically; editors without a document return
 * nil. This is what the Save / Save All / Save As menu plumbing talks to.
 */
@property (nonatomic, readonly, nullable) __kindof UDBaseDocument *editorDocument;

/**
 * Factory: returns the right editor view controller subclass for the given file item,
 * using the fileUTI to dispatch.
 */
+ (instancetype)editorViewControllerForWorkspaceItem:(UDWorkspaceItem *)item inWorkspace:(UDWorkspace *)workspace;

@end

/**
 * An editor with its text beside it: Editor | Source in the workspace
 * window switches between them (a structured decl editor's, a GUI's).
 */
@protocol UDSourceRepresenting <NSObject>
/// The text in place of the editor. Setting NO may leave it up (text the
/// editor cannot take); the switch shows what it is.
@property (nonatomic) BOOL showsSource;
@end

/**
 * A tab of the workspace window's right pane, the inspector: what an
 * editor shows there beside itself (a GUI's state, its log), its badge in
 * the pane's tab bar.
 */
@interface UDInspectorPane : NSObject
+ (instancetype)paneWithTitle:(NSString *)title letters:(NSString *)letters
                          red:(CGFloat)red green:(CGFloat)green blue:(CGFloat)blue view:(NSView *)view;
@property (nonatomic, copy, readonly) NSString *title;
@property (nonatomic, copy, readonly) NSString *letters;
@property (nonatomic, readonly) CGFloat red, green, blue;
@property (nonatomic, strong, readonly) NSView *view;
@end

/// An editor with tabs in the right pane while it is the selected one.
@protocol UDInspecting <NSObject>
@property (nonatomic, readonly) NSArray<UDInspectorPane *> *inspectorPanes;
@end

/**
 * GNUstep layout hardening. gnustep-gui's NSScrollView has no re-entrancy
 * guard around scroller auto-hiding: _autohideScrollers → tile → clip-view
 * setFrame: → the document view re-wraps (NSTextView height follows width)
 * → reflectScrolledClipView: → _autohideScrollers flips the scroller back —
 * an unbounded recursion (stack overflow) whenever content size sits on the
 * show/hide boundary, which the Eau theme's scroller width makes easy to
 * hit. Turning auto-hide off removes the oscillation structurally. No-op on
 * macOS, where auto-hiding is safe.
 */
@interface NSView (UDGNUstepLayoutFixes)
- (void)ud_disableScrollerAutohideRecursively;
@end

NS_ASSUME_NONNULL_END
