#import "UDWorkspaceDocument.h"
#import "UDWorkspace.h"
#import "UDWorkspaceManager.h"
#import "UDWorkspaceWindowController.h"
#import "UDWorkspaceSettingsWindowController.h"
#import "UDWorkspaceOpeningController.h"

@interface UDWorkspaceDocument ()
// A new workspace's settings dialog, while it is up.
@property (nonatomic, strong, nullable) UDWorkspaceSettingsWindowController *settingsController;
// "Opening…", while the workspace starts.
@property (nonatomic, strong, nullable) UDWorkspaceOpeningController *openingController;
@end

@implementation UDWorkspaceDocument

- (instancetype)init {
    self = [super init];
    if (self) {
        // a tool's settings (the GUI editor's options) are the workspace's:
        // changed, it is edited, and saved with them
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_toolSettingsDidChange:)
                                                     name:UDWorkspaceToolSettingsDidChangeNotification object:nil];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)_toolSettingsDidChange:(NSNotification *)notification {
    if (notification.object == self.workspace) {
        [self updateChangeCount:NSChangeDone];
    }
}

- (void)makeWindowControllers {
    if (self.workspace != nil) {
        // Already configured (opened from file): start it, then its window.
        [self _startWorkspace];
        return;
    }

    // New document — its settings first, in a plain window (not a modal
    // session, which would hold the menus); OK or Cancel come back to
    // -_settingsDidFinish:.

    UDWorkspaceSettingsWindowController *settingsWC =
        [[UDWorkspaceSettingsWindowController alloc] initWithWindowNibName:@"UDWorkspaceSettings"];

    // Create the (default-initialized) workspace BEFORE handing the document
    // to the settings controller, so its scratch copy starts from the same
    // defaults the workspace itself would use.
    self.workspace = [[UDWorkspace alloc] initWithDictionary:@{} rootDirectory:@""];

    settingsWC.document = self;
    settingsWC.target = self;
    settingsWC.action = @selector(_settingsDidFinish:);
    self.settingsController = settingsWC;
    [settingsWC showWindow:nil];
}

- (void)_settingsDidFinish:(UDWorkspaceSettingsWindowController *)settingsWC {
    self.settingsController = nil;
    if (settingsWC.result != NSModalResponseOK) {
        [self close];
        return;
    }
    // The settings window edits a scratch copy; apply it to the real
    // workspace before starting it up.
    [self.workspace applySettingsFromDictionary:settingsWC.scratchWorkspace.dictionaryRepresentation];
    [self updateChangeCount:NSChangeDone];
    [self _startWorkspace];
}

/// The workspace starts in the background (its paks and decls take a while
/// from a hard disk), "Opening…" up meanwhile; its window comes once it has.
- (void)_startWorkspace {
    self.openingController = [[UDWorkspaceOpeningController alloc] initWithWorkspaceName:self.displayName];
    [self.openingController showOverWindow:nil];
    [self.workspace startupInBackgroundWithTarget:self action:@selector(_workspaceDidStart:)];
}

- (void)_workspaceDidStart:(UDWorkspace *)workspace {
    [self.openingController close];
    self.openingController = nil;
    if (workspace.startupError != nil) {
        [self presentError:workspace.startupError];
        [self close];
        return;
    }
    [[UDWorkspaceManager sharedManager] registerWorkspace:workspace];
    UDWorkspaceWindowController *wc =
        [[UDWorkspaceWindowController alloc] initWithWindowNibName:@"UDWorkspaceWindow"];
    [self addWindowController:wc];
    [self showWindows];
}

- (BOOL)readFromData:(NSData *)data ofType:(NSString *)typeName error:(NSError **)outError {
    // Deserialize saved settings from data (JSON, plist, etc.)
    NSDictionary *settings = [NSJSONSerialization JSONObjectWithData:data options:0 error:outError];
    self.workspace = [[UDWorkspace alloc] initWithDictionary:settings rootDirectory:[settings valueForKey:@"fs_basepath"]];
    return self.workspace != nil;
}

- (NSData *)dataOfType:(NSString *)typeName error:(NSError **)outError {
    // Serialize current settings
    NSDictionary *settings = [self.workspace dictionaryRepresentation];
    return [NSJSONSerialization dataWithJSONObject:settings options:0 error:outError];
}

+ (BOOL)autosavesInPlace {
    return YES;
}

@end
