//
//  UDScriptDebugAdapter.m
//  udscript-dap
//

#import "UDScriptDebugAdapter.h"
#import "UDScriptIndex.h"
#import "UDScriptExpression.h"
#import "UDWorkspace.h"
#import "idFileSystem.h"

/// A breakpoint as the client set it, and as the game has it.
@interface UDScriptBreakpoint : NSObject
@property (nonatomic) int identifier;
@property (nonatomic) int line;
@property (nonatomic) BOOL verified;
/// DAP's SourceBreakpoint options, which the adapter keeps (the game has
/// none): a condition, a hit count condition, a logpoint's message in
/// pieces; and how often it was reached.
@property (nonatomic, strong, nullable) UDScriptExpression *condition;
@property (nonatomic, copy, nullable) NSString *hitCondition;
@property (nonatomic, copy, nullable) NSArray *logParts;
@property (nonatomic) NSInteger hits;
/// Why the options do not read, if they do not.
@property (nonatomic, copy, nullable) NSString *problem;
@end

@implementation UDScriptBreakpoint
@end

/// Variables asked of the game for one frame's scope, the request waiting
/// on them.
@interface UDScriptVariablesQuery : NSObject
@property (nonatomic, strong) UDDAPRequest *request;
@property (nonatomic) int scopeDepth;
@property (nonatomic, copy) NSArray<NSString *> *names;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSString *> *values;
@end

@implementation UDScriptVariablesQuery
@end

/// The variables a stop's breakpoints' conditions and messages read, asked
/// of the game before the stop is decided.
@interface UDScriptConditionQuery : NSObject
@property (nonatomic, copy) NSArray<UDScriptBreakpoint *> *breakpoints;
@property (nonatomic, copy) NSSet<NSString *> *names;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSString *> *values;
@property (nonatomic) BOOL decided;
@end

@implementation UDScriptConditionQuery
@end

/// A step's temporary breakpoints' identifiers start here, away from the client's.
static const int UDStepBreakpointBase = 1000000;

/// How long an answer the game owes is waited for.
static const int64_t UDGameAnswerTimeout = 2 * NSEC_PER_SEC;

@implementation UDScriptDebugAdapter {
    dispatch_queue_t _queue;
    UDScriptDebuggerConnection *_game;
    UDWorkspace *_workspace;
    NSArray<NSString *> *_roots;                 // the folders scripts' paths are relative to
    NSTask *_task;                               // a launched game

    UDDAPRequest *_connectRequest;               // the launch or attach that waits for the game
    int _connectAttempts;

    NSMutableDictionary<NSString *, NSMutableArray<UDScriptBreakpoint *> *> *_breakpoints;   // by game path
    NSMutableDictionary<NSString *, NSString *> *_sourcePaths;                               // a game path's disk path, as set
    int _nextBreakpoint;
    NSArray<NSString *> *_loadedScripts;         // as the game names them

    BOOL _stopped;
    NSString *_stopReason;
    int _stopLine;
    NSString *_stopPath;
    NSArray<UDScriptThreadInfo *> *_threads;
    NSArray<UDScriptStackFrame *> *_frames;
    NSMutableArray<UDDAPRequest *> *_threadRequests;
    NSMutableArray<UDDAPRequest *> *_stackRequests;
    NSMutableArray<UDDAPRequest *> *_scriptRequests;
    BOOL _announceStop;
    NSMutableArray<UDScriptVariablesQuery *> *_variableQueries;
    NSMutableArray<NSString *> *_sourceReferences;   // game paths, by sourceReference - 1

    int _engineVersion;                          // DBMSG_VERSION's (0: a server that does not say)
    UDScriptDebuggerCapabilities _engineCapabilities;
    // a step: the thread it is of, its temporary breakpoints (a server
    // whose steps other threads end: the steps the adapter takes itself)
    BOOL _stepping;
    int _stepThread;
    NSMutableArray<NSNumber *> *_stepBreakpoints;
    int _nextStepBreakpoint;
    BOOL _pauseAsked;
    UDScriptConditionQuery *_conditionQuery;
    NSMutableArray<NSArray *> *_listRequests;    // @[request, depth, kind] waiting on DBMSG_INSPECTVARIABLES
    UDScriptIndex *_objectIndex;                 // the loaded scripts' objects, for their fields
}

- (instancetype)initWithQueue:(dispatch_queue_t)queue output:(FILE *)output {
    if (!(self = [super init])) return nil;
    _queue = queue;
#if !OS_OBJECT_USE_OBJC
    dispatch_retain(queue);
#endif
    _connection = [[UDDAPConnection alloc] initWithTarget:self queue:queue output:output];
    for (NSArray<NSString *> *command in @[
             @[@"initialize", @"initialize:"], @[@"launch", @"launch:"], @[@"attach", @"attach:"],
             @[@"setBreakpoints", @"setBreakpoints:"], @[@"configurationDone", @"configurationDone:"],
             @[@"threads", @"threads:"], @[@"stackTrace", @"stackTrace:"], @[@"scopes", @"scopes:"],
             @[@"variables", @"variables:"], @[@"evaluate", @"evaluate:"], @[@"continue", @"continueRequest:"],
             @[@"next", @"next:"], @[@"stepIn", @"stepIn:"], @[@"stepOut", @"stepOut:"], @[@"pause", @"pause:"],
             @[@"source", @"source:"],
             @[@"loadedSources", @"loadedSources:"], @[@"disconnect", @"disconnect:"], @[@"terminate", @"terminate:"]]) {
        [_connection setRequestAction:NSSelectorFromString(command[1]) forCommand:command[0]];
    }
    _breakpoints = [NSMutableDictionary dictionary];
    _sourcePaths = [NSMutableDictionary dictionary];
    _nextBreakpoint = 1;
    _threadRequests = [NSMutableArray array];
    _stackRequests = [NSMutableArray array];
    _scriptRequests = [NSMutableArray array];
    _variableQueries = [NSMutableArray array];
    _sourceReferences = [NSMutableArray array];
    _stepBreakpoints = [NSMutableArray array];
    _nextStepBreakpoint = UDStepBreakpointBase;
    _listRequests = [NSMutableArray array];
    _roots = @[];
    return self;
}

#if !OS_OBJECT_USE_OBJC
- (void)dealloc {
    dispatch_release(_queue);
}
#endif

#pragma mark - Paths

/// The workspace the settings say: its game folders, what a script's game
/// path is relative to (UDWorkspace's gameFolders, as Quarry's editors name
/// scripts), and its file system, where a script in a pak is read from.
- (void)_useSettings:(NSDictionary *)settings {
    UDWorkspace *workspace = [[UDWorkspace alloc] initWithDictionary:settings rootDirectory:settings[@"fs_basepath"] ?: @""];
    _roots = workspace.gameFolders;
    if (settings[@"fs_basepath"] == nil) return;
    NSError *error = nil;
    if ([workspace startup:&error]) {
        _workspace = workspace;
    } else {
        [self _output:[NSString stringWithFormat:@"The workspace does not start: %@\n", error.localizedDescription] category:@"stderr"];
    }
}

- (NSString *)gamePathOf:(NSString *)path {
    NSString *standard = path.stringByStandardizingPath;
    if (!standard.isAbsolutePath) return standard;
    for (NSString *root in _roots) {
        NSString *prefix = [root stringByAppendingString:@"/"];
        if ([standard hasPrefix:prefix]) {
            NSString *relative = [standard substringFromIndex:prefix.length];
            // the game's spelling, which its breakpoints are matched against
            for (NSString *loaded in _loadedScripts) {
                if ([loaded caseInsensitiveCompare:relative] == NSOrderedSame) return loaded;
            }
            return relative;
        }
    }
    return nil;
}

- (NSString *)diskPathOf:(NSString *)gamePath {
    NSString *set = _sourcePaths[gamePath.lowercaseString];
    if (set != nil) return set;
    for (NSString *root in _roots) {
        NSString *path = [root stringByAppendingPathComponent:gamePath];
        if ([[NSFileManager defaultManager] fileExistsAtPath:path]) return path;
    }
    return nil;
}

/// DAP's Source for a game path: the file on disk, or (in a pak) one the
/// client asks the adapter for by reference.
- (NSDictionary *)_sourceOf:(NSString *)gamePath {
    NSString *disk = [self diskPathOf:gamePath];
    if (disk != nil) return @{ @"name": gamePath.lastPathComponent, @"path": disk };
    NSUInteger index = [_sourceReferences indexOfObject:gamePath];
    if (index == NSNotFound) {
        [_sourceReferences addObject:gamePath];
        index = _sourceReferences.count - 1;
    }
    NSMutableDictionary *source = [@{ @"name": gamePath.lastPathComponent, @"sourceReference": @(index + 1),
                                      @"origin": gamePath } mutableCopy];
    // where it would be in the mod's folder: what a client names it by (its
    // text the source request's, as DAP has it for a path with a reference)
    for (NSString *root in _roots) {
        if ([[NSFileManager defaultManager] fileExistsAtPath:root]) {
            source[@"path"] = [root stringByAppendingPathComponent:gamePath];
            break;
        }
    }
    return source;
}

/// A script's text: from disk, or from the workspace's file system.
- (NSString *)_textOf:(NSString *)gamePath {
    NSString *disk = [self diskPathOf:gamePath];
    if (disk != nil) {
        NSData *data = [NSData dataWithContentsOfFile:disk];
        if (data != nil) {
            return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]
                ?: [[NSString alloc] initWithData:data encoding:NSISOLatin1StringEncoding];
        }
    }
    if (_workspace.fileSystem == nil) return nil;
    void *buffer = NULL;
    int length = [_workspace.fileSystem readFile:gamePath buffer:&buffer timestamp:NULL error:NULL];
    if (length < 0 || buffer == NULL) return nil;
    NSData *data = [NSData dataWithBytes:buffer length:(NSUInteger)length];
    [_workspace.fileSystem freeFile:buffer error:NULL];
    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]
        ?: [[NSString alloc] initWithData:data encoding:NSISOLatin1StringEncoding];
}

- (void)_output:(NSString *)text category:(NSString *)category {
    [_connection sendEvent:@"output" body:@{ @"category": category, @"output": text ?: @"" }];
}

#pragma mark - The session

- (void)initialize:(UDDAPRequest *)request {
    [request respondWithBody:@{
        @"supportsConfigurationDoneRequest": @YES,
        @"supportsEvaluateForHovers": @YES,
        @"supportsTerminateRequest": @YES,
        @"supportsLoadedSourcesRequest": @YES,
        @"supportsStepBack": @NO,
        @"supportsSetVariable": @NO,
        @"supportsRestartRequest": @NO,
        @"supportsConditionalBreakpoints": @YES,
        @"supportsHitConditionalBreakpoints": @YES,
        @"supportsLogPoints": @YES,
    }];
}

/// The connection to the game, listening; NO (the request failed) where the
/// port is taken.
- (BOOL)_openGameFor:(UDDAPRequest *)request {
    NSDictionary *arguments = request.arguments;
    NSDictionary *settings = arguments[@"settings"];
    if ([settings isKindOfClass:[NSDictionary class]]) [self _useSettings:settings];
    NSArray *roots = arguments[@"sourceRoots"];
    if ([roots isKindOfClass:[NSArray class]]) {
        NSMutableArray *all = [_roots mutableCopy];
        for (NSString *root in roots) {
            if ([root isKindOfClass:[NSString class]]) [all addObject:root.stringByStandardizingPath];
        }
        _roots = all;
    }
    NSString *host = [arguments[@"host"] isKindOfClass:[NSString class]] ? arguments[@"host"] : @"127.0.0.1";
    uint16_t port = arguments[@"port"] ? (uint16_t)[arguments[@"port"] intValue] : 27980;
    uint16_t localPort = arguments[@"localPort"] ? (uint16_t)[arguments[@"localPort"] intValue] : 27981;
    _game = [[UDScriptDebuggerConnection alloc] initWithHost:host port:port localPort:localPort queue:_queue];
    _game.delegate = self;
    NSError *error = nil;
    if (![_game open:&error]) {
        [request failWithMessage:[NSString stringWithFormat:@"The debugger cannot listen: %@", error.localizedDescription]];
        _game = nil;
        return NO;
    }
    // the breakpoints now, the workspace known: what their paths are relative to
    [_connection sendEvent:@"initialized" body:nil];
    return YES;
}

- (void)launch:(UDDAPRequest *)request {
    NSDictionary *arguments = request.arguments;
    NSString *program = arguments[@"program"];
    if (![program isKindOfClass:[NSString class]] || program.length == 0) {
        [request failWithMessage:@"launch needs the game's program"];
        return;
    }
    if (![self _openGameFor:request]) return;
    // a Mac application: its executable
    if ([program.pathExtension isEqualToString:@"app"]) {
        NSString *executable = [NSBundle bundleWithPath:program].executablePath;
        if (executable != nil) program = executable;
    }
    NSMutableArray<NSString *> *args = [NSMutableArray array];
    NSDictionary *settings = arguments[@"settings"];
    if ([settings isKindOfClass:[NSDictionary class]]) {
        for (NSString *key in @[@"fs_basepath", @"fs_savepath", @"fs_game", @"fs_game_base"]) {
            NSString *value = settings[key];
            if ([value isKindOfClass:[NSString class]] && value.length > 0) [args addObjectsFromArray:@[@"+set", key, value]];
        }
    }
    [args addObjectsFromArray:@[@"+set", @"com_enableDebuggerServer", @"1", @"+set", @"com_dbgClientAdr", @"127.0.0.1"]];
    for (id arg in [arguments[@"args"] isKindOfClass:[NSArray class]] ? arguments[@"args"] : @[]) {
        if ([arg isKindOfClass:[NSString class]]) [args addObject:arg];
    }

    NSTask *task = [[NSTask alloc] init];
    task.launchPath = program;
    task.arguments = args;
    NSString *cwd = arguments[@"cwd"];
    task.currentDirectoryPath = [cwd isKindOfClass:[NSString class]] && cwd.length > 0 ? cwd : program.stringByDeletingLastPathComponent;
    // its output an event's, never the protocol's stdout
    NSPipe *pipe = [NSPipe pipe];
    task.standardOutput = pipe;
    task.standardError = pipe;
    task.standardInput = [NSFileHandle fileHandleWithNullDevice];
    NSFileHandle *reading = pipe.fileHandleForReading;
    [NSThread detachNewThreadSelector:@selector(_forwardOutput:) toTarget:self withObject:reading];
    @try {
        [task launch];
    } @catch (NSException *exception) {
        [request failWithMessage:[NSString stringWithFormat:@"%@ does not start: %@", program, exception.reason]];
        return;
    }
    _task = task;
    [NSThread detachNewThreadSelector:@selector(_waitForExit:) toTarget:self withObject:task];
    // the game says DBMSG_CONNECT as its debugger server starts
    _connectRequest = request;
}

- (void)_forwardOutput:(NSFileHandle *)handle {
    for (;;) {
        @autoreleasepool {
            NSData *data = [handle availableData];
            if (data.length == 0) return;
            NSString *text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]
                ?: [[NSString alloc] initWithData:data encoding:NSISOLatin1StringEncoding];
            dispatch_async(_queue, ^{
                [self _output:text category:@"stdout"];
            });
        }
    }
}

- (void)_waitForExit:(NSTask *)task {
    [task waitUntilExit];
    int status = task.terminationStatus;
    dispatch_async(_queue, ^{
        if (self->_task != task) return;
        self->_task = nil;
        if (self->_connectRequest != nil) {
            [self->_connectRequest failWithMessage:[NSString stringWithFormat:@"The game exited (%d) before its debugger connected", status]];
            self->_connectRequest = nil;
        }
        [self->_connection sendEvent:@"exited" body:@{ @"exitCode": @(status) }];
        [self->_connection sendEvent:@"terminated" body:nil];
    });
}

- (void)attach:(UDDAPRequest *)request {
    if (![self _openGameFor:request]) return;
    _connectRequest = request;
    _connectAttempts = 0;
    [self _tryConnect];
}

/// rvDebuggerClient's connect, again each second until the game answers
/// (ten times).
- (void)_tryConnect {
    if (_connectRequest == nil || _game.connected) return;
    if (_connectAttempts++ >= 10) {
        [_connectRequest failWithMessage:@"The game does not answer: is it running with com_enableDebuggerServer 1?"];
        _connectRequest = nil;
        return;
    }
    [_game sendConnect];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), _queue, ^{
        [self _tryConnect];
    });
}

- (void)configurationDone:(UDDAPRequest *)request {
    [request respondWithBody:nil];
}

- (void)disconnect:(UDDAPRequest *)request {
    // the game takes its breakpoints off and goes on
    if (_game.connected) [_game sendDisconnect];
    id terminate = request.arguments[@"terminateDebuggee"];
    if (_task != nil && (terminate == nil || [terminate boolValue])) {
        NSTask *task = _task;
        _task = nil;
        [task terminate];
    }
    [_game close];
    [request respondWithBody:nil];
}

- (void)terminate:(UDDAPRequest *)request {
    if (_task != nil) {
        [_task terminate];
    } else if (_game.connected) {
        [_game executeCommand:@"quit"];
    }
    [request respondWithBody:nil];
}

#pragma mark - The game's (UDScriptDebuggerConnectionDelegate)

- (void)debuggerConnectionDidConnect:(UDScriptDebuggerConnection *)connection {
    // rvDebuggerClient::SendBreakpoints: the game has none of them now
    for (NSString *path in _breakpoints) {
        for (UDScriptBreakpoint *breakpoint in _breakpoints[path]) {
            if (breakpoint.problem != nil) continue;
            [_game addBreakpointAtLine:breakpoint.line path:path identifier:breakpoint.identifier onceOnly:NO];
            if (breakpoint.verified) continue;
            // the game's to refuse now (no code on its line)
            breakpoint.verified = YES;
            [_connection sendEvent:@"breakpoint" body:@{ @"reason": @"changed",
                                                         @"breakpoint": [self _describe:breakpoint path:path message:nil] }];
        }
    }
    [_game inspectScripts];
    if (_connectRequest != nil) {
        [_connectRequest respondWithBody:nil];
        _connectRequest = nil;
    }
}

- (void)debuggerConnectionDidDisconnect:(UDScriptDebuggerConnection *)connection {
    _stopped = NO;
    // a launched game goes on to exit, which ends the session
    if (_task == nil) [_connection sendEvent:@"terminated" body:nil];
}

- (void)debuggerConnection:(UDScriptDebuggerConnection *)connection didPrint:(NSString *)text {
    [self _output:text category:@"console"];
}

- (void)debuggerConnection:(UDScriptDebuggerConnection *)connection didReceiveScripts:(NSArray<NSString *> *)paths {
    _loadedScripts = paths;
    NSArray<UDDAPRequest *> *waiting = [_scriptRequests copy];
    [_scriptRequests removeAllObjects];
    for (UDDAPRequest *request in waiting) [self _answerLoadedSources:request];
}

#pragma mark - Breakpoints

- (void)setBreakpoints:(UDDAPRequest *)request {
    NSDictionary *source = request.arguments[@"source"];
    NSString *path = [source isKindOfClass:[NSDictionary class]] ? source[@"path"] : nil;
    NSString *gamePath = nil;
    if ([path isKindOfClass:[NSString class]]) {
        gamePath = [self gamePathOf:path];
    } else if ([source isKindOfClass:[NSDictionary class]] && source[@"sourceReference"] != nil) {
        NSInteger reference = [source[@"sourceReference"] integerValue];
        if (reference >= 1 && reference <= (NSInteger)_sourceReferences.count) gamePath = _sourceReferences[(NSUInteger)reference - 1];
    }
    NSArray *asked = request.arguments[@"breakpoints"];
    if (![asked isKindOfClass:[NSArray class]]) asked = @[];
    if (gamePath == nil) {
        // not one of the workspace's scripts
        NSMutableArray *unverified = [NSMutableArray array];
        for (NSDictionary *breakpoint in asked) {
            [unverified addObject:@{ @"verified": @NO, @"line": breakpoint[@"line"] ?: @0,
                                     @"message": @"Not one of the workspace's scripts" }];
        }
        [request respondWithBody:@{ @"breakpoints": unverified }];
        return;
    }
    if ([path isKindOfClass:[NSString class]] && [[NSFileManager defaultManager] fileExistsAtPath:path]) {
        _sourcePaths[gamePath.lowercaseString] = path.stringByStandardizingPath;
    }

    for (UDScriptBreakpoint *old in _breakpoints[gamePath]) {
        if (_game.connected) [_game removeBreakpoint:old.identifier];
    }
    NSMutableArray<UDScriptBreakpoint *> *set = [NSMutableArray array];
    NSMutableArray *answered = [NSMutableArray array];
    for (NSDictionary *asking in asked) {
        if (![asking isKindOfClass:[NSDictionary class]]) continue;
        UDScriptBreakpoint *breakpoint = [[UDScriptBreakpoint alloc] init];
        breakpoint.identifier = _nextBreakpoint++;
        breakpoint.line = [asking[@"line"] intValue];
        NSString *problem = nil;
        NSString *condition = [asking[@"condition"] isKindOfClass:[NSString class]] ? asking[@"condition"] : nil;
        if (condition.length > 0) breakpoint.condition = [UDScriptExpression expressionWithText:condition error:&problem];
        NSString *hitCondition = [asking[@"hitCondition"] isKindOfClass:[NSString class]] ? asking[@"hitCondition"] : nil;
        if (hitCondition.length > 0 && problem == nil) {
            [UDScriptExpression hitCount:1 passes:hitCondition error:&problem];
            breakpoint.hitCondition = hitCondition;
        }
        NSString *logMessage = [asking[@"logMessage"] isKindOfClass:[NSString class]] ? asking[@"logMessage"] : nil;
        if (logMessage.length > 0 && problem == nil) breakpoint.logParts = [UDScriptExpression partsOfMessage:logMessage error:&problem];
        breakpoint.problem = problem;
        // the game's answer, if it is connected: none is yes
        breakpoint.verified = _game.connected && breakpoint.problem == nil;
        [set addObject:breakpoint];
        if (_game.connected && breakpoint.problem == nil) {
            [_game addBreakpointAtLine:breakpoint.line path:gamePath identifier:breakpoint.identifier onceOnly:NO];
        }
        [answered addObject:[self _describe:breakpoint path:gamePath message:breakpoint.problem]];
    }
    _breakpoints[gamePath] = set;
    [request respondWithBody:@{ @"breakpoints": answered }];
}

- (NSDictionary *)_describe:(UDScriptBreakpoint *)breakpoint path:(NSString *)gamePath message:(NSString *)message {
    NSMutableDictionary *described = [@{ @"id": @(breakpoint.identifier), @"verified": @(breakpoint.verified),
                                         @"line": @(breakpoint.line), @"source": [self _sourceOf:gamePath] } mutableCopy];
    if (message != nil) described[@"message"] = message;
    return described;
}

/// The game took one off: no code on its line (or a once-only one hit).
- (void)debuggerConnection:(UDScriptDebuggerConnection *)connection didRemoveBreakpointAtLine:(int)line path:(NSString *)path {
    for (NSString *gamePath in _breakpoints) {
        if ([gamePath caseInsensitiveCompare:path] != NSOrderedSame) continue;
        for (UDScriptBreakpoint *breakpoint in _breakpoints[gamePath]) {
            if (breakpoint.line != line || !breakpoint.verified) continue;
            breakpoint.verified = NO;
            [_connection sendEvent:@"breakpoint" body:@{
                @"reason": @"changed",
                @"breakpoint": [self _describe:breakpoint path:gamePath message:@"No code on this line"],
            }];
        }
    }
}

#pragma mark - Stopping and going on

- (void)debuggerConnection:(UDScriptDebuggerConnection *)connection didReceiveVersion:(int)version
              capabilities:(UDScriptDebuggerCapabilities)capabilities {
    _engineVersion = version;
    _engineCapabilities = capabilities;
}

/// A server whose steps stay in their thread (the protocol's version 2 on).
- (BOOL)_engineSteps {
    return (_engineCapabilities & UDScriptDebuggerCapabilityStepOut) != 0;
}

- (void)debuggerConnection:(UDScriptDebuggerConnection *)connection didBreakAtLine:(int)line path:(NSString *)path {
    _stopped = YES;
    _stopLine = line;
    _stopPath = [path copy];
    _stopReason = nil;
    _frames = nil;
    _threads = nil;
    _conditionQuery = nil;
    [_variableQueries removeAllObjects];
    // stopped in which thread: the threads' answer says, then the stop is decided
    _announceStop = YES;
    [_game inspectThreads];
    [_game inspectCallstack];
}

- (void)debuggerConnectionDidResume:(UDScriptDebuggerConnection *)connection {
    if (!_stopped) return;
    [self _forgetStop];
    [_connection sendEvent:@"continued" body:@{ @"threadId": @([self _currentThread]), @"allThreadsContinued": @YES }];
}

- (void)_forgetStop {
    _stopped = NO;
    _frames = nil;
    _threads = nil;
    _conditionQuery = nil;
    [_variableQueries removeAllObjects];
}

- (int)_currentThread {
    for (UDScriptThreadInfo *thread in _threads) {
        if (thread.current) return thread.number;
    }
    return 1;
}

/// The client's breakpoints where the game stopped.
- (NSArray<UDScriptBreakpoint *> *)_breakpointsAtStop {
    NSMutableArray<UDScriptBreakpoint *> *hit = [NSMutableArray array];
    for (NSString *gamePath in _breakpoints) {
        if ([gamePath caseInsensitiveCompare:_stopPath] != NSOrderedSame) continue;
        for (UDScriptBreakpoint *breakpoint in _breakpoints[gamePath]) {
            if (breakpoint.line == _stopLine && breakpoint.problem == nil) [hit addObject:breakpoint];
        }
    }
    return hit;
}

/// The game stopped, the thread known: a stop the client is told of, or
/// one the adapter goes on from (a step's temporary breakpoint reached by
/// another thread; a breakpoint whose condition or hit count says no; a
/// logpoint).
- (void)_decideStop {
    BOOL ownStep = _stepping && [self _currentThread] == _stepThread;
    NSArray<UDScriptBreakpoint *> *hit = [self _breakpointsAtStop];
    if (_pauseAsked) {
        [self _announceStop:@"pause" breakpoints:@[]];
        return;
    }
    if (hit.count == 0) {
        if (_stepping && !ownStep) [self _goOnSilently];
        else [self _announceStop:_stepping ? @"step" : @"breakpoint" breakpoints:@[]];
        return;
    }
    // what the breakpoints' conditions and messages read, asked first
    NSMutableSet<NSString *> *names = [NSMutableSet set];
    for (UDScriptBreakpoint *breakpoint in hit) {
        breakpoint.hits += 1;
        if (breakpoint.condition != nil) [names unionSet:breakpoint.condition.names];
        for (id part in breakpoint.logParts) {
            if ([part isKindOfClass:[UDScriptExpression class]]) [names unionSet:[(UDScriptExpression *)part names]];
        }
    }
    UDScriptConditionQuery *query = [[UDScriptConditionQuery alloc] init];
    query.breakpoints = hit;
    query.names = names;
    query.values = [NSMutableDictionary dictionary];
    _conditionQuery = query;
    if (names.count == 0) {
        [self _decideBreakpoints:query];
        return;
    }
    for (NSString *name in names) [_game inspectVariable:name scopeDepth:-1];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, UDGameAnswerTimeout), _queue, ^{
        [self _decideBreakpoints:query];
    });
}

/// The breakpoints reached, their variables read: a logpoint's message
/// printed; a stop if any breakpoint (no logpoint) says so; else on.
- (void)_decideBreakpoints:(UDScriptConditionQuery *)query {
    if (query.decided || query != _conditionQuery) return;
    query.decided = YES;
    _conditionQuery = nil;
    NSMutableArray<NSNumber *> *stopping = [NSMutableArray array];
    for (UDScriptBreakpoint *breakpoint in query.breakpoints) {
        NSString *problem = nil;
        if (breakpoint.hitCondition != nil && ![UDScriptExpression hitCount:breakpoint.hits passes:breakpoint.hitCondition error:&problem]) {
            continue;
        }
        if (breakpoint.condition != nil) {
            id value = [breakpoint.condition valueWithVariables:query.values error:&problem];
            if (value == nil) {
                // a condition that cannot be evaluated stops, and says why (as VS Code)
                [self _output:[NSString stringWithFormat:@"The breakpoint's condition (%@): %@\n", breakpoint.condition.text, problem]
                     category:@"stderr"];
            } else if (![UDScriptExpression isTrue:value]) {
                continue;
            }
        }
        if (breakpoint.logParts != nil) {
            NSMutableString *message = [NSMutableString string];
            for (id part in breakpoint.logParts) {
                if ([part isKindOfClass:[NSString class]]) {
                    [message appendString:part];
                    continue;
                }
                NSString *why = nil;
                id value = [(UDScriptExpression *)part valueWithVariables:query.values error:&why];
                [message appendString:value != nil ? [UDScriptExpression textOf:value] : [NSString stringWithFormat:@"<%@>", why]];
            }
            [message appendString:@"\n"];
            [_connection sendEvent:@"output" body:@{ @"category": @"console", @"output": message,
                                                     @"source": [self _sourceOf:_stopPath], @"line": @(_stopLine) }];
            continue;
        }
        [stopping addObject:@(breakpoint.identifier)];
    }
    BOOL ownStep = _stepping && [self _currentThread] == _stepThread;
    if (stopping.count > 0) [self _announceStop:@"breakpoint" breakpoints:stopping];
    else if (ownStep) [self _announceStop:@"step" breakpoints:@[]];
    else [self _goOnSilently];
}

/// The client told: stopped (the step's temporary breakpoints taken off).
- (void)_announceStop:(NSString *)reason breakpoints:(NSArray<NSNumber *> *)identifiers {
    [self _endStep];
    _pauseAsked = NO;
    _stopReason = reason;
    NSMutableDictionary *body = [@{ @"reason": reason, @"threadId": @([self _currentThread]), @"allThreadsStopped": @YES } mutableCopy];
    if (identifiers.count > 0) body[@"hitBreakpointIds"] = identifiers;
    [_connection sendEvent:@"stopped" body:body];
}

/// On, as if the game had not stopped (the step, if any, kept).
- (void)_goOnSilently {
    [self _forgetStop];
    [_game resume];
}

- (void)_endStep {
    for (NSNumber *identifier in _stepBreakpoints) [_game removeBreakpoint:identifier.intValue];
    [_stepBreakpoints removeAllObjects];
    _stepping = NO;
}

/// A step's temporary breakpoints, where a server whose steps other threads
/// end does not stop: the lines of the function stopped in (but the one it
/// is on), for step over and into, and the lines of the function under it,
/// where it returns to.
- (void)_addStepBreakpoints:(BOOL)inFunction {
    NSMutableArray<NSArray *> *spans = [NSMutableArray array];       // @[frame, skip its line]
    if (inFunction && _frames.count > 0) [spans addObject:@[_frames[0], @YES]];
    if (_frames.count > 1) [spans addObject:@[_frames[1], @NO]];
    for (NSArray *span in spans) {
        UDScriptStackFrame *frame = span[0];
        NSString *text = [self _textOf:frame.path];
        if (text == nil) continue;
        NSRange lines = [UDScriptIndex linesOfFunctionAtLine:frame.line inText:text];
        if (lines.location == NSNotFound) continue;
        for (NSUInteger line = lines.location; line < NSMaxRange(lines); line++) {
            if ([span[1] boolValue] && (int)line == frame.line) continue;
            int identifier = _nextStepBreakpoint++;
            [_stepBreakpoints addObject:@(identifier)];
            [_game addBreakpointAtLine:(int)line path:frame.path identifier:identifier onceOnly:NO];
        }
    }
}

- (void)_go:(UDDAPRequest *)request {
    if (!_game.connected) {
        [request failWithMessage:@"The game is not connected"];
        return;
    }
    NSString *command = request.command;
    if ([command isEqualToString:@"pause"]) {
        _pauseAsked = YES;
        [_game breakNext];
        [request respondWithBody:nil];
        return;
    }
    if (!_stopped) {
        [request failWithMessage:@"The game is running"];
        return;
    }
    BOOL step = ![command isEqualToString:@"continue"];
    [self _endStep];
    if (step) {
        _stepping = YES;
        _stepThread = [self _currentThread];
    }
    if ([command isEqualToString:@"continue"]) {
        [_game resume];
    } else if ([self _engineSteps]) {
        if ([command isEqualToString:@"next"]) [_game stepOver];
        else if ([command isEqualToString:@"stepIn"]) [_game stepInto];
        else [_game stepOut];
    } else {
        // the stock server's steps end when any thread returns from its
        // last function: the adapter's own, a temporary breakpoint where the
        // step may end, a stop elsewhere gone on from
        [self _addStepBreakpoints:![command isEqualToString:@"stepOut"]];
        if ([command isEqualToString:@"stepIn"]) [_game stepInto];
        else [_game resume];
    }
    [self _forgetStop];
    [request respondWithBody:[command isEqualToString:@"continue"] ? @{ @"allThreadsContinued": @YES } : nil];
}

- (void)continueRequest:(UDDAPRequest *)request { [self _go:request]; }
- (void)next:(UDDAPRequest *)request { [self _go:request]; }
- (void)stepIn:(UDDAPRequest *)request { [self _go:request]; }
- (void)stepOut:(UDDAPRequest *)request { [self _go:request]; }
- (void)pause:(UDDAPRequest *)request { [self _go:request]; }

#pragma mark - Threads and frames

- (NSArray *)_describeThreads {
    NSMutableArray *threads = [NSMutableArray array];
    for (UDScriptThreadInfo *thread in _threads) {
        NSString *name = thread.name.length > 0 ? thread.name : [NSString stringWithFormat:@"thread %d", thread.number];
        [threads addObject:@{ @"id": @(thread.number), @"name": name }];
    }
    if (threads.count == 0) [threads addObject:@{ @"id": @([self _currentThread]), @"name": @"scripts" }];
    return threads;
}

- (void)threads:(UDDAPRequest *)request {
    if (_stopped && _threads == nil && _game.connected) {
        [_threadRequests addObject:request];
        return;
    }
    [request respondWithBody:@{ @"threads": [self _describeThreads] }];
}

- (void)debuggerConnection:(UDScriptDebuggerConnection *)connection didReceiveThreads:(NSArray<UDScriptThreadInfo *> *)threads {
    _threads = threads;
    if (_announceStop) {
        _announceStop = NO;
        [self _decideStop];
    }
    NSArray<UDDAPRequest *> *waiting = [_threadRequests copy];
    [_threadRequests removeAllObjects];
    for (UDDAPRequest *request in waiting) [request respondWithBody:@{ @"threads": [self _describeThreads] }];
}

- (void)stackTrace:(UDDAPRequest *)request {
    if (!_stopped) {
        [request respondWithBody:@{ @"stackFrames": @[], @"totalFrames": @0 }];
        return;
    }
    id thread = request.arguments[@"threadId"];
    if (thread != nil && _threads != nil && [thread intValue] != [self _currentThread]) {
        // only the stopped thread's frames can be read
        [request respondWithBody:@{ @"stackFrames": @[], @"totalFrames": @0 }];
        return;
    }
    if (_frames == nil) {
        [_stackRequests addObject:request];
        return;
    }
    [self _answerStackTrace:request];
}

- (void)debuggerConnection:(UDScriptDebuggerConnection *)connection didReceiveCallstack:(NSArray<UDScriptStackFrame *> *)frames {
    _frames = frames;
    NSArray<UDDAPRequest *> *waiting = [_stackRequests copy];
    [_stackRequests removeAllObjects];
    for (UDDAPRequest *request in waiting) [self _answerStackTrace:request];
}

/// A frame's function as the game writes it, "lamp::flicker(  )": the name.
static NSString *UDFunctionName(NSString *function) {
    NSRange parenthesis = [function rangeOfString:@"("];
    NSString *name = parenthesis.location != NSNotFound ? [function substringToIndex:parenthesis.location] : function;
    return [name stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
}

- (void)_answerStackTrace:(UDDAPRequest *)request {
    NSInteger start = MAX([request.arguments[@"startFrame"] integerValue], 0);
    NSInteger levels = [request.arguments[@"levels"] integerValue];
    NSMutableArray *frames = [NSMutableArray array];
    for (NSInteger i = start; i < (NSInteger)_frames.count && (levels <= 0 || i < start + levels); i++) {
        UDScriptStackFrame *frame = _frames[(NSUInteger)i];
        NSMutableDictionary *described = [@{ @"id": @(i + 1), @"name": UDFunctionName(frame.function),
                                             @"line": @(frame.line), @"column": @1 } mutableCopy];
        if (frame.path.length > 0 && ![frame.path isEqualToString:@"<UNKNOWN>"]) described[@"source"] = [self _sourceOf:frame.path];
        [frames addObject:described];
    }
    [request respondWithBody:@{ @"stackFrames": frames, @"totalFrames": @(_frames.count) }];
}

/// The interpreter's scope for frame @a index (0, the function stopped in):
/// -1, then the call stack's from the top (MSG_WriteInterpreterInfo wrote it
/// from callStackDepth - 1 down).
- (int)_scopeDepthOfFrame:(NSInteger)index {
    return index == 0 ? -1 : (int)((NSInteger)_frames.count - index);
}

#pragma mark - Variables

/// The object frame @a index's function is a method of ("weapon_shotgun"
/// for weapon_shotgun::fire); nil for a function, or one of a namespace.
- (NSString *)_objectOfFrame:(NSInteger)index {
    if (index < 0 || index >= (NSInteger)_frames.count) return nil;
    UDScriptStackFrame *frame = _frames[(NSUInteger)index];
    NSString *function = UDFunctionName(frame.function);
    NSRange scope = [function rangeOfString:@"::" options:NSBackwardsSearch];
    if (scope.location == NSNotFound) return nil;
    NSString *owner = [function substringToIndex:scope.location];
    for (UDScriptDefinition *definition in [UDScriptIndex definitionsInText:[self _textOf:frame.path] ?: @"" path:frame.path]) {
        if (definition.kind == UDScriptDefinitionNamespace && [definition.qualifiedName isEqualToString:owner]) return nil;
    }
    return owner;
}

/// Its scopes: Locals (its parameters and locals), and for a method Fields
/// (its object's, and its superclasses'). A scope's reference: the frame's
/// twice, and one or two.
- (void)scopes:(UDDAPRequest *)request {
    NSInteger frame = [request.arguments[@"frameId"] integerValue] - 1;
    if (!_stopped || frame < 0 || frame >= (NSInteger)_frames.count) {
        [request respondWithBody:@{ @"scopes": @[] }];
        return;
    }
    NSMutableArray *scopes = [NSMutableArray arrayWithObject:@{ @"name": @"Locals", @"presentationHint": @"locals",
                                                                @"variablesReference": @(frame * 2 + 1), @"expensive": @NO }];
    if ([self _objectOfFrame:frame] != nil) {
        [scopes addObject:@{ @"name": @"Fields", @"variablesReference": @(frame * 2 + 2), @"expensive": @NO }];
    }
    [request respondWithBody:@{ @"scopes": scopes }];
}

/// The fields of @a object and its superclasses, the object's first, as the
/// loaded scripts declare them.
- (NSArray<NSString *> *)_fieldsOfObject:(NSString *)object {
    if (_objectIndex == nil) {
        _objectIndex = [[UDScriptIndex alloc] init];
        for (NSString *path in _loadedScripts ?: @[]) {
            NSString *text = [self _textOf:path];
            if (text != nil) [_objectIndex setText:text forPath:path];
        }
    }
    NSMutableOrderedSet<NSString *> *fields = [NSMutableOrderedSet orderedSet];
    NSMutableSet<NSString *> *seen = [NSMutableSet set];
    for (NSString *name = object; name != nil && ![seen containsObject:name]; ) {
        [seen addObject:name];
        NSString *superclass = nil;
        for (UDScriptDefinition *definition in [_objectIndex definitionsOfName:name]) {
            if (definition.kind == UDScriptDefinitionObject) superclass = definition.superclassName;
        }
        NSString *prefix = [name stringByAppendingString:@"::"];
        for (UDScriptDefinition *definition in _objectIndex.allDefinitions) {
            if (definition.kind == UDScriptDefinitionField && [definition.qualifiedName hasPrefix:prefix]) [fields addObject:definition.name];
        }
        name = superclass;
    }
    return fields.array;
}

- (void)variables:(UDDAPRequest *)request {
    NSInteger reference = [request.arguments[@"variablesReference"] integerValue] - 1;
    NSInteger frame = reference / 2;
    BOOL fields = reference % 2 == 1;
    if (!_stopped || reference < 0 || frame >= (NSInteger)_frames.count) {
        [request respondWithBody:@{ @"variables": @[] }];
        return;
    }
    int depth = [self _scopeDepthOfFrame:frame];
    // a server that lists them: its list
    if (_engineCapabilities & UDScriptDebuggerCapabilityInspectVariables) {
        BOOL asked = NO;
        for (NSArray *waiting in _listRequests) asked = asked || [waiting[1] intValue] == depth;
        [_listRequests addObject:@[request, @(depth), @(fields)]];
        if (!asked) [_game inspectVariablesAtScopeDepth:depth];
        return;
    }
    // else the names the script has, each asked of the game; frame 0 is
    // where it stopped, under it each line is the call's
    UDScriptStackFrame *at = _frames[(NSUInteger)frame];
    NSArray<NSString *> *names = nil;
    if (fields) {
        NSString *object = [self _objectOfFrame:frame];
        names = object != nil ? [self _fieldsOfObject:object] : nil;
    } else {
        NSString *text = [self _textOf:at.path];
        names = text != nil ? [UDScriptIndex variablesOfFunctionAtLine:at.line inText:text] : nil;
    }
    if (names.count == 0) {
        [request respondWithBody:@{ @"variables": @[] }];
        return;
    }
    UDScriptVariablesQuery *query = [[UDScriptVariablesQuery alloc] init];
    query.request = request;
    query.scopeDepth = depth;
    query.names = names;
    query.values = [NSMutableDictionary dictionary];
    [_variableQueries addObject:query];
    for (NSString *name in names) [_game inspectVariable:name scopeDepth:query.scopeDepth];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, UDGameAnswerTimeout), _queue, ^{
        [self _answerVariables:query];
    });
}

- (void)debuggerConnection:(UDScriptDebuggerConnection *)connection didReceiveVariables:(NSArray<UDScriptVariableInfo *> *)variables
                scopeDepth:(int)scopeDepth {
    for (NSArray *waiting in [_listRequests copy]) {
        if ([waiting[1] intValue] != scopeDepth) continue;
        [_listRequests removeObject:waiting];
        BOOL fields = [waiting[2] boolValue];
        NSMutableArray *answer = [NSMutableArray array];
        for (UDScriptVariableInfo *variable in variables) {
            if (variable.field != fields) continue;
            [answer addObject:@{ @"name": variable.name, @"value": variable.value, @"variablesReference": @0 }];
        }
        [(UDDAPRequest *)waiting[0] respondWithBody:@{ @"variables": answer }];
    }
}

- (void)debuggerConnection:(UDScriptDebuggerConnection *)connection didReceiveValue:(NSString *)value
                  variable:(NSString *)name scopeDepth:(int)scopeDepth {
    UDScriptConditionQuery *condition = _conditionQuery;
    if (condition != nil && scopeDepth == -1 && [condition.names containsObject:name] && condition.values[name] == nil) {
        condition.values[name] = value;
        if (condition.values.count == condition.names.count) [self _decideBreakpoints:condition];
        return;
    }
    for (UDScriptVariablesQuery *query in [_variableQueries copy]) {
        if (query.scopeDepth != scopeDepth || ![query.names containsObject:name] || query.values[name] != nil) continue;
        query.values[name] = value;
        if (query.values.count == query.names.count) [self _answerVariables:query];
        break;
    }
}

- (void)_answerVariables:(UDScriptVariablesQuery *)query {
    if (query.request.answered) return;
    [_variableQueries removeObject:query];
    NSMutableArray *variables = [NSMutableArray array];
    for (NSString *name in query.names) {
        NSString *value = query.values[name] ?: @"???";
        if ([query.request.command isEqualToString:@"evaluate"]) {
            if ([value isEqualToString:@"???"] && ![query.request.arguments[@"context"] isEqual:@"watch"]) {
                [query.request failWithMessage:[NSString stringWithFormat:@"%@ is not a variable here", name]];
            } else {
                [query.request respondWithBody:@{ @"result": value, @"variablesReference": @0 }];
            }
            return;
        }
        [variables addObject:@{ @"name": name, @"value": value, @"variablesReference": @0 }];
    }
    [query.request respondWithBody:@{ @"variables": variables }];
}

/// What can be a variable's name: idScript's names, and an object's field
/// ("$player1.health" is not).
static BOOL UDIsVariableName(NSString *text) {
    if (text.length == 0) return NO;
    NSCharacterSet *letters = [NSCharacterSet characterSetWithCharactersInString:
                               @"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ_"];
    NSCharacterSet *nameCharacters = [NSCharacterSet characterSetWithCharactersInString:
                                      @"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ_0123456789"];
    if (![letters characterIsMember:[text characterAtIndex:0]]) return NO;
    return [text rangeOfCharacterFromSet:nameCharacters.invertedSet].location == NSNotFound;
}

/// Whether the game can be asked for @a name in frame @a index. In a
/// namespace's function, idInterpreter::GetRegisterValue looks a name it
/// does not find up the namespace's superclasses, and a namespace has
/// none: idTypeDef::SuperClass throws, and the game aborts. There, only the
/// function's own variables are asked for; elsewhere (a function, an
/// object's method, whose fields it looks up) anything.
- (BOOL)_canInspect:(NSString *)name inFrame:(NSInteger)index {
    if (index < 0 || index >= (NSInteger)_frames.count) return NO;
    if (_engineVersion >= 2) return YES;
    UDScriptStackFrame *frame = _frames[(NSUInteger)index];
    NSString *function = UDFunctionName(frame.function);
    NSRange scope = [function rangeOfString:@"::" options:NSBackwardsSearch];
    NSString *text = [self _textOf:frame.path];
    if ([[UDScriptIndex variablesOfFunctionAtLine:frame.line inText:text ?: @""] containsObject:name]) return YES;
    if (scope.location == NSNotFound) return YES;
    // the scope an object, not a namespace
    NSString *owner = [function substringToIndex:scope.location];
    for (UDScriptDefinition *definition in [UDScriptIndex definitionsInText:text ?: @"" path:frame.path]) {
        if (definition.kind == UDScriptDefinitionNamespace && [definition.qualifiedName isEqualToString:owner]) return NO;
    }
    return text != nil;
}

- (void)evaluate:(UDDAPRequest *)request {
    NSString *expression = [request.arguments[@"expression"] isKindOfClass:[NSString class]] ? request.arguments[@"expression"] : @"";
    expression = [expression stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSString *context = request.arguments[@"context"];
    BOOL console = [context isEqual:@"repl"];
    BOOL command = [expression hasPrefix:@"/"] || [expression hasPrefix:@"\\"];
    if (console && (command || !_stopped || !UDIsVariableName(expression))) {
        if (!_game.connected) {
            [request failWithMessage:@"The game is not connected"];
            return;
        }
        [_game executeCommand:command ? [expression substringFromIndex:1] : expression];
        [request respondWithBody:@{ @"result": @"", @"variablesReference": @0 }];
        return;
    }
    if (!_stopped || !UDIsVariableName(expression)) {
        [request failWithMessage:_stopped ? @"Only a variable's name can be read" : @"The game is running"];
        return;
    }
    NSInteger frame = request.arguments[@"frameId"] ? [request.arguments[@"frameId"] integerValue] - 1 : 0;
    if (![self _canInspect:expression inFrame:frame]) {
        [request failWithMessage:[NSString stringWithFormat:@"%@ is not a variable here", expression]];
        return;
    }
    UDScriptVariablesQuery *query = [[UDScriptVariablesQuery alloc] init];
    query.request = request;
    query.scopeDepth = (frame >= 0 && frame < (NSInteger)_frames.count) ? [self _scopeDepthOfFrame:frame] : -1;
    query.names = @[expression];
    query.values = [NSMutableDictionary dictionary];
    [_variableQueries addObject:query];
    [_game inspectVariable:expression scopeDepth:query.scopeDepth];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, UDGameAnswerTimeout), _queue, ^{
        [self _answerVariables:query];
    });
}

#pragma mark - Sources

- (void)source:(UDDAPRequest *)request {
    NSInteger reference = [request.arguments[@"sourceReference"] integerValue];
    NSDictionary *source = request.arguments[@"source"];
    if (reference == 0 && [source isKindOfClass:[NSDictionary class]]) reference = [source[@"sourceReference"] integerValue];
    NSString *text = nil;
    if (reference >= 1 && reference <= (NSInteger)_sourceReferences.count) text = [self _textOf:_sourceReferences[(NSUInteger)reference - 1]];
    if (text == nil) {
        [request failWithMessage:@"No such script"];
        return;
    }
    [request respondWithBody:@{ @"content": text }];
}

- (void)loadedSources:(UDDAPRequest *)request {
    if (_loadedScripts == nil && _game.connected) {
        [_scriptRequests addObject:request];
        [_game inspectScripts];
        return;
    }
    [self _answerLoadedSources:request];
}

- (void)_answerLoadedSources:(UDDAPRequest *)request {
    NSMutableArray *sources = [NSMutableArray array];
    for (NSString *path in _loadedScripts ?: @[]) [sources addObject:[self _sourceOf:path]];
    [request respondWithBody:@{ @"sources": sources }];
}

@end
