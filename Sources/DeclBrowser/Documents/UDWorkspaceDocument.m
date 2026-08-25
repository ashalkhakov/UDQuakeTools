#import "UDWorkspaceDocument.h"
#import "UDWorkspace.h"
#import "UDWorkspaceManager.h"
#import "UDWorkspaceWindowController.h"
#import "UDWorkspaceSettingsWindowController.h"

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

    // New document — show settings window modally first

    UDWorkspaceSettingsWindowController *settingsWC =
        [[UDWorkspaceSettingsWindowController alloc] initWithWindowNibName:@"UDWorkspaceSettings"];

    // Create the (default-initialized) workspace BEFORE handing the document
    // to the settings controller, so its scratch copy starts from the same
    // defaults the workspace itself would use.
    self.workspace = [[UDWorkspace alloc] initWithDictionary:@{} rootDirectory:@""];

    NSWindow *settingsWindow = [settingsWC window];
    settingsWC.document = self;

    // Optional but nice: hide the main window while configuring.
    // (Typed intermediate: GNUstep's -windowControllers returns a plain
    // NSArray, so firstObject is `id` there and dot-syntax property access
    // would not compile.)
    NSWindowController *mainWindowController = self.windowControllers.firstObject;
    NSWindow *mainWindow = mainWindowController.window;
    [mainWindow orderOut:nil];

    // Real modal session – always interactable
    [settingsWindow makeKeyAndOrderFront:nil];
    NSModalResponse result = [NSApp runModalForWindow:settingsWindow];

    [settingsWindow orderOut:nil];

    BOOL ret = NO;
    if (result == NSModalResponseOK) {
        // The settings window edits a scratch copy; apply it to the real
        // workspace before starting it up.
        [self.workspace applySettingsFromDictionary:settingsWC.scratchWorkspace.dictionaryRepresentation];
        [self updateChangeCount:NSChangeDone];

        BOOL success = [self applySettingsAndCreateWorkspace:&error];
        if (success) {
            [mainWindow makeKeyAndOrderFront:nil];   // show the real window
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
