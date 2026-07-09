/*
 * SPDX-License-Identifier: GPL-2.0-or-later
 */

#import "UDLauncherAppDelegate.h"

@interface UDLauncherAppDelegate ()
@property (strong) NSWindow *window;
@end

@implementation UDLauncherAppDelegate

- (NSArray<NSString *> *)appNames
{
    return @[@"PakManager", @"DeclBrowser", @"GuiEd"];
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification
{
    NSRect frame = NSMakeRect(0, 0, 340, 220);
    NSWindow *win = [[NSWindow alloc]
                     initWithContentRect:frame
                     styleMask:NSWindowStyleMaskTitled
                               | NSWindowStyleMaskClosable
                               | NSWindowStyleMaskMiniaturizable
                     backing:NSBackingStoreBuffered
                     defer:NO];
    [win setTitle:@"UDQuakeTools"];

    NSView *contentView = [win contentView];

    NSArray<NSString *> *appNames  = [self appNames];
    NSArray<NSString *> *appLabels = @[@"Pak Manager", @"Decl Browser", @"GUI Editor"];

    CGFloat buttonWidth  = 220.0;
    CGFloat buttonHeight = 32.0;
    CGFloat startX       = (frame.size.width - buttonWidth) / 2.0;
    CGFloat startY       = frame.size.height - 70.0;
    CGFloat spacing      = 50.0;

    for (NSUInteger i = 0; i < appNames.count; i++) {
        NSButton *btn = [[NSButton alloc]
                         initWithFrame:NSMakeRect(startX, startY - (CGFloat)i * spacing,
                                                  buttonWidth, buttonHeight)];
        [btn setTitle:appLabels[i]];
#if GNUSTEP
        [btn setBezelStyle:NSRoundedBezelStyle];
#else
        [btn setBezelStyle:NSBezelStyleRounded];
#endif
        [btn setTag:(NSInteger)i];
        [btn setTarget:self];
        [btn setAction:@selector(launchApp:)];
        [contentView addSubview:btn];
    }

    [win center];
    [win makeKeyAndOrderFront:nil];
    self.window = win;
}

- (void)launchApp:(NSButton *)sender
{
    NSArray<NSString *> *names = [self appNames];
    if (sender.tag < 0 || (NSUInteger)sender.tag >= names.count) {
        return;
    }
    NSString *appName = names[(NSUInteger)sender.tag];

    /* Sibling apps live in the same Applications directory as UDLauncher. */
    NSString *appsDir = [[[NSBundle mainBundle] bundlePath]
                          stringByDeletingLastPathComponent];
    NSString *appBin  = [appsDir
                          stringByAppendingPathComponent:
                          [NSString stringWithFormat:@"%@.app/%@",
                           appName, appName]];

    /* Fall back to the GNUSTEP_LOCAL_APPS environment variable. */
    if (![[NSFileManager defaultManager] isExecutableFileAtPath:appBin]) {
        NSString *localApps = [[[NSProcessInfo processInfo] environment]
                                objectForKey:@"GNUSTEP_LOCAL_APPS"];
        if (localApps != nil) {
            appBin = [localApps
                      stringByAppendingPathComponent:
                      [NSString stringWithFormat:@"%@.app/%@",
                       appName, appName]];
        }
    }

    if (![[NSFileManager defaultManager] isExecutableFileAtPath:appBin]) {
        NSAlert *alert = [[NSAlert alloc] init];
        [alert setMessageText:@"Application not found"];
        [alert setInformativeText:
            [NSString stringWithFormat:
             @"Could not find %@. Make sure all apps are installed.", appName]];
        [alert runModal];
        return;
    }

    /* Launch the app as an independent child process (fire-and-forget). */
    NSTask *task = [[NSTask alloc] init];
    [task setLaunchPath:appBin];
    @try {
        [task launch];
    } @catch (NSException *e) {
        NSAlert *alert = [[NSAlert alloc] init];
        [alert setMessageText:@"Failed to launch application"];
        [alert setInformativeText:
            [NSString stringWithFormat:@"Could not launch %@: %@",
             appName, [e reason]]];
        [alert runModal];
    }
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender
{
    return YES;
}

@end
