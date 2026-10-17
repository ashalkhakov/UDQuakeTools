/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

#import "UDLauncherAppDelegate.h"
#import "UDUpdater.h"

// MainMenu.xib's Check for Updates…, removed where there is no updater.
static const NSInteger UDCheckForUpdatesTag = 7100;

@interface UDLauncherAppDelegate ()
@property (strong) NSWindow *window;
@property (strong) UDUpdater *updater;
@end

@implementation UDLauncherAppDelegate

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

- (NSArray<NSString *> *)appNames
{
    return @[@"PakManager", @"Quarry"];
}

- (NSDictionary<NSString *, NSString *> *)appLabels
{
    return @{@"PakManager": @"Pak Manager", @"Quarry": @"Quarry"};
}

/* A tool's executable, beside UDLauncher (in the same Applications
 * directory, or the AppImage's), else in GNUSTEP_LOCAL_APPS; nil when it is
 * not installed. NSBundle knows where each system keeps it
 * (Name.app/Name on GNUstep, Name.app/Contents/MacOS/Name on a Mac). */
- (NSString *)executableForApp:(NSString *)appName
{
    NSString *bundleName = [appName stringByAppendingPathExtension:@"app"];
    NSMutableArray<NSString *> *dirs = [NSMutableArray arrayWithObject:
        [[[NSBundle mainBundle] bundlePath] stringByDeletingLastPathComponent]];
    NSString *localApps = [[[NSProcessInfo processInfo] environment] objectForKey:@"GNUSTEP_LOCAL_APPS"];
    if (localApps != nil) {
        [dirs addObject:localApps];
    }
    for (NSString *dir in dirs) {
        NSBundle *bundle = [NSBundle bundleWithPath:[dir stringByAppendingPathComponent:bundleName]];
        NSString *executable = [bundle executablePath];
        if (executable != nil && [[NSFileManager defaultManager] isExecutableFileAtPath:executable]) {
            return executable;
        }
    }
    return nil;
}

/* The tools installed here, in the order they are offered. */
- (NSArray<NSString *> *)installedAppNames
{
    NSMutableArray<NSString *> *installed = [NSMutableArray array];
    for (NSString *name in [self appNames]) {
        if ([self executableForApp:name] != nil) {
            [installed addObject:name];
        }
    }
    return installed;
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

    NSArray<NSString *> *appNames = [self installedAppNames];
    NSDictionary<NSString *, NSString *> *appLabels = [self appLabels];

    CGFloat buttonWidth  = 220.0;
    CGFloat buttonHeight = 32.0;
    CGFloat startX       = (frame.size.width - buttonWidth) / 2.0;
    CGFloat startY       = frame.size.height - 70.0;
    CGFloat spacing      = 50.0;

    for (NSUInteger i = 0; i < appNames.count; i++) {
        NSButton *btn = [[NSButton alloc]
                         initWithFrame:NSMakeRect(startX, startY - (CGFloat)i * spacing,
                                                  buttonWidth, buttonHeight)];
        [btn setTitle:appLabels[appNames[i]]];
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

    if (appNames.count == 0) {
        NSTextField *none = [[NSTextField alloc] initWithFrame:NSMakeRect(20, frame.size.height / 2 - 20, frame.size.width - 40, 40)];
        [none setStringValue:@"No UDQuakeTools apps are installed beside UDLauncher."];
        [none setEditable:NO];
        [none setBordered:NO];
        [none setDrawsBackground:NO];
        [none setAlignment:NSTextAlignmentCenter];
        [contentView addSubview:none];
    }

    [win center];
    [win makeKeyAndOrderFront:nil];
    self.window = win;
}

- (void)launchApp:(NSButton *)sender
{
    NSArray<NSString *> *names = [self installedAppNames];
    if (sender.tag < 0 || (NSUInteger)sender.tag >= names.count) {
        return;
    }
    NSString *appName = names[(NSUInteger)sender.tag];
    NSString *appBin = [self executableForApp:appName];

    if (appBin == nil) {
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
