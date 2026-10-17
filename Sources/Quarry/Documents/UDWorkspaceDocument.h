#import <AppKit/AppKit.h>
@class UDWorkspace;

NS_ASSUME_NONNULL_BEGIN

/**
 * NSDocument subclass for ".qworkspace" files.
 * Reads/writes the workspace JSON, owns the Workspace model,
 * and creates the WorkspaceWindowController.
 */
@interface UDWorkspaceDocument : NSDocument

@property (nonatomic, strong, nullable) UDWorkspace *workspace;

@end

NS_ASSUME_NONNULL_END
