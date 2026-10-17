//
//  AppDelegate.m
//  Quarry
//
//  Created by artyom on 8/1/26.
//

#import "AppDelegate.h"
#import "UDAppDocumentController.h"
#import "UDUpdater.h"

// MainMenu.xib's Check for Updates…, removed where there is no updater.
static const NSInteger UDCheckForUpdatesTag = 7100;

@interface AppDelegate ()
@property (nonatomic, strong) UDUpdater *updater;
@end

@implementation AppDelegate

// Updates, set up before the app finishes launching (as Sparkle asks), and
// not started under XCTest, which reaches no network. Where there is no
// updater, no menu item.
- (void)applicationWillFinishLaunching:(NSNotification *)notification
{
    BOOL testing = [[NSProcessInfo processInfo] environment][@"XCTestConfigurationFilePath"] != nil;
    self.updater = [[UDUpdater alloc] initStarting:!testing];
    if (!self.updater.available) {
        NSMenu *appMenu = [[[NSApp mainMenu] itemAtIndex:0] submenu];
        NSMenuItem *check = [appMenu itemWithTag:UDCheckForUpdatesTag];
        if (check != nil) {
            [appMenu removeItem:check];
        }
    }
}

- (IBAction)checkForUpdates:(id)sender
{
    [self.updater checkForUpdates:sender];
}

- (BOOL)validateMenuItem:(NSMenuItem *)item
{
    if ([item action] == @selector(checkForUpdates:)) {
        return self.updater.canCheckForUpdates;
    }
    return YES;
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender {
    return NO;
}

// No new workspace at launch: one is opened (File > Open) or created
// (File > New, which asks for its settings).
- (BOOL)applicationShouldOpenUntitledFile:(NSApplication *)sender {
    return NO;
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    // Insert code here to initialize your application

    // Instantiate our custom document controller before AppKit creates the default one.
    (void)[[UDAppDocumentController alloc] init];
}


- (void)applicationWillTerminate:(NSNotification *)aNotification {
    // Insert code here to tear down your application
}


- (BOOL)applicationSupportsSecureRestorableState:(NSApplication *)app {
    return YES;
}


@end
