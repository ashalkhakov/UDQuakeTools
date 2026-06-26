/*
 * SPDX-License-Identifier: GPL-2.0-or-later
 */

#import "UDAppDelegate.h"
#import "UDCodecRegistry.h"
#import "UDPAKCodec.h"
#import "UDPAK2Codec.h"
#import "UDDaikatanaPAKCodec.h"
#import "UDPK3Codec.h"
#import "UDPK4Codec.h"

@implementation UDAppDelegate

- (void)applicationWillFinishLaunching:(NSNotification *)notification {
    UDCodecRegistry *reg = [UDCodecRegistry sharedRegistry];
    [reg registerCodec:[[UDPAKCodec alloc] init]];
    [reg registerCodec:[[UDPAK2Codec alloc] init]];
    [reg registerCodec:[[UDDaikatanaPAKCodec alloc] init]];
    [reg registerCodec:[[UDPK3Codec alloc] init]];
    [reg registerCodec:[[UDPK4Codec alloc] init]];
}

@end
