//
//  UDScreenshotTests.m
//  QuarryTests
//
//  The README's screenshots, taken of Quarry's own windows on a retail Doom 3
//  install: a material lit in its editor, a particle playing, the main menu in
//  the GUI editor's design and, given a game to run, the debugger stopped in a
//  script. Only when $UD_SCREENSHOTS names a folder to write them to (through
//  xcodebuild, TEST_RUNNER_UD_SCREENSHOTS); $UD_SCREENSHOT_GAME is the game
//  the debugger runs (a dhewm3 executable or .app). Each is named for its
//  scene and the system, "quarry-material-macos.png".
//
//  macOS: screencapture, of the window alone, by Scripts/screenshot-watch.sh
//  (the test runner has no Screen Recording permission; a terminal can).
//  GNUstep: ImageMagick's import, of the window's part of the (virtual) display.
//

#import <XCTest/XCTest.h>
#import <UDCodeKit/UDCodeKit.h>
#import "UDQuarryTestCase.h"
#import "UDWorkspaceWindowController.h"
#import "UDWorkspaceDocument.h"
#import "UDWorkspace.h"
#import "UDScriptDebugger.h"
#import "UDMaterialEditorViewController.h"
#import "UDParticleEditorViewController.h"
#import "UDGuiEditorViewController.h"
#import "UDTransportController.h"

@interface UDScreenshotTests : UDQuarryTestCase
@property (nonatomic, copy) NSString *folder;
@property (nonatomic, copy) NSString *installPath;
@end

@implementation UDScreenshotTests

- (void)setUp {
    [super setUp];
    self.folder = NSProcessInfo.processInfo.environment[@"UD_SCREENSHOTS"];
    self.installPath = UDDoom3InstallPath();
}

/// The case's workspace over the install, its window the screenshots' size.
- (UDWorkspaceWindowController *)openDoom3 {
    if (self.folder.length == 0 || self.installPath == nil) return nil;
    NSString *save = [self.scratchDirectory stringByAppendingPathComponent:@"save"];
    [[NSFileManager defaultManager] createDirectoryAtPath:save withIntermediateDirectories:YES attributes:nil error:NULL];
    UDWorkspaceWindowController *controller = [self openWorkspaceWithSettings:[self workspaceSettingsWithBasePath:self.installPath
                                                                                                         savePath:save]];
    NSRect visible = controller.window.screen.visibleFrame;
    NSSize size = NSMakeSize(MIN(1440, NSWidth(visible)), MIN(860, NSHeight(visible)));
    [controller.window setFrame:NSMakeRect(NSMinX(visible) + (NSWidth(visible) - size.width) / 2,
                                           NSMinY(visible) + (NSHeight(visible) - size.height) / 2, size.width, size.height)
                        display:YES];
    [controller.window makeKeyAndOrderFront:nil];
    return controller;
}

- (void)settle:(NSTimeInterval)seconds {
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:seconds]];
}

/// The window, as it is on the screen, written to the folder as @a scene.
- (void)capture:(NSWindow *)window scene:(NSString *)scene {
    [window displayIfNeeded];
    [self settle:1.0];
    NSTask *task = [[NSTask alloc] init];
#ifdef GNUSTEP
    NSString *path = [self.folder stringByAppendingPathComponent:[NSString stringWithFormat:@"quarry-%@-gnustep.png", scene]];
    // X's y goes down from the display's top; there is no window manager's frame
    NSRect frame = window.frame;
    CGFloat top = NSHeight(window.screen.frame) - NSMaxY(frame);
    task.launchPath = @"/usr/bin/import";
    task.arguments = @[ @"-window", @"root", @"-crop",
                        [NSString stringWithFormat:@"%dx%d+%d+%d", (int)NSWidth(frame), (int)NSHeight(frame), (int)NSMinX(frame), (int)top],
                        @"+repage", path ];
#else
    // screencapture needs the Screen Recording permission, which the test
    // runner hasn't: a watcher that has it takes the picture. The test asks
    // with <scene>.window (the window's number) and waits for the picture.
    NSString *path = [self.folder stringByAppendingPathComponent:[NSString stringWithFormat:@"quarry-%@-macos.png", scene]];
    NSString *request = [self.folder stringByAppendingPathComponent:[scene stringByAppendingPathExtension:@"window"]];
    [[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
    [[NSString stringWithFormat:@"%ld", (long)window.windowNumber] writeToFile:request atomically:YES
                                                                     encoding:NSUTF8StringEncoding error:NULL];
    XCTAssertTrue([self spinUntil:^BOOL{ return [[NSFileManager defaultManager] fileExistsAtPath:path]; } timeout:60],
                  @"no picture of %@: is Scripts/screenshot-watch.sh running?", scene);
    [[NSFileManager defaultManager] removeItemAtPath:request error:NULL];
    (void)task;
    return;
#endif
    [task launch];
    [task waitUntilExit];
    XCTAssertEqual(task.terminationStatus, 0, @"%@ %@", task.launchPath, task.arguments);
    XCTAssertTrue([[NSFileManager defaultManager] fileExistsAtPath:path], @"%@", path);
}

- (void)testTheMaterialEditor {
    UDWorkspaceWindowController *controller = [self openDoom3];
    if (controller == nil) return;
    UDMaterialEditorViewController *editor = [self openOutlinePath:@"material/textures/base_wall/lfwall27d" inController:controller];
    XCTAssertTrue([editor isKindOfClass:[UDMaterialEditorViewController class]]);
    [editor.stagesController setSelectionIndex:0];
    XCTAssertTrue([self spinUntil:^BOOL{ return editor.materialPreviewView.image != nil; } timeout:20], @"lit");
    [self capture:controller.window scene:@"material"];
}

- (void)testTheParticleEditor {
    UDWorkspaceWindowController *controller = [self openDoom3];
    if (controller == nil) return;
    UDParticleEditorViewController *editor = [self openOutlinePath:@"particle/flamejet" inController:controller];
    XCTAssertTrue([editor isKindOfClass:[UDParticleEditorViewController class]]);
    // a moment into its playing: the jet going
    [self settle:3.0];
    XCTAssertNotNil(editor.previewView.image);
    [self capture:controller.window scene:@"particle"];
}

- (void)testTheGuiEditorsDesign {
    UDWorkspaceWindowController *controller = [self openDoom3];
    if (controller == nil) return;
    UDGuiEditorViewController *editor = [self openOutlinePath:@"guis/mainmenu.gui" inController:controller];
    XCTAssertTrue([editor isKindOfClass:[UDGuiEditorViewController class]]);
    editor.modeControl.selectedSegment = 1;
    [editor changeMode:editor.modeControl];
    // the menu as it shows, not behind its intro's black curtain
    NSMenuItem *noIntro = [editor.namedEventPopUp itemWithTitle:@"NoIntro"];
    if (noIntro != nil) [NSApp sendAction:noIntro.action to:noIntro.target from:noIntro];
    NSSlider *slider = editor.transport.timeSlider;
    [self spinUntil:^BOOL{ return slider.maxValue >= 2000; } timeout:10];
    slider.doubleValue = MIN(2000, slider.maxValue);
    [NSApp sendAction:slider.action to:slider.target from:slider];
    [self capture:controller.window scene:@"gui"];
}

/// A real game, stopped at a breakpoint in character::init as Mars City
/// starts, self opened.
- (void)testTheDebuggerStopped {
    NSString *game = NSProcessInfo.processInfo.environment[@"UD_SCREENSHOT_GAME"];
    if (game.length == 0) return;
    UDWorkspaceWindowController *controller = [self openDoom3];
    if (controller == nil) return;
    UDWorkspace *workspace = ((UDWorkspaceDocument *)controller.document).workspace;
    workspace.gameExecutable = game;
    workspace.gameArguments = @"+set r_fullscreen 0 +set r_mode 3 +set s_noSound 1 +map game/mars_city1";
    [controller openFileAtPath:@"script/ai_character.script" line:356 character:0 length:0];
    UDBreakpointStore *breakpoints = controller.scriptDebugger.breakpoints;
    [breakpoints addBreakpointAtLine:357 inFile:[workspace diskPathOfGamePath:@"script/ai_character.script"]];

    [controller startDebugging:nil];
    UDDebugSession *session = controller.scriptDebugger.session;
    XCTAssertTrue([self spinUntil:^BOOL{ return session.state == UDDebugSessionStateStopped && session.scopes.count > 0; } timeout:180],
                  @"stopped in character::init");
    NSOutlineView *variables = controller.scriptDebugger.area.variablesView;
    [self spinUntil:^BOOL{ return variables.numberOfRows > 1; } timeout:20];
    for (NSInteger row = 0; row < variables.numberOfRows; row++) {
        if ([[controller.scriptDebugger.area variableOfRow:row].name isEqualToString:@"self"]) {
            [variables expandItem:[variables itemAtRow:row]];
            break;
        }
    }
    [self spinUntil:^BOOL{ return variables.numberOfRows > 8; } timeout:20];
    [self capture:controller.window scene:@"debugger"];

    [controller stopDebugging:nil];
    [self spinUntil:^BOOL{ return !controller.scriptDebugger.debugging; } timeout:30];
    [breakpoints removeAllBreakpoints];
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:breakpoints.autosaveName];
}
@end
