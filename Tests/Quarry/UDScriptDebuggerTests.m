//
//  UDScriptDebuggerTests.m
//  QuarryTests
//
//  Debug > Attach in a workspace's window: udscript-dap (the tree's) between
//  Quarry and the game (UDFakeScriptDebugger, on UDP), a fixture script on
//  disk.
//

#import <XCTest/XCTest.h>
#import <UDCodeKit/UDCodeKit.h>
#import "UDQuarryTestCase.h"
#import "UDFakeScriptDebugger.h"
#import "UDScriptDebugger.h"
#import "UDWorkspaceWindowController.h"
#import "UDWorkspaceDocument.h"
#import "UDWorkspace.h"
#import "UDTextEditorViewController.h"
#import "UDEditorTabManager.h"

static NSString *const UDFixtureScript =
    @"void udtest_main() {\n"          // 1
    @"    float count = 2;\n"           // 2
    @"    sys.wait( count );\n"         // 3
    @"}\n";

@interface UDScriptDebuggerTests : UDQuarryTestCase
@property (nonatomic, strong) UDFakeScriptDebugger *game;
@end

@implementation UDScriptDebuggerTests

/// The game's port free for the next test (XCTest keeps a test's instance).
- (void)tearDown {
    self.game = nil;
    [super tearDown];
}

/// The next message of @a type the debugger sent the game, the run loop
/// turning meanwhile (the session's answers come on it).
- (UDBitMsg *)receive:(int)type within:(NSTimeInterval)timeout {
    NSDate *until = [NSDate dateWithTimeIntervalSinceNow:timeout];
    while (until.timeIntervalSinceNow > 0) {
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
        int got = -1;
        UDBitMsg *message = [self.game receiveWithin:0.01 type:&got];
        if (message != nil && got == type) return message;
    }
    return nil;
}

- (void)testABreakpointStopsTheGameWhereTheScriptShowsIt {
    NSString *base = [self.scratchDirectory stringByAppendingPathComponent:@"install"];
    NSString *script = [base stringByAppendingPathComponent:@"base/script/udtest.script"];
    [[NSFileManager defaultManager] createDirectoryAtPath:script.stringByDeletingLastPathComponent
                              withIntermediateDirectories:YES attributes:nil error:NULL];
    [UDFixtureScript writeToFile:script atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    NSString *save = [self.scratchDirectory stringByAppendingPathComponent:@"save"];
    [[NSFileManager defaultManager] createDirectoryAtPath:save withIntermediateDirectories:YES attributes:nil error:NULL];
    self.game = [[UDFakeScriptDebugger alloc] initWithPort:[UDFakeScriptDebugger gamePort] debuggerPort:[UDFakeScriptDebugger debuggerPort]];
    if (self.game == nil || [UDScriptDebugger adapterPath] == nil) return;

    UDWorkspaceWindowController *controller = [self openWorkspaceWithSettings:[self workspaceSettingsWithBasePath:base savePath:save]];
    if (controller == nil) return;
    UDWorkspace *workspace = ((UDWorkspaceDocument *)controller.document).workspace;
    [workspace setSettings:@{ @"port": @([UDFakeScriptDebugger gamePort]), @"localPort": @([UDFakeScriptDebugger debuggerPort]) }
                   forTool:@"Debugger"];
    XCTAssertFalse(controller.debugAreaShown, @"hidden until a session starts");

    // a breakpoint, set in the script's tab (Debug > Toggle Breakpoint)
    [controller openFileAtPath:@"script/udtest.script" line:2 character:0 length:0];
    UDTextEditorViewController *editor = (UDTextEditorViewController *)[[self tabManagerOf:controller] selectedEditor];
    XCTAssertTrue([editor isKindOfClass:[UDTextEditorViewController class]]);
    XCTAssertTrue([self spinUntil:^BOOL{ return editor.editorTextView != nil; } timeout:5]);
    [controller.window makeFirstResponder:editor.editorTextView];
    [editor selectLine:2 character:0 length:0];
    XCTAssertTrue([editor.editorTextView tryToPerform:@selector(toggleBreakpoint:) with:nil], @"the code editor's, up the text view's responders");
    UDBreakpointStore *breakpoints = controller.scriptDebugger.breakpoints;
    XCTAssertNotNil([breakpoints breakpointAtLine:3 inFile:[workspace diskPathOfGamePath:@"script/udtest.script"]],
                    @"the script named as the adapter names it");
    // the breakpoints navigator lists it; a watch, kept with it
    UDBreakpointNavigatorViewController *navigator = controller.scriptDebugger.breakpointNavigator;
    BOOL listed = NO;
    for (NSInteger row = 0; row < navigator.outlineView.numberOfRows; row++) {
        listed = listed || [navigator breakpointOfRow:row].line == 3;
    }
    XCTAssertTrue(listed, @"in the Breakpoints navigator");
    [breakpoints addWatchExpression:@"count"];
    XCTAssertTrue([breakpoints.autosaveName hasPrefix:@"Quarry Debugger "], @"kept as the workspace's state");

    // Attach: the game connects, and has the breakpoint as it names the script
    [controller attachDebugger:nil];
    XCTAssertTrue(controller.debugAreaShown);
    XCTAssertNotNil([self receive:1 /* CONNECT */ within:20], @"the adapter asks the game");
    [self.game send:[self.game message:2 /* CONNECTED */]];
    UDBitMsg *add = [self receive:4 /* ADDBREAKPOINT */ within:10];
    XCTAssertNotNil(add);
    [add readBits:1];
    XCTAssertEqual([add readInt], 3);
    [add readInt];
    XCTAssertEqualObjects([add readString], @"script/udtest.script");

    // the game stops there: the script shown at its line, the session stopped
    UDBitMsg *broke = [self.game message:9 /* BREAK */];
    [broke writeInt:3];
    [broke writeString:@"script/udtest.script"];
    [self.game send:broke];
    XCTAssertNotNil([self receive:13 /* INSPECTTHREADS */ within:10]);
    UDBitMsg *threads = [self.game message:13];
    [threads writeShort:1];
    [threads writeString:@"udtest_main"];
    [threads writeInt:2];
    [threads writeBits:1 numBits:1];
    [threads writeBits:0 numBits:3];
    [self.game send:threads];
    UDBitMsg *stack = [self.game message:12 /* INSPECTCALLSTACK */];
    [stack writeShort:1];
    [stack writeString:@"udtest_main(  )"];
    [stack writeString:@"script/udtest.script"];
    [stack writeInt:3];
    [self.game send:stack];
    UDDebugSession *session = controller.scriptDebugger.session;
    XCTAssertTrue([self spinUntil:^BOOL{ return session.state == UDDebugSessionStateStopped && session.selectedFrame != nil; } timeout:10]);
    XCTAssertEqual(session.selectedFrame.line, 3);
    UDTextEditorViewController *shown = (UDTextEditorViewController *)[[self tabManagerOf:controller] selectedEditor];
    XCTAssertEqualObjects(shown.item.path, @"script/udtest.script", @"the stopped frame's script, in its tab");

    // its variables and the watch, each asked of the game by name
    NSDate *until = [NSDate dateWithTimeIntervalSinceNow:10];
    BOOL answered = NO;
    while (until.timeIntervalSinceNow > 0 && !answered) {
        UDBitMsg *inspect = [self receive:11 /* INSPECTVARIABLE */ within:1];
        if (inspect != nil) {
            int depth = [inspect readShort];
            NSString *name = [inspect readString];
            UDBitMsg *value = [self.game message:11];
            [value writeShort:depth];
            [value writeString:name];
            [value writeString:[name isEqualToString:@"count"] ? @"2" : @"???"];
            [self.game send:value];
        }
        UDDebugVariable *locals = session.scopes.firstObject;
        answered = [[locals.children valueForKey:@"value"] containsObject:@"2"]
            && [[session.watches valueForKey:@"value"] containsObject:@"2"];
    }
    XCTAssertTrue(answered, @"locals %@, watches %@", session.scopes.firstObject.children, session.watches);

    // going on, then stopping
    [controller debugContinueOrPause:nil];
    XCTAssertNotNil([self receive:7 /* RESUME */ within:10]);
    [controller stopDebugging:nil];
    XCTAssertNotNil([self receive:3 /* DISCONNECT */ within:10], @"the game takes its breakpoints off and goes on");
    XCTAssertTrue([self spinUntil:^BOOL{ return !controller.scriptDebugger.debugging; } timeout:10]);
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:breakpoints.autosaveName];
}

/// The lines of the file at @a path (none, there being none).
- (NSArray<NSString *> *)linesOf:(NSString *)path {
    NSString *text = [[NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:NULL] ?: @""
                      stringByTrimmingCharactersInSet:[NSCharacterSet newlineCharacterSet]];
    return text.length > 0 ? [text componentsSeparatedByString:@"\n"] : @[];
}

/// Debug > Run while a game runs: a restart, as Xcode's. The game (a
/// script that notes its process and waits) quits, and another is run.
- (void)testRunWhileDebuggingRestartsTheGame {
    NSString *base = [self.scratchDirectory stringByAppendingPathComponent:@"install"];
    NSString *save = [self.scratchDirectory stringByAppendingPathComponent:@"save"];
    for (NSString *folder in @[[base stringByAppendingPathComponent:@"base"], save]) {
        [[NSFileManager defaultManager] createDirectoryAtPath:folder withIntermediateDirectories:YES attributes:nil error:NULL];
    }
    NSString *started = [self.scratchDirectory stringByAppendingPathComponent:@"started"];
    NSString *game = [self.scratchDirectory stringByAppendingPathComponent:@"game.sh"];
    [[NSString stringWithFormat:@"#!/bin/sh\necho $$ >> '%@'\nexec sleep 60\n", started]
        writeToFile:game atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    [[NSFileManager defaultManager] setAttributes:@{ NSFilePosixPermissions: @0755 } ofItemAtPath:game error:NULL];
    self.game = [[UDFakeScriptDebugger alloc] initWithPort:[UDFakeScriptDebugger gamePort] debuggerPort:[UDFakeScriptDebugger debuggerPort]];
    if (self.game == nil || [UDScriptDebugger adapterPath] == nil) return;

    UDWorkspaceWindowController *controller = [self openWorkspaceWithSettings:[self workspaceSettingsWithBasePath:base savePath:save]];
    if (controller == nil) return;
    UDWorkspace *workspace = ((UDWorkspaceDocument *)controller.document).workspace;
    [workspace setSettings:@{ @"port": @([UDFakeScriptDebugger gamePort]), @"localPort": @([UDFakeScriptDebugger debuggerPort]) }
                   forTool:@"Debugger"];
    workspace.gameExecutable = game;

    // Run: the game started, its debugger server saying it is there
    [controller startDebugging:nil];
    XCTAssertTrue([self spinUntil:^BOOL{ return [self linesOf:started].count == 1; } timeout:20]);
    [self.game send:[self.game message:1 /* CONNECT */]];
    XCTAssertNotNil([self receive:2 /* CONNECTED */ within:10]);
    pid_t first = (pid_t)[self linesOf:started][0].intValue;
    XCTAssertTrue([controller validateMenuItem:[[NSMenuItem alloc] initWithTitle:@"Run" action:@selector(startDebugging:) keyEquivalent:@""]],
                  @"Run while debugging");

    [controller startDebugging:nil];
    XCTAssertTrue([self spinUntil:^BOOL{ return [self linesOf:started].count == 2; } timeout:20], @"run again: %@", [self linesOf:started]);
    XCTAssertNotEqual(kill(first, 0), 0, @"the first game quit");
    XCTAssertTrue(controller.scriptDebugger.debugging);

    [controller stopDebugging:nil];
    XCTAssertTrue([self spinUntil:^BOOL{ return !controller.scriptDebugger.debugging; } timeout:10]);
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:controller.scriptDebugger.breakpoints.autosaveName];
}

@end
