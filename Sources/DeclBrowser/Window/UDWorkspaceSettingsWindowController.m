#import "UDWorkspaceSettingsWindowController.h"
#import "UDWorkspaceDocument.h"
#import "UDWorkspace.h"

@interface UDWorkspaceSettingsWindowController ()
@property (nonatomic, strong, readwrite) UDWorkspace *scratchWorkspace;
@end

@implementation UDWorkspaceSettingsWindowController

#pragma mark - Scratch workspace

// The document may be set before OR after the window loads (both call sites
// exist), so the scratch is (re)built from whichever event comes last.
- (void)_rebuildScratchWorkspace {
    if (self.objectController == nil) {
        return; // window not loaded yet; windowDidLoad will call again
    }

    UDWorkspace *source = [self.document isKindOfClass:[UDWorkspaceDocument class]]
        ? ((UDWorkspaceDocument *)self.document).workspace
        : nil;

    NSDictionary *settings = source != nil ? source.dictionaryRepresentation : @{};
    NSString *rootDir = source.rootDirectory ?: @"";
    self.scratchWorkspace = [[UDWorkspace alloc] initWithDictionary:settings rootDirectory:rootDir];
    self.objectController.content = self.scratchWorkspace;
}

- (void)windowDidLoad {
    [super windowDidLoad];
    [self _rebuildScratchWorkspace];
}

- (void)setDocument:(id)document {
    [super setDocument:document];
    [self _rebuildScratchWorkspace];
}

#pragma mark - OK / Cancel

- (IBAction)ok:(id)sender {
    // Commit any in-flight field editing into the scratch object first.
    if (![self.window makeFirstResponder:nil]) {
        [self.window endEditingFor:nil];
    }
    [self.objectController commitEditing];

    if (![self _validateScratch]) {
        return; // keep the modal session running so the user can fix it
    }

    [NSApp stopModalWithCode:NSModalResponseOK];
}

- (IBAction)cancel:(id)sender {
    [self.objectController discardEditing];
    [NSApp stopModalWithCode:NSModalResponseCancel];
}

- (BOOL)_validateScratch {
    UDWorkspace *scratch = self.scratchWorkspace;
    NSString *basepath = scratch.fs_basepath;
    NSString *game = scratch.fs_game;

    if (basepath.length == 0) {
        [self _showValidationAlert:@"Doom 3 folder required"
                              text:@"Please select the Doom 3 installation directory."];
        return NO;
    }

    if (game.length == 0) {
        [self _showValidationAlert:@"Mod folder required"
                              text:@"Please select the mod directory (e.g. base)."];
        return NO;
    }

    NSString *basePathWithGameDir = [basepath stringByAppendingPathComponent:@"base"];
    if (![[NSFileManager defaultManager] fileExistsAtPath:basePathWithGameDir]) {
        [self _showValidationAlert:@"The selected folder should contain at least the 'base' directory."
                              text:@"Please select the Doom 3 installation directory."];
        return NO;
    }

    if (![game isEqualToString:@"base"] &&
        ![[NSFileManager defaultManager] fileExistsAtPath:[basepath stringByAppendingPathComponent:game]]) {
        [self _showValidationAlert:@"The selected folder should contain the mod directory."
                              text:@"Please select the mod directory."];
        return NO;
    }

    return YES;
}

- (void)_showValidationAlert:(NSString *)message text:(NSString *)informativeText {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = message;
    alert.informativeText = informativeText;
    [alert addButtonWithTitle:@"OK"];
    [alert beginSheetModalForWindow:self.window completionHandler:nil];
}

#pragma mark - Path pickers

// The pickers write straight into the scratch workspace via KVC; the bound
// text fields update themselves.
- (void)_chooseDirectoryForSettingKey:(NSString *)key title:(NSString *)title message:(NSString *)message {
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.canChooseFiles = NO;
    panel.canChooseDirectories = YES;
    panel.allowsMultipleSelection = NO;
    panel.canCreateDirectories = NO;
    panel.title = title;
    panel.message = message;
    panel.prompt = @"Select";

    NSString *current = [self.scratchWorkspace valueForKey:key];
    panel.directoryURL = [NSURL fileURLWithPath:current.length > 0 ? current : NSHomeDirectory()];

    [panel beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse result) {
        if (result == NSModalResponseOK) {
            NSURL *url = panel.URLs.firstObject;
            if (url != nil) {
                [self.scratchWorkspace setValue:url.path forKey:key];
            }
        }
    }];
}

- (IBAction)selectBasePath:(id)sender {
    [self _chooseDirectoryForSettingKey:@"fs_basepath"
                                  title:@"Select Doom 3 Folder"
                                message:@"Choose the main Doom 3 installation directory (the one that contains base/, d3xp/, etc.)"];
}

- (IBAction)selectSavePath:(id)sender {
    [self _chooseDirectoryForSettingKey:@"fs_savepath"
                                  title:@"Select Save Path"
                                message:@"Choose the directory modified decl files are written to (fs_savepath)."];
}

- (IBAction)selectHomePath:(id)sender {
    [self _chooseDirectoryForSettingKey:@"fs_homepath"
                                  title:@"Select Home Path"
                                message:@"Choose the per-user game data directory (fs_homepath)."];
}

- (IBAction)selectCDPath:(id)sender {
    [self _chooseDirectoryForSettingKey:@"fs_cdpath"
                                  title:@"Select CD Path"
                                message:@"Choose the secondary read-only data directory (fs_cdpath)."];
}

@end
