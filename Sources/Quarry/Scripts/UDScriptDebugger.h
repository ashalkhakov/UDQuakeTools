/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 * UDScriptDebugger.h — a workspace window's script debugging (not the
 * engine's: its debugger was a window of its own): UDCodeKit's debugger
 * (the breakpoints its script editors show, a session, the debug bar,
 * navigator and area) over udscript-dap, which Quarry carries beside its
 * executable. Run starts the workspace's game (its gameExecutable, with its
 * gameArguments) with the script debugger on; Attach debugs one started so.
 * A script is named by its path on disk, or where it would be in the mod's
 * folder when it is in a pak (UDWorkspace's diskPathOfGamePath:), as the
 * adapter names it too.
 */

#import <Cocoa/Cocoa.h>
#import <UDCodeKit/UDCodeKit.h>

@class UDWorkspace, UDScriptDebugger;

NS_ASSUME_NONNULL_BEGIN

@protocol UDScriptDebuggerDelegate <NSObject>
/// Show the script at @a gamePath ("script/lamp.script"), at @a line (1-based).
- (void)scriptDebugger:(UDScriptDebugger *)debugger showScript:(NSString *)gamePath line:(NSInteger)line;
@optional
/// A session started: its views want showing.
- (void)scriptDebuggerDidStart:(UDScriptDebugger *)debugger;
- (void)scriptDebuggerDidEnd:(UDScriptDebugger *)debugger;
@end

@interface UDScriptDebugger : NSObject <UDDebugSessionDelegate>

- (instancetype)initWithWorkspace:(UDWorkspace *)workspace;
@property (nonatomic, weak, nullable) id<UDScriptDebuggerDelegate> delegate;

/// The window's breakpoints, which its script editors show.
@property (nonatomic, strong, readonly) UDBreakpointStore *breakpoints;
/// The session, while there is one (ended: still, until the next).
@property (nonatomic, strong, readonly, nullable) UDDebugSession *session;
@property (nonatomic, readonly, getter=isDebugging) BOOL debugging;
@property (nonatomic, strong, readonly) UDDebugBarViewController *bar;
@property (nonatomic, strong, readonly) UDDebugNavigatorViewController *navigator;
@property (nonatomic, strong, readonly) UDDebugAreaViewController *area;
/// The breakpoints (and the adapter's exception filters), as a navigator lists them.
@property (nonatomic, strong, readonly) UDBreakpointNavigatorViewController *breakpointNavigator;

/// The adapter: $UD_SCRIPT_DAP (the tests'), else udscript-dap beside the
/// app's executable.
+ (nullable NSString *)adapterPath;

/// Run: the game started for debugging. NO, with @a error (what to set),
/// when the workspace names no game. While a session is on, a restart: it
/// ends (its game quits), and the game is run again.
- (BOOL)run:(NSError **)error;
/// Attach: a game started with com_enableDebuggerServer 1.
- (BOOL)attach:(NSError **)error;
- (void)stop;

/// A command line's words: split at white space, a quoted one kept whole.
+ (NSArray<NSString *> *)argumentsOfCommandLine:(NSString *)line;

@end

NS_ASSUME_NONNULL_END
