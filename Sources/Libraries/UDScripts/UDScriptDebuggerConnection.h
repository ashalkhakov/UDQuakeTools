//
//  UDScriptDebuggerConnection.h
//  UDCore
//
//  The game's script debugger, from the debugger's side: rvDebuggerClient's
//  half of the protocol rvDebuggerServer speaks (neo/tools/debugger). The
//  game listens on UDP 27980 and sends to its client on 27981
//  (com_dbgClientAdr's host); each message is an idBitMsg, a short
//  DBMSG_* first. What the game sends is told to the delegate, on the
//  connection's queue.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// DebuggerMessages.h's EDebuggerMessage.
typedef NS_ENUM(int, UDScriptDebuggerMessage) {
    UDScriptDebuggerUnknown,
    UDScriptDebuggerConnect,
    UDScriptDebuggerConnected,
    UDScriptDebuggerDisconnect,
    UDScriptDebuggerAddBreakpoint,
    UDScriptDebuggerRemoveBreakpoint,
    UDScriptDebuggerHitBreakpoint,
    UDScriptDebuggerResume,
    UDScriptDebuggerResumed,
    UDScriptDebuggerBreak,
    UDScriptDebuggerPrint,
    UDScriptDebuggerInspectVariable,
    UDScriptDebuggerInspectCallstack,
    UDScriptDebuggerInspectThreads,
    UDScriptDebuggerStepOver,
    UDScriptDebuggerStepInto,
    UDScriptDebuggerInspectScripts,
    UDScriptDebuggerExecCommand,
    // a newer server's (protocol 2): its version and capabilities, step out,
    // a frame's variables listed
    UDScriptDebuggerVersion,
    UDScriptDebuggerStepOut,
    UDScriptDebuggerInspectVariables,
};

/// DBMSG_VERSION's capabilities (DBCAP_*).
typedef NS_OPTIONS(int, UDScriptDebuggerCapabilities) {
    UDScriptDebuggerCapabilityStepOut = 1,
    UDScriptDebuggerCapabilityInspectVariables = 2,
};

/// A variable DBMSG_INSPECTVARIABLES lists (DBVAR_*: a parameter or local,
/// or a field of the object the function is a method of).
@interface UDScriptVariableInfo : NSObject
@property (nonatomic, copy, readonly) NSString *name;
@property (nonatomic, copy, readonly) NSString *value;
@property (nonatomic, readonly, getter=isField) BOOL field;
- (instancetype)initWithName:(NSString *)name value:(NSString *)value field:(BOOL)field;
@end

/// A call stack entry, as MSG_WriteCallstackFunc writes it: the function
/// ("lamp::flicker(  )"), and the script and line it is at (for the
/// frames under the first, the call it made).
@interface UDScriptStackFrame : NSObject
@property (nonatomic, copy, readonly) NSString *function;
@property (nonatomic, copy, readonly) NSString *path;
@property (nonatomic, readonly) int line;
- (instancetype)initWithFunction:(NSString *)function path:(NSString *)path line:(int)line;
@end

/// A script thread, as MSG_WriteThreadInfo writes it.
@interface UDScriptThreadInfo : NSObject
@property (nonatomic, copy, readonly) NSString *name;
@property (nonatomic, readonly) int number;
/// The thread the game stopped in.
@property (nonatomic, readonly, getter=isCurrent) BOOL current;
@property (nonatomic, readonly, getter=isDoneProcessing) BOOL doneProcessing;
@property (nonatomic, readonly, getter=isWaiting) BOOL waiting;
@property (nonatomic, readonly, getter=isDying) BOOL dying;
- (instancetype)initWithName:(NSString *)name number:(int)number current:(BOOL)current
              doneProcessing:(BOOL)doneProcessing waiting:(BOOL)waiting dying:(BOOL)dying;
@end

@class UDScriptDebuggerConnection;

@protocol UDScriptDebuggerConnectionDelegate <NSObject>
@optional
/// DBMSG_CONNECT or DBMSG_CONNECTED: the game is there (it lost what
/// breakpoints it had, if it started again).
- (void)debuggerConnectionDidConnect:(UDScriptDebuggerConnection *)connection;
/// DBMSG_DISCONNECT: the game is going.
- (void)debuggerConnectionDidDisconnect:(UDScriptDebuggerConnection *)connection;
/// DBMSG_BREAK: stopped, at @a line of the script at @a path.
- (void)debuggerConnection:(UDScriptDebuggerConnection *)connection didBreakAtLine:(int)line path:(NSString *)path;
/// DBMSG_RESUMED.
- (void)debuggerConnectionDidResume:(UDScriptDebuggerConnection *)connection;
/// DBMSG_PRINT: what the console printed.
- (void)debuggerConnection:(UDScriptDebuggerConnection *)connection didPrint:(NSString *)text;
/// DBMSG_REMOVEBREAKPOINT: the game has no breakpoint at @a line of
/// @a path (no code there), or no longer (one that broke once).
- (void)debuggerConnection:(UDScriptDebuggerConnection *)connection didRemoveBreakpointAtLine:(int)line path:(NSString *)path;
/// DBMSG_INSPECTCALLSTACK's answer: the stopped thread's frames, the
/// innermost first.
- (void)debuggerConnection:(UDScriptDebuggerConnection *)connection didReceiveCallstack:(NSArray<UDScriptStackFrame *> *)frames;
/// DBMSG_INSPECTTHREADS's answer.
- (void)debuggerConnection:(UDScriptDebuggerConnection *)connection didReceiveThreads:(NSArray<UDScriptThreadInfo *> *)threads;
/// DBMSG_INSPECTVARIABLE's answer: "???" for what it cannot read.
- (void)debuggerConnection:(UDScriptDebuggerConnection *)connection didReceiveValue:(NSString *)value
                  variable:(NSString *)name scopeDepth:(int)scopeDepth;
/// DBMSG_VERSION: a server that says what it supports (an older one says
/// nothing).
- (void)debuggerConnection:(UDScriptDebuggerConnection *)connection didReceiveVersion:(int)version
              capabilities:(UDScriptDebuggerCapabilities)capabilities;
/// DBMSG_INSPECTVARIABLES' answer.
- (void)debuggerConnection:(UDScriptDebuggerConnection *)connection didReceiveVariables:(NSArray<UDScriptVariableInfo *> *)variables
                scopeDepth:(int)scopeDepth;
/// DBMSG_INSPECTSCRIPTS's answer: the scripts the game loaded.
- (void)debuggerConnection:(UDScriptDebuggerConnection *)connection didReceiveScripts:(NSArray<NSString *> *)paths;
@end

@interface UDScriptDebuggerConnection : NSObject

/// The game at @a host (its port: 27980), heard on @a localPort (27981;
/// the game sends there and nowhere else); the delegate told on @a queue.
- (instancetype)initWithHost:(NSString *)host port:(uint16_t)port localPort:(uint16_t)localPort
                       queue:(dispatch_queue_t)queue;
@property (nonatomic, weak, nullable) id<UDScriptDebuggerConnectionDelegate> delegate;

/// Listening (NO, with @a error, when the port is taken).
- (BOOL)open:(NSError **)error;
- (void)close;
@property (nonatomic, readonly, getter=isConnected) BOOL connected;

// What the debugger sends (rvDebuggerClient's).
- (void)sendConnect;
- (void)sendDisconnect;
- (void)addBreakpointAtLine:(int)line path:(NSString *)path identifier:(int)identifier onceOnly:(BOOL)onceOnly;
- (void)removeBreakpoint:(int)identifier;
- (void)resume;
- (void)breakNext;
- (void)stepOver;
- (void)stepInto;
/// A newer server's (UDScriptDebuggerCapabilityStepOut).
- (void)stepOut;
/// A newer server's (UDScriptDebuggerCapabilityInspectVariables): the
/// variables of the frame at @a scopeDepth (as for -inspectVariable:).
- (void)inspectVariablesAtScopeDepth:(int)scopeDepth;
- (void)inspectCallstack;
- (void)inspectThreads;
/// @a scopeDepth: -1 for the function stopped in, else the interpreter's
/// call stack index of the frame's.
- (void)inspectVariable:(NSString *)name scopeDepth:(int)scopeDepth;
- (void)inspectScripts;
- (void)executeCommand:(NSString *)command;

/// One message's bytes, as the connection sends it (for the tests).
+ (NSData *)messageWithType:(UDScriptDebuggerMessage)type;

@end

NS_ASSUME_NONNULL_END
