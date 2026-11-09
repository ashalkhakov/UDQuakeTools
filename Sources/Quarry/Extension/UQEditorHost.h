/*---------------------------------------------------------------------------------------------
 *  UQEditorHost.h
 *
 *  One of Quarry's editors in a UDCode tab (-[UDExtension
 *  workbench:editorForDocument:]): its view the tab's, its inspector panes
 *  (UDInspecting: a material's Material and Stage) the inspector's tabs
 *  (UDCodeKit's UDEditorPanes), each with its badge; its issues its
 *  document's, which UDCode's Issues navigator lists. An editor with
 *  navigator panes of its own (UDNavigating: a GUI's Windows) has them on
 *  the left of its view, in a split (UQEditorHost.xib), as CoreData
 *  Builder's and XForms Designer's outlines are.
 *--------------------------------------------------------------------------------------------*/

#import <AppKit/AppKit.h>
#import <UDCodeKit/UDCodeKit.h>

@class UDBaseEditorViewController;

NS_ASSUME_NONNULL_BEGIN

@protocol UDEditorHosting;

@interface UQEditorHost : NSViewController <UDEditorPanes>

- (instancetype)initWithEditor:(UDBaseEditorViewController *)editor
                      document:(UDCodeDocument *)document
                     workbench:(nullable id<UDWorkbench>)workbench;

@property (nonatomic, readonly) UDBaseEditorViewController *editor;
@property (nonatomic, readonly) UDCodeDocument *document;
@property (nonatomic, weak, readonly, nullable) id<UDWorkbench> workbench;

/// With navigator panes: the split, the panes' tabs, the editor's place.
@property (nonatomic, weak, readonly, nullable) IBOutlet NSSplitView *splitView;
@property (nonatomic, weak, readonly, nullable) IBOutlet NSTabView *navigatorTabs;
@property (nonatomic, weak, readonly, nullable) IBOutlet NSView *editorHost;

/// The inspector's tab of @a title chosen (the editor's -showInspectorPaneTitled:).
- (void)showInspectorPaneTitled:(NSString *)title;

@end

NS_ASSUME_NONNULL_END
