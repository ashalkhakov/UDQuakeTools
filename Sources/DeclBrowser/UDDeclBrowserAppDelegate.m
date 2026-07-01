/*
 * SPDX-License-Identifier: GPL-2.0-or-later
 * Decl Browser application delegate.
 */

#import "UDDeclBrowserAppDelegate.h"
#import "UDDeclBrowserWindowController.h"
#import "../UDFormats/UDCodecRegistry.h"
#import "../UDFormats/UDPAKCodec.h"
#import "../UDFormats/UDPAK2Codec.h"
#import "../UDFormats/UDDaikatanaPAKCodec.h"
#import "../UDFormats/UDPK3Codec.h"
#import "../UDFormats/UDPK4Codec.h"

@interface UDDeclBrowserAppDelegate ()
@property (nonatomic, strong) UDDeclBrowserWindowController *windowController;
@end

@implementation UDDeclBrowserAppDelegate

- (void)applicationWillFinishLaunching:(NSNotification *)notification {
    (void)notification;
    UDCodecRegistry *registry = [UDCodecRegistry sharedRegistry];
    [registry registerCodec:[[UDPAKCodec alloc] init]];
    [registry registerCodec:[[UDPAK2Codec alloc] init]];
    [registry registerCodec:[[UDDaikatanaPAKCodec alloc] init]];
    [registry registerCodec:[[UDPK3Codec alloc] init]];
    [registry registerCodec:[[UDPK4Codec alloc] init]];
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    (void)notification;
    self.windowController = [[UDDeclBrowserWindowController alloc] init];
    [self.windowController showWindow:self];
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender {
    (void)sender;
    return YES;
}

@end
