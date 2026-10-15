#import "UDWorkspaceDocument.h"
#import "UDWorkspace.h"
#import "UDWorkspaceManager.h"
#import "UDWorkspaceWindowController.h"
#import "UDWorkspaceSettingsWindowController.h"

@interface UDWorkspaceDocument ()
// A new workspace's settings dialog, while it is up.
@property (nonatomic, strong, nullable) UDWorkspaceSettingsWindowController *settingsController;
@end

@implementation UDWorkspaceDocument

- (void)makeWindowControllers {
    NSError *error = nil;

    if (self.workspace != nil) {
        // Already configured (opened from file) — go straight to workspace window
        BOOL success = [self applySettingsAndCreateWorkspace:&error];
        if (success) {
            [self addWorkspaceWindowController];
        } else {
            [self presentError:error]; // FIXME: is this correct?
            [self close];
        }
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
    NSError *error = nil;
    self.settingsController = nil;

    BOOL ret = NO;
    if (settingsWC.result == NSModalResponseOK) {
        // The settings window edits a scratch copy; apply it to the real
        // workspace before starting it up.
        [self.workspace applySettingsFromDictionary:settingsWC.scratchWorkspace.dictionaryRepresentation];
        [self updateChangeCount:NSChangeDone];

        BOOL success = [self applySettingsAndCreateWorkspace:&error];
        if (success) {
            ret = YES;
        } else {
            [self presentError:error]; // FIXME: is this correct?
            ret = NO;
        }
    } else {
        // user cancelled
        ret = NO;
    }

    if (ret == YES) {
        [self addWorkspaceWindowController];
        [self showWindows];
    } else {
        [self close];
    }
}

- (BOOL)applySettingsAndCreateWorkspace:(NSError **)error {
    if (![self.workspace startup:error]) {
        // TODO: show this as error message
        return NO;
    }

    [[UDWorkspaceManager sharedManager] registerWorkspace:self.workspace];

    return YES;
}

- (void)addWorkspaceWindowController {
    UDWorkspaceWindowController *wc =
        [[UDWorkspaceWindowController alloc] initWithWindowNibName:@"UDWorkspaceWindow"];
    [self addWindowController:wc];
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
