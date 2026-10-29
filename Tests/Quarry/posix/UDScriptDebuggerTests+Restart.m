//
//  UDScriptDebuggerTests+Restart.m
//  QuarryTests
//
//  The script debugger's tests that run a shell script as the game
//  (#!/bin/sh): a POSIX system's, which Windows does not build (posix/).
//

#import <XCTest/XCTest.h>
#import <UDCodeKit/UDCodeKit.h>
#import "../UDScriptDebuggerTests.h"
#import "UDScriptDebugger.h"
#import "UDWorkspaceWindowController.h"
#import "UDWorkspaceDocument.h"
#import "UDWorkspace.h"

#include <signal.h>

@implementation UDScriptDebuggerTests (Restart)

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
    XCTAssertTrue([self spinUntil:^BOOL{ return controller.scriptDebugger.session.processID == first; } timeout:10],
                  @"the game's process, as the adapter says it: %d", controller.scriptDebugger.session.processID);
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
