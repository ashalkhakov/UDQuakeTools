/*---------------------------------------------------------------------------------------------
 *  UQEditorHost.h
 *
 *  One of Quarry's editors in a UDCode tab (-[UDExtension
 *  workbench:editorForDocument:]): its view the tab's, its inspector panes
 *  (UDInspecting: a material's Material and Stage) the inspector's tabs
 *  (UDCodeKit's UDEditorPanes), each with its badge; its issues its
 *  document's, which UDCode's Issues navigator lists.
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

/// The inspector's tab of @a title chosen (the editor's -showInspectorPaneTitled:).
- (void)showInspectorPaneTitled:(NSString *)title;

@end

NS_ASSUME_NONNULL_END
