/*
 * SPDX-License-Identifier: GPL-2.0-or-later
 * UDArchivist — GNUstep AppKit application entry point.
 */

#import <AppKit/AppKit.h>
#import "UDAppDelegate.h"

int main(int argc, const char *argv[])
{
#ifndef GNUSTEP
    @autoreleasepool {
        [NSApplication sharedApplication];
        UDAppDelegate *delegate = [[UDAppDelegate alloc] init];
        [NSApp setDelegate:delegate];
    }
#endif
    return NSApplicationMain(argc, argv);
}
