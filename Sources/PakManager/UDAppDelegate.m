/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

#import "UDAppDelegate.h"
#import "UDCodecRegistry.h"
#import "UDPAKCodec.h"
#import "UDPAK2Codec.h"
#import "UDDaikatanaPAKCodec.h"
#import "UDPK3Codec.h"
#import "UDPK4Codec.h"
#import "UDUpdater.h"

// MainMenu.xib's Check for Updates…, removed where there is no updater.
static const NSInteger UDCheckForUpdatesTag = 7100;

@interface UDAppDelegate ()
@property (nonatomic, strong) UDUpdater *updater;
@end

@implementation UDAppDelegate

- (void)applicationWillFinishLaunching:(NSNotification *)notification {
    // Updates, set up before the app finishes launching (as Sparkle asks),
    // and not started under XCTest, which reaches no network. Where there is
    // no updater, no menu item.
    BOOL testing = [[NSProcessInfo processInfo] environment][@"XCTestConfigurationFilePath"] != nil;
    self.updater = [[UDUpdater alloc] initStarting:!testing];
    if (!self.updater.available) {
        NSMenu *appMenu = [[[NSApp mainMenu] itemAtIndex:0] submenu];
        NSMenuItem *check = [appMenu itemWithTag:UDCheckForUpdatesTag];
        if (check != nil) {
            [appMenu removeItem:check];
        }
    }

    UDCodecRegistry *reg = [UDCodecRegistry sharedRegistry];
    [reg registerCodec:[[UDPAKCodec alloc] init]];
    [reg registerCodec:[[UDPAK2Codec alloc] init]];
    [reg registerCodec:[[UDDaikatanaPAKCodec alloc] init]];
    [reg registerCodec:[[UDPK3Codec alloc] init]];
    [reg registerCodec:[[UDPK4Codec alloc] init]];
}

- (IBAction)checkForUpdates:(id)sender {
    [self.updater checkForUpdates:sender];
}

- (BOOL)validateMenuItem:(NSMenuItem *)item {
    if ([item action] == @selector(checkForUpdates:)) {
        return self.updater.canCheckForUpdates;
    }
    return YES;
}

@end
