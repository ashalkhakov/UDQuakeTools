//
//  UDScriptDebugAdapter.h
//  udscript-dap
//
//  The Debug Adapter Protocol for a mod's scripts, over the game's script
//  debugger (UDScriptDebuggerConnection): a DAP client debugs idScript in
//  a running dhewm3. What DAP asks maps onto DBMSG_*:
//
//    setBreakpoints      ADDBREAKPOINT / REMOVEBREAKPOINT (each resent when
//                        the game connects; a line with no code, the game
//                        takes off, and the breakpoint is unverified)
//    continue, next,     RESUME, STEPOVER, STEPINTO, BREAK (the game has no
//    stepIn, pause       step out)
//    threads, stackTrace INSPECTTHREADS, INSPECTCALLSTACK
//    scopes, variables   the frame's function's parameters and locals, read
//                        from its script (UDScriptIndex), each INSPECTVARIABLE'd:
//                        the game reads a variable by name but cannot list them
//    evaluate            INSPECTVARIABLE; in the console, a command
//                        (EXECCOMMAND) unless stopped and a name; '/' or '\'
//                        first, always a command
//    loadedSources       INSPECTSCRIPTS
//    output events       PRINT, and a launched game's own output
//
//  initialized is sent once launch or attach says where the workspace is
//  (the breakpoints' paths are relative to it); launch starts the game
//  (its "program", with "args") with the debugger
//  server on (+set com_enableDebuggerServer 1); attach asks a running one
//  (DBMSG_CONNECT). Both take the workspace's "settings" (fs_basepath,
//  fs_game, ...: what a script's path is relative to, and where a script in
//  a pak is read from) and, for tests, "host", "port" and "localPort".
//

#import <Foundation/Foundation.h>
#import "UDDAPConnection.h"
#import "UDScriptDebuggerConnection.h"

NS_ASSUME_NONNULL_BEGIN

@interface UDScriptDebugAdapter : NSObject <UDScriptDebuggerConnectionDelegate>

/// Answering on @a queue, writing to @a output.
- (instancetype)initWithQueue:(dispatch_queue_t)queue output:(FILE *)output;
@property (nonatomic, strong, readonly) UDDAPConnection *connection;

/// The script at @a path on disk, as the game names it ("script/doom_main.script"),
/// and back; nil where none of the workspace's folders holds it.
- (nullable NSString *)gamePathOf:(NSString *)path;
- (nullable NSString *)diskPathOf:(NSString *)gamePath;

@end

NS_ASSUME_NONNULL_END
