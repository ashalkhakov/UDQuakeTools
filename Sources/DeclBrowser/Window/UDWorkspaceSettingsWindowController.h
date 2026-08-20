#import <AppKit/AppKit.h>

@class UDWorkspace;

NS_ASSUME_NONNULL_BEGIN

/**
 * The workspace settings window (used both when creating a new workspace and
 * from File > Workspace Settings… on an open one).
 *
 * All controls are BOUND (through the objectController) to a scratch
 * UDWorkspace built from the source workspace's dictionaryRepresentation, so
 * this controller carries no per-setting code at all — adding a setting means
 * adding a control to the xib and binding it to selection.<property>.
 *
 * The controller itself never touches the real workspace: OK only validates
 * the scratch and stops the modal session. The CALLER applies
 * `scratchWorkspace.dictionaryRepresentation` via
 * -[UDWorkspace applySettingsFromDictionary:] (and restarts the workspace if
 * it was already running).
 */
@interface UDWorkspaceSettingsWindowController : NSWindowController

@property (strong) IBOutlet NSObjectController *objectController;

/** The scratch copy being edited. Valid after the window has loaded. */
@property (nonatomic, strong, readonly, nullable) UDWorkspace *scratchWorkspace;

- (IBAction)ok:(id)sender;
- (IBAction)cancel:(id)sender;

- (IBAction)selectBasePath:(id)sender;
- (IBAction)selectSavePath:(id)sender;
- (IBAction)selectHomePath:(id)sender;
- (IBAction)selectCDPath:(id)sender;

@end

NS_ASSUME_NONNULL_END
