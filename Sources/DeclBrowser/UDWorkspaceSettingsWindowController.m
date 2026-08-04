#import "UDWorkspaceSettingsWindowController.h"
#import "UDWorkspaceDocument.h"

@implementation UDWorkspaceSettingsWindowController

- (void)windowDidLoad {
    [super windowDidLoad];

    // optionally pre-fill controls from the document
    if (self.document) {
        UDWorkspace *workspace =  ((UDWorkspaceDocument *)self.document).workspace;
        if (workspace) {
            self.basepathField.stringValue = workspace.fs_basepath;
            self.gameField.stringValue = workspace.fs_game ?: @"base"; // set default
            self.caseSensitiveFSCheckbox.state = workspace.fs_caseSensitiveOS == YES ? NSControlStateValueOn : NSControlStateValueOff;
        }
    }
}

- (IBAction)ok:(id)sender {
    NSString *basepath = self.basepathField.stringValue;
    NSString *game = self.gameField.stringValue;

    if (basepath.length == 0) {
        // Show an alert – this setting is required
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"Doom 3 folder required";
        alert.informativeText = @"Please select the Doom 3 installation directory.";
        [alert addButtonWithTitle:@"OK"];
        [alert beginSheetModalForWindow:self.window completionHandler:nil];
        return;
    }
    
    if (game.length == 0) {
        // Show an alert – this setting is required
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"Mod folder required";
        alert.informativeText = @"Please select the mod directory (e.g. base).";
        [alert addButtonWithTitle:@"OK"];
        [alert beginSheetModalForWindow:self.window completionHandler:nil];
        return;
    }

    NSString *basePathWithGameDir = [basepath stringByAppendingPathComponent:@"base"];
    if (![[NSFileManager defaultManager] fileExistsAtPath:basePathWithGameDir]) {
        // warn the user that it doesn’t look like a valid Doom 3 folder
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"The selected folder should contain at least the 'base' directory.";
        alert.informativeText = @"Please select the Doom 3 installation directory.";
        [alert addButtonWithTitle:@"OK"];
        [alert beginSheetModalForWindow:self.window completionHandler:nil];
        return;
    }
    
    if (![game isEqualToString:@"base"] && ![[NSFileManager defaultManager] fileExistsAtPath:[basepath stringByAppendingPathComponent:game]]) {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"The selected folder should contain the mod directory.";
        alert.informativeText = @"Please select the mod directory.";
        [alert addButtonWithTitle:@"OK"];
        [alert beginSheetModalForWindow:self.window completionHandler:nil];
        return;
    }

    // apply changes to workspace
    if (self.document) {
        UDWorkspace *workspace = ((UDWorkspaceDocument *)self.document).workspace;
        if (workspace) {
            workspace.fs_basepath = self.basepathField.stringValue;
            workspace.fs_game = self.gameField.stringValue;
            workspace.fs_caseSensitiveOS = self.caseSensitiveFSCheckbox.state == NSControlStateValueOn ? YES : NO;
        }
        [self.document updateChangeCount:NSChangeDone];
    }

    [NSApp stopModalWithCode:NSModalResponseOK];
}

- (IBAction)cancel:(id)sender {
    [NSApp stopModalWithCode:NSModalResponseCancel];
}

- (IBAction)selectBasePath:(id)sender {
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    
    panel.canChooseFiles = NO;
    panel.canChooseDirectories = YES;
    panel.allowsMultipleSelection = NO;
    panel.canCreateDirectories = NO;          // usually NO for a game folder
    panel.title = @"Select Doom 3 Folder";
    panel.message = @"Choose the main Doom 3 installation directory (the one that contains base/, d3xp/, etc.)";
    panel.prompt = @"Select";
    
    // Optional: start in a sensible place
    panel.directoryURL = [NSURL fileURLWithPath:NSHomeDirectory()];
    
    // Because your settings window is already a sheet, present the panel as a sheet too
    [panel beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse result) {
        if (result == NSModalResponseOK) {
            NSURL *url = panel.URLs.firstObject;
            if (url) {
                self.basepathField.stringValue = url.path;
            }
        }
    }];
}

@end
