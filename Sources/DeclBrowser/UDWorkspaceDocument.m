#import <Cocoa/Cocoa.h>
#import "UDWorkspace.h"
#import "UDWorkspaceManager.h"
#import "UDWorkspaceWindowController.h"
#import "UDWorkspaceSettingsWindowController.h"

@interface UDWorkspaceDocument : NSDocument
@property (nonatomic, strong) UDWorkspace *workspace;
@end

@implementation UDWorkspaceDocument

- (instancetype)init {
    self = [super init];
    return self;
}

+ (BOOL)autosavesInPlace {
    return YES;
}

- (void)makeWindowControllers {
    [self createMainWindowController];
}

- (void)createMainWindowController {
    UDWorkspaceWindowController *wc = [[UDWorkspaceWindowController alloc]
        initWithWindowNibName:@"UDWorkspaceWindow"];
    [self addWindowController:wc];
}

- (NSData *)dataOfType:(NSString *)typeName error:(NSError **)outError {
    NSMutableDictionary *dict = [[self.workspace dictionaryRepresentation] mutableCopy];

    return [NSJSONSerialization dataWithJSONObject:dict
                                           options:NSJSONWritingPrettyPrinted
                                             error:outError];
}

- (BOOL)readFromData:(NSData *)data ofType:(NSString *)typeName error:(NSError **)outError {
    NSMutableDictionary *parsedDict = [[NSJSONSerialization JSONObjectWithData:data
                                                                       options:NSJSONReadingMutableContainers
                                                                         error:outError] mutableCopy];
    if (!parsedDict) return NO;
    
    NSString *rootDir = [[self.fileURL URLByDeletingLastPathComponent] path];
    
    // 1. Check if the manager already has this workspace open in another window
    self.workspace = [[UDWorkspaceManager sharedManager] workspaceForDirectory:rootDir];

    // 2. If not, create it, boot it, and register it
    if (!self.workspace) {
        self.workspace = [[UDWorkspace alloc] initWithDictionary:parsedDict rootDirectory:rootDir];
        // TODO: this should be simplified
        if (![self.workspace startup:outError]) {
            return NO;
        }
        [[UDWorkspaceManager sharedManager] registerWorkspace:self.workspace];
    }
    
    return YES;
}

- (void)close {
    if (self.workspace) {
        [[UDWorkspaceManager sharedManager] closeWorkspace:self.workspace];
        self.workspace = nil;
    }
    [super close];
}

- (BOOL)isConfigured {
    return self.workspace && self.workspace.fs_basepath.length > 0; // TODO: improve this
}

- (BOOL)applySettingsAndCreateWorkspace {
    NSError *error = nil;
    if (![self.workspace startup:&error]) {
        // TODO: show this as error message
        return NO;
    }

    [[UDWorkspaceManager sharedManager] registerWorkspace:self.workspace];

    // Critical: give the document a type so Save becomes possible
    self.fileType = @"org.underivable.quaketools.workspace";   // ← change to whatever you used in Info.plist

    // TODO: Tell the main window controller to reload its outline, etc.
    //UDWorkspaceWindowController *wc = self.windowControllers.firstObject;
    //[wc reloadAfterWorkspaceChange];
    return YES;
}

- (BOOL)showSettingsForced {
    UDWorkspaceSettingsWindowController *settingsWC =
        [[UDWorkspaceSettingsWindowController alloc] initWithWindowNibName:@"UDWorkspaceSettings"];
    
    NSWindow *settingsWindow = [settingsWC window];
    settingsWC.document = self;
    
    self.workspace = [[UDWorkspace alloc] initWithDictionary:@{} rootDirectory:@""];
    
    // Optional but nice: hide the main window while configuring
    NSWindow *mainWindow = self.windowControllers.firstObject.window;
    [mainWindow orderOut:nil];
    
    // Real modal session – always interactable
    [settingsWindow makeKeyAndOrderFront:nil];
    NSModalResponse result = [NSApp runModalForWindow:settingsWindow];
    
    [settingsWindow orderOut:nil];
    
    BOOL ret = NO;
    
    if (result == NSModalResponseOK) {
        BOOL success = [self applySettingsAndCreateWorkspace];
        if (success) {
            [mainWindow makeKeyAndOrderFront:nil];   // show the real window
            ret = YES;
        } else {
            [self close];
            ret = NO;
        }
    } else {
        [self close];
        ret = NO;
    }
    
    return ret;
}

- (void)refreshUI {
}

@end
