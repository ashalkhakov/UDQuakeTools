//
//  UDScriptDebugAdapter.m
//  udscript-dap
//

#import "UDScriptDebugAdapter.h"
#import "UDScriptIndex.h"
#import "UDWorkspace.h"
#import "idFileSystem.h"

/// A breakpoint as the client set it, and as the game has it.
@interface UDScriptBreakpoint : NSObject
@property (nonatomic) int identifier;
@property (nonatomic) int line;
@property (nonatomic) BOOL verified;
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
    NSString *_pendingReason;                    // a step or pause asked for
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
             @[@"next", @"next:"], @[@"stepIn", @"stepIn:"], @[@"pause", @"pause:"], @[@"source", @"source:"],
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
        // the game's answer, if it is connected: none is yes
        breakpoint.verified = _game.connected;
        [set addObject:breakpoint];
        if (_game.connected) [_game addBreakpointAtLine:breakpoint.line path:gamePath identifier:breakpoint.identifier onceOnly:NO];
        [answered addObject:[self _describe:breakpoint path:gamePath message:nil]];
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

- (void)debuggerConnection:(UDScriptDebuggerConnection *)connection didBreakAtLine:(int)line path:(NSString *)path {
    _stopped = YES;
    _stopLine = line;
    _stopPath = [path copy];
    _stopReason = _pendingReason ?: @"breakpoint";
    _pendingReason = nil;
    _frames = nil;
    _threads = nil;
    [_variableQueries removeAllObjects];
    // stopped in which thread: the threads' answer says, then the client is told
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
    [_variableQueries removeAllObjects];
}

- (int)_currentThread {
    for (UDScriptThreadInfo *thread in _threads) {
        if (thread.current) return thread.number;
    }
    return 1;
}

- (NSArray<NSNumber *> *)_breakpointsAtStop {
    NSMutableArray *hit = [NSMutableArray array];
    for (NSString *gamePath in _breakpoints) {
        if ([gamePath caseInsensitiveCompare:_stopPath] != NSOrderedSame) continue;
        for (UDScriptBreakpoint *breakpoint in _breakpoints[gamePath]) {
            if (breakpoint.line == _stopLine) [hit addObject:@(breakpoint.identifier)];
        }
    }
    return hit;
}

- (void)_go:(UDDAPRequest *)request reason:(NSString *)reason {
    if (!_game.connected) {
        [request failWithMessage:@"The game is not connected"];
        return;
    }
    _pendingReason = reason;
    if ([request.command isEqualToString:@"pause"]) {
        [_game breakNext];
        [request respondWithBody:nil];
        return;
    }
    if (!_stopped) {
        [request failWithMessage:@"The game is running"];
        return;
    }
    if ([request.command isEqualToString:@"next"]) [_game stepOver];
    else if ([request.command isEqualToString:@"stepIn"]) [_game stepInto];
    else [_game resume];
    [self _forgetStop];
    [request respondWithBody:[request.command isEqualToString:@"continue"] ? @{ @"allThreadsContinued": @YES } : nil];
}

- (void)continueRequest:(UDDAPRequest *)request { [self _go:request reason:nil]; }
- (void)next:(UDDAPRequest *)request { [self _go:request reason:@"step"]; }
- (void)stepIn:(UDDAPRequest *)request { [self _go:request reason:@"step"]; }
- (void)pause:(UDDAPRequest *)request { [self _go:request reason:@"pause"]; }

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
        NSMutableDictionary *body = [@{ @"reason": _stopReason ?: @"breakpoint", @"threadId": @([self _currentThread]),
                                        @"allThreadsStopped": @YES } mutableCopy];
        if ([_stopReason isEqualToString:@"breakpoint"]) body[@"hitBreakpointIds"] = [self _breakpointsAtStop];
        [_connection sendEvent:@"stopped" body:body];
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

- (void)scopes:(UDDAPRequest *)request {
    NSInteger frame = [request.arguments[@"frameId"] integerValue] - 1;
    if (!_stopped || frame < 0 || frame >= (NSInteger)_frames.count) {
        [request respondWithBody:@{ @"scopes": @[] }];
        return;
    }
    [request respondWithBody:@{ @"scopes": @[ @{ @"name": @"Locals", @"presentationHint": @"locals",
                                                @"variablesReference": @(frame + 1), @"expensive": @NO } ] }];
}

- (void)variables:(UDDAPRequest *)request {
    NSInteger frame = [request.arguments[@"variablesReference"] integerValue] - 1;
    if (!_stopped || frame < 0 || frame >= (NSInteger)_frames.count) {
        [request respondWithBody:@{ @"variables": @[] }];
        return;
    }
    // frame 0 is where it stopped; under it, each line is the call's
    UDScriptStackFrame *at = _frames[(NSUInteger)frame];
    NSString *text = [self _textOf:at.path];
    NSArray<NSString *> *names = text != nil ? [UDScriptIndex variablesOfFunctionAtLine:at.line inText:text] : nil;
    if (names.count == 0) {
        [request respondWithBody:@{ @"variables": @[] }];
        return;
    }
    UDScriptVariablesQuery *query = [[UDScriptVariablesQuery alloc] init];
    query.request = request;
    query.scopeDepth = [self _scopeDepthOfFrame:frame];
    query.names = names;
    query.values = [NSMutableDictionary dictionary];
    [_variableQueries addObject:query];
    for (NSString *name in names) [_game inspectVariable:name scopeDepth:query.scopeDepth];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, UDGameAnswerTimeout), _queue, ^{
        [self _answerVariables:query];
    });
}

- (void)debuggerConnection:(UDScriptDebuggerConnection *)connection didReceiveValue:(NSString *)value
                  variable:(NSString *)name scopeDepth:(int)scopeDepth {
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
