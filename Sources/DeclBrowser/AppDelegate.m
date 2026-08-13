//
//  AppDelegate.m
//  QuakeEditor
//
//  Created by artyom on 8/1/26.
//

#import "AppDelegate.h"
#import "UDAppDocumentController.h"

@interface AppDelegate ()

@end

@implementation AppDelegate

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender {
    return NO;
}

- (BOOL)applicationShouldOpenUntitledFile:(NSApplication *)sender {
    return YES;
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
