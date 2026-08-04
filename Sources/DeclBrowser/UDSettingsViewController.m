#import "UDSettingsViewController.h"
#import "UDWorkspaceDocument.h"
#import "UDWorkspaceManager.h"

@implementation UDSettingsViewController

- (void)windowDidLoad {
    [super windowDidLoad];

    // If the workspace already exists, populate the UI
    if (self.document.workspace) {
        self.basePathTextField.stringValue = self.document.workspace.rootDirectory ?: @"";
        self.gameDirTextField.stringValue = self.document.workspace.fs_game ?: @"base";
        self.caseSensitiveCheckbox.state = self.document.workspace.fs_caseSensitiveOS ? NSControlStateValueOn : NSControlStateValueOff;
    } else {
        self.gameDirTextField.stringValue = @"base";
        self.caseSensitiveCheckbox.state = NSControlStateValueOn;
    }
}

- (IBAction)browseBasePath:(id)sender {
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.canChooseFiles = NO;
    panel.canChooseDirectories = YES;
    panel.canCreateDirectories = NO;
    panel.message = @"Select your Doom 3 root directory";
    
    // Changed self.view.window to self.window
    [panel beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse result) {
        if (result == NSModalResponseOK) {
            self.basePathTextField.stringValue = panel.URL.path;
        }
    }];
}

- (IBAction)saveAndDismiss:(id)sender {
    NSString *rootDir = self.basePathTextField.stringValue;
    if (rootDir.length == 0) {
        // You could show an alert here telling them a directory is required
        return;
    }
    
    if (!self.document.workspace) {
        NSMutableDictionary *config = [@{
            @"fs_basepath": self.basePathTextField.stringValue,
            @"fs_game": self.gameDirTextField.stringValue,
            @"fs_caseSensitiveOS": @(self.caseSensitiveCheckbox.state == NSControlStateValueOn),
            @"decl_show": @(0)
        } mutableCopy];
        self.document.workspace = [[UDWorkspace alloc] initWithDictionary:config rootDirectory:self.basePathTextField.stringValue];
        [[UDWorkspaceManager sharedManager] registerWorkspace:self.document.workspace];
    } else {
        // Apply UI values back to the workspace
        self.document.workspace.fs_basepath = self.basePathTextField.stringValue;
        self.document.workspace.fs_game = self.gameDirTextField.stringValue;
        self.document.workspace.fs_caseSensitiveOS = (self.caseSensitiveCheckbox.state == NSControlStateValueOn);
    }
    
    // Tell the document to refresh the tree view
    [self.document refreshUI];

    // Mark the document as dirty so the user is prompted to save the .workspace file
    [self.document updateChangeCount:NSChangeDone];

    // Dismiss the sheet
    [self.window.sheetParent endSheet:self.sheetWindow];
    [self.window orderOut:nil]; // <--- This actually removes it from the screen!
}

- (IBAction)cancelAndDismiss:(id)sender {
    [self.window.sheetParent endSheet:self.sheetWindow];
    [self.window orderOut:nil]; // <--- This actually removes it from the screen!

    // If this was a brand new document and they cancelled setup, close the window
    if (!self.document.workspace) {
        [self.document close];
    }
}

@end
