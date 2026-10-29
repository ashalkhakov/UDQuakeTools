//
//  UDScriptDebugAdapter.m
//  udscript-dap
//

#import "UDScriptDebugAdapter.h"
#import "UDScriptIndex.h"
#import "UDScriptExpression.h"
#import "UDWorkspace.h"
#import "idFileSystem.h"
#import "UDKillTask.h"

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
/// A method's self: its fields' reference, and its object's name.
@property (nonatomic) NSInteger selfReference;
@property (nonatomic, copy, nullable) NSString *selfObject;
/// An evaluate's: the expression the values are for.
@property (nonatomic, strong, nullable) UDScriptExpression *expression;
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

/// Other threads' frames' identifiers start here (their variables cannot
/// be read: the game reads the stopped thread's), entities' variables'
/// references here.
static const NSInteger UDOtherFrameBase = 1 << 24;
static const NSInteger UDEntityReferenceBase = 1 << 20;
/// Other threads' frames' variables' references: their frame's (its place
/// in _otherFrames) twice, and one (its locals) or two (its self's fields).
static const NSInteger UDOtherReferenceBase = 1 << 22;

static NSString *UDFunctionName(NSString *function);

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
    UDScriptIndex *_objectIndex;                 // the loaded scripts' objects, for their fields

    // a newer server's (its capabilities say): which of the scripts' errors
    // stop it, the error a stop is at; other threads' frames; entities
    // opened (@[name, spawn args or not], by reference - base), what the
    // game said of them, the requests waiting; a set and a goto waiting
    UDScriptDebuggerErrorFlags _errorFlags;
    NSString *_scriptError;
    BOOL _scriptErrorIsError;
    NSString *_stopDescription;
    NSMutableDictionary<NSNumber *, NSArray<UDScriptStackFrame *> *> *_threadFrames;
    NSMutableArray<NSArray *> *_threadStackRequests;     // @[request, thread]
    NSMutableArray<NSArray *> *_otherFrames;             // @[thread, index], by frame id - base
    NSMutableArray<NSArray *> *_entityReferences;
    NSMutableDictionary<NSString *, NSArray<UDScriptVariableInfo *> *> *_entities;
    NSMutableArray<NSArray *> *_entityRequests;          // @[request, reference]
    NSMutableDictionary<NSNumber *, NSString *> *_selfEntities;   // a self's entity, by its fields' reference
    // other threads' frames' variables (by @[thread, depth]), and the
    // requests waiting on them: @[key, request]
    NSMutableDictionary<NSArray *, NSArray<UDScriptVariableInfo *> *> *_threadVariables;
    NSMutableArray<NSArray *> *_threadVariableRequests;
    NSMutableArray<UDDAPRequest *> *_setRequests;
    UDDAPRequest *_gotoRequest;
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
             @[@"source", @"source:"], @[@"setExceptionBreakpoints", @"setExceptionBreakpoints:"],
             @[@"setVariable", @"setVariable:"], @[@"gotoTargets", @"gotoTargets:"], @[@"goto", @"gotoRequest:"],
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
    _threadFrames = [NSMutableDictionary dictionary];
    _threadStackRequests = [NSMutableArray array];
    _otherFrames = [NSMutableArray array];
    _entityReferences = [NSMutableArray array];
    _entities = [NSMutableDictionary dictionary];
    _entityRequests = [NSMutableArray array];
    _selfEntities = [NSMutableDictionary dictionary];
    _threadVariables = [NSMutableDictionary dictionary];
    _threadVariableRequests = [NSMutableArray array];
    _setRequests = [NSMutableArray array];
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
        // a newer dhewm3's (its capabilities say; stock 1.5.5 refuses them)
        @"supportsSetVariable": @YES,
        @"supportsGotoTargetsRequest": @YES,
        @"exceptionBreakpointFilters": @[
            @{ @"filter": @"errors", @"label": @"Script Errors", @"default": @YES,
               @"description": @"Stop where a script errs, before the game drops the map" },
            @{ @"filter": @"warnings", @"label": @"Script Warnings", @"default": @NO,
               @"description": @"Stop where a script warns" },
        ],
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
    // its process, which a client brings forward as it runs
    [_connection sendEvent:@"process" body:@{ @"name": program.lastPathComponent, @"systemProcessId": @(task.processIdentifier),
                                              @"isLocalProcess": @YES, @"startMethod": @"launch" }];
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
    [_game close];
    if (_task != nil && (terminate == nil || [terminate boolValue])) {
        NSTask *task = _task;
        _task = nil;
        [task terminate];
        // answered once it is gone, its debugger's port free (a restart
        // starts another at once)
        [self _respond:request whenGone:task tries:30];
        return;
    }
    [request respondWithBody:nil];
}

/// @a request answered when @a task has exited, looked at every tenth of a
/// second; after @a tries, killed.
- (void)_respond:(UDDAPRequest *)request whenGone:(NSTask *)task tries:(int)tries {
    if ([task isRunning] && tries == 0) UDKillTask(task);
    if (![task isRunning] || tries == 0) {
        [request respondWithBody:nil];
        return;
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC / 10), _queue, ^{
        [self _respond:request whenGone:task tries:tries - 1];
    });
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
    if (capabilities & UDScriptDebuggerCapabilityBreakOnErrors) [_game setBreakOnErrors:_errorFlags];
}

/// Which of the scripts' errors and warnings stop the game (DAP's exception
/// filters); the game told when it can be (a newer one's capability).
- (void)setExceptionBreakpoints:(UDDAPRequest *)request {
    NSArray *filters = [request.arguments[@"filters"] isKindOfClass:[NSArray class]] ? request.arguments[@"filters"] : @[];
    _errorFlags = 0;
    if ([filters containsObject:@"errors"]) _errorFlags |= UDScriptDebuggerBreakOnScriptErrors;
    if ([filters containsObject:@"warnings"]) _errorFlags |= UDScriptDebuggerBreakOnScriptWarnings;
    BOOL can = (_engineCapabilities & UDScriptDebuggerCapabilityBreakOnErrors) != 0;
    if (_game.connected && can) [_game setBreakOnErrors:_errorFlags];
    NSMutableArray *answered = [NSMutableArray array];
    for (NSUInteger i = 0; i < filters.count; i++) {
        NSMutableDictionary *breakpoint = [@{ @"verified": @(can || !_game.connected) } mutableCopy];
        if (_game.connected && !can) breakpoint[@"message"] = @"This dhewm3 does not stop at script errors";
        [answered addObject:breakpoint];
    }
    [request respondWithBody:@{ @"breakpoints": answered }];
}

/// A stop at a script error: the break that follows says where.
- (void)debuggerConnection:(UDScriptDebuggerConnection *)connection didStopAtScriptError:(NSString *)message isError:(BOOL)isError {
    _scriptError = [message copy];
    _scriptErrorIsError = isError;
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
    _stopDescription = nil;
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
    [_threadFrames removeAllObjects];
    [_otherFrames removeAllObjects];
    [_entityReferences removeAllObjects];
    [_entities removeAllObjects];
    [_selfEntities removeAllObjects];
    [_threadVariables removeAllObjects];
    [_threadVariableRequests removeAllObjects];
    _scriptError = nil;
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
    if (_scriptError != nil) {
        _stopDescription = [NSString stringWithFormat:@"%@: %@", _scriptErrorIsError ? @"Script error" : @"Script warning", _scriptError];
        _scriptError = nil;
        [self _announceStop:@"exception" breakpoints:@[]];
        return;
    }
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
    if (_stopDescription != nil) {
        body[@"description"] = _stopDescription;
        body[@"text"] = _stopDescription;
    }
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
        // what it is doing, as Xcode's thread list says
        if (thread.dying) name = [name stringByAppendingString:@" (ending)"];
        else if (thread.waiting) name = [name stringByAppendingString:@" (waiting)"];
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
        // another thread's: a newer server's, else none
        if (!(_engineCapabilities & UDScriptDebuggerCapabilityInspect)) {
            [request respondWithBody:@{ @"stackFrames": @[], @"totalFrames": @0 }];
            return;
        }
        NSNumber *number = @([thread intValue]);
        if (_threadFrames[number] != nil) {
            [self _answerStackTrace:request ofThread:number];
            return;
        }
        BOOL asked = NO;
        for (NSArray *waiting in _threadStackRequests) asked = asked || [waiting[1] isEqual:number];
        [_threadStackRequests addObject:@[request, number]];
        if (!asked) [_game inspectCallstackOfThread:number.intValue];
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

- (void)debuggerConnection:(UDScriptDebuggerConnection *)connection didReceiveCallstack:(NSArray<UDScriptStackFrame *> *)frames
                    thread:(int)number {
    if (!_stopped) return;
    _threadFrames[@(number)] = frames;
    for (NSArray *waiting in [_threadStackRequests copy]) {
        if (![waiting[1] isEqual:@(number)]) continue;
        [_threadStackRequests removeObject:waiting];
        [self _answerStackTrace:waiting[0] ofThread:@(number)];
    }
}

/// Another thread's frames: their identifiers the adapter's (their
/// variables cannot be read).
- (void)_answerStackTrace:(UDDAPRequest *)request ofThread:(NSNumber *)number {
    NSArray<UDScriptStackFrame *> *frames = _threadFrames[number];
    NSMutableArray *described = [NSMutableArray array];
    for (NSUInteger i = 0; i < frames.count; i++) {
        UDScriptStackFrame *frame = frames[i];
        NSArray *key = @[number, @(i)];
        NSUInteger index = [_otherFrames indexOfObject:key];
        if (index == NSNotFound) {
            [_otherFrames addObject:key];
            index = _otherFrames.count - 1;
        }
        NSMutableDictionary *entry = [@{ @"id": @(UDOtherFrameBase + (NSInteger)index), @"name": UDFunctionName(frame.function),
                                         @"line": @(frame.line), @"column": @1 } mutableCopy];
        if (frame.path.length > 0 && ![frame.path isEqualToString:@"<UNKNOWN>"]) entry[@"source"] = [self _sourceOf:frame.path];
        [described addObject:entry];
    }
    [request respondWithBody:@{ @"stackFrames": described, @"totalFrames": @(frames.count) }];
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
    return [self _objectOfStackFrame:_frames[(NSUInteger)index]];
}

- (NSString *)_objectOfStackFrame:(UDScriptStackFrame *)frame {
    NSString *function = UDFunctionName(frame.function);
    NSRange scope = [function rangeOfString:@"::" options:NSBackwardsSearch];
    if (scope.location == NSNotFound) return nil;
    NSString *owner = [function substringToIndex:scope.location];
    for (UDScriptDefinition *definition in [UDScriptIndex definitionsInText:[self _textOf:frame.path] ?: @"" path:frame.path]) {
        if (definition.kind == UDScriptDefinitionNamespace && [definition.qualifiedName isEqualToString:owner]) return nil;
    }
    return owner;
}

/// Its scope: Locals (its parameters and locals), a method's self first,
/// which opens to its fields (its object's, and its superclasses'), as VS
/// Code shows a method's this. A reference: the frame's twice, and one
/// (its locals) or two (its self's fields).
- (void)scopes:(UDDAPRequest *)request {
    NSInteger frame = [request.arguments[@"frameId"] integerValue] - 1;
    // another thread's frame: its Locals, when the game reads them (a newer one)
    NSInteger place = frame + 1 - UDOtherFrameBase;
    if (_stopped && place >= 0 && place < (NSInteger)_otherFrames.count) {
        BOOL can = (_engineCapabilities & UDScriptDebuggerCapabilityInspect) != 0;
        [request respondWithBody:@{ @"scopes": can ? @[ @{ @"name": @"Locals", @"presentationHint": @"locals",
                                                          @"variablesReference": @(UDOtherReferenceBase + place * 2 + 1),
                                                          @"expensive": @NO } ] : @[] }];
        return;
    }
    if (!_stopped || frame < 0 || frame >= (NSInteger)_frames.count) {
        [request respondWithBody:@{ @"scopes": @[] }];
        return;
    }
    [request respondWithBody:@{ @"scopes": @[ @{ @"name": @"Locals", @"presentationHint": @"locals",
                                                 @"variablesReference": @(frame * 2 + 1), @"expensive": @NO } ] }];
}

/// A variable's description; self, a method's, opening to its fields.
- (NSDictionary *)_describeVariable:(NSString *)name value:(NSString *)value selfReference:(NSInteger)reference object:(NSString *)object {
    if (reference > 0 && [name isEqualToString:@"self"]) {
        // the stock game cannot print an object: its type, then
        NSString *shown = [value isEqualToString:@"???"] || value.length == 0 ? object : [NSString stringWithFormat:@"%@ (%@)", value, object];
        // its entity's spawn args, under its fields
        if ([self _isEntity:value]) _selfEntities[@(reference)] = value;
        return @{ @"name": name, @"value": shown, @"type": object, @"variablesReference": @(reference) };
    }
    // an entity opens to its script object's fields and its spawn args (a newer server's)
    if ([self _isEntity:value]) {
        return @{ @"name": name, @"value": value, @"type": @"entity",
                  @"variablesReference": @([self _referenceOfEntity:value spawnArgs:NO]) };
    }
    return @{ @"name": name, @"value": value, @"variablesReference": @0 };
}

- (BOOL)_isEntity:(NSString *)value {
    return (_engineCapabilities & UDScriptDebuggerCapabilityInspect) && [value hasPrefix:@"$"]
        && ![value isEqualToString:@"$null_entity"] && value.length > 1;
}

- (NSInteger)_referenceOfEntity:(NSString *)entity spawnArgs:(BOOL)spawnArgs {
    NSArray *key = @[entity, @(spawnArgs)];
    NSUInteger index = [_entityReferences indexOfObject:key];
    if (index == NSNotFound) {
        [_entityReferences addObject:key];
        index = _entityReferences.count - 1;
    }
    return UDEntityReferenceBase + (NSInteger)index;
}

/// An entity's variables: its script object's fields, then its spawn args
/// (a child); or its spawn args, as their strings.
- (void)_variablesOfEntity:(UDDAPRequest *)request reference:(NSInteger)reference {
    NSArray *key = _entityReferences[(NSUInteger)(reference - UDEntityReferenceBase)];
    NSString *entity = key[0];
    if (_entities[entity] == nil) {
        BOOL asked = NO;
        for (NSArray *waiting in _entityRequests) {
            asked = asked || [_entityReferences[(NSUInteger)([waiting[1] integerValue] - UDEntityReferenceBase)][0] isEqual:entity];
        }
        [_entityRequests addObject:@[request, @(reference)]];
        if (!asked) [_game inspectEntity:entity];
        return;
    }
    BOOL spawnArgs = [key[1] boolValue];
    NSMutableArray *variables = [NSMutableArray array];
    for (UDScriptVariableInfo *variable in _entities[entity]) {
        if (spawnArgs != (variable.kind == UDScriptVariableSpawnArg)) continue;
        if (spawnArgs) {
            [variables addObject:@{ @"name": variable.name, @"value": [NSString stringWithFormat:@"\"%@\"", variable.value],
                                    @"variablesReference": @0 }];
        } else {
            [variables addObject:[self _describeVariable:variable.name value:variable.value selfReference:0 object:nil]];
        }
    }
    if (!spawnArgs) [variables addObject:[self _spawnArgsOf:entity]];
    [request respondWithBody:@{ @"variables": variables }];
}

- (NSDictionary *)_spawnArgsOf:(NSString *)entity {
    return @{ @"name": @"spawnArgs", @"value": @"{…}", @"presentationHint": @{ @"kind": @"virtual" },
              @"variablesReference": @([self _referenceOfEntity:entity spawnArgs:YES]) };
}

- (void)debuggerConnection:(UDScriptDebuggerConnection *)connection didReceiveEntity:(NSString *)name
                 variables:(NSArray<UDScriptVariableInfo *> *)variables {
    if (!_stopped) return;
    _entities[name] = variables;
    for (NSArray *waiting in [_entityRequests copy]) {
        NSInteger reference = [waiting[1] integerValue];
        if (![_entityReferences[(NSUInteger)(reference - UDEntityReferenceBase)][0] isEqual:name]) continue;
        [_entityRequests removeObject:waiting];
        [self _variablesOfEntity:waiting[0] reference:reference];
    }
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
    NSInteger asked = [request.arguments[@"variablesReference"] integerValue];
    if (_stopped && asked >= UDOtherReferenceBase && (asked - UDOtherReferenceBase - 1) / 2 < (NSInteger)_otherFrames.count) {
        [self _whenListedOtherFrame:(asked - UDOtherReferenceBase - 1) / 2 answer:request];
        return;
    }
    if (_stopped && asked >= UDEntityReferenceBase && asked - UDEntityReferenceBase < (NSInteger)_entityReferences.count) {
        [self _variablesOfEntity:request reference:asked];
        return;
    }
    NSInteger reference = asked - 1;
    NSInteger frame = reference / 2;
    BOOL fields = reference % 2 == 1;
    if (!_stopped || reference < 0 || frame >= (NSInteger)_frames.count) {
        [request respondWithBody:@{ @"variables": @[] }];
        return;
    }
    int depth = [self _scopeDepthOfFrame:frame];
    // a server that lists them: its list
    if (_engineCapabilities & UDScriptDebuggerCapabilityInspect) {
        [self _whenListed:@[@([self _currentThread]), @(depth)] answer:request fieldsReference:frame * 2 + 2
                   object:[self _objectOfFrame:frame] ?: @""];
        return;
    }
    // else the names the script has, each asked of the game; frame 0 is
    // where it stopped, under it each line is the call's
    UDScriptStackFrame *at = _frames[(NSUInteger)frame];
    NSString *object = [self _objectOfFrame:frame];
    NSArray<NSString *> *names = nil;
    if (fields) {
        names = object != nil ? [self _fieldsOfObject:object] : nil;
    } else {
        NSString *text = [self _textOf:at.path];
        names = text != nil ? [UDScriptIndex variablesOfFunctionAtLine:at.line inText:text] : nil;
        // a method's self, which the script does not declare
        if (object != nil) names = [@[@"self"] arrayByAddingObjectsFromArray:names ?: @[]];
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
    if (!fields && object != nil) {
        query.selfReference = frame * 2 + 2;
        query.selfObject = object;
    }
    [_variableQueries addObject:query];
    for (NSString *name in names) [_game inspectVariable:name scopeDepth:query.scopeDepth];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, UDGameAnswerTimeout), _queue, ^{
        [self _answerVariables:query];
    });
}

/// A frame's listed variables: its locals (a method's self opening to its
/// fields, at @a fieldsReference), or its self's fields (and its entity's
/// spawn args).
- (void)_answer:(UDDAPRequest *)request variables:(NSArray<UDScriptVariableInfo *> *)variables fields:(BOOL)fields
fieldsReference:(NSInteger)fieldsReference object:(NSString *)object {
    NSMutableArray *answer = [NSMutableArray array];
    NSInteger reference = object.length > 0 && !fields ? fieldsReference : 0;
    for (UDScriptVariableInfo *variable in variables) {
        if (variable.field != fields) continue;
        [answer addObject:[self _describeVariable:variable.name value:variable.value selfReference:reference object:object]];
    }
    NSString *entity = fields ? _selfEntities[@(fieldsReference)] : nil;
    if (entity != nil) [answer addObject:[self _spawnArgsOf:entity]];
    [request respondWithBody:@{ @"variables": answer }];
}

#pragma mark - Other threads' variables

/// Another thread's frame (its place in _otherFrames): its thread, and its
/// scope depth in that thread's call stack.
- (NSArray *)_keyOfOtherFrame:(NSInteger)place {
    NSArray *frame = _otherFrames[(NSUInteger)place];
    NSInteger index = [frame[1] integerValue];
    NSInteger count = (NSInteger)_threadFrames[frame[0]].count;
    return @[frame[0], @(index == 0 ? -1 : count - index)];
}

- (UDScriptStackFrame *)_stackFrameOfOtherFrame:(NSInteger)place {
    NSArray *frame = _otherFrames[(NSUInteger)place];
    NSArray<UDScriptStackFrame *> *frames = _threadFrames[frame[0]];
    NSUInteger index = [frame[1] unsignedIntegerValue];
    return index < frames.count ? frames[index] : nil;
}

- (void)_whenListedOtherFrame:(NSInteger)place answer:(UDDAPRequest *)request {
    [self _whenListed:[self _keyOfOtherFrame:place] answer:request fieldsReference:UDOtherReferenceBase + place * 2 + 2
               object:[self _objectOfStackFrame:[self _stackFrameOfOtherFrame:place]] ?: @""];
}

#pragma mark - A thread's frame's variables, as the game lists them

/// @a request (variables or evaluate) answered once the game has listed the
/// variables of the frame @a key says (@[thread, scope depth]; the stopped
/// thread's or another's): its self's fields at @a fieldsReference, the
/// object its function is a method of @a object.
- (void)_whenListed:(NSArray *)key answer:(UDDAPRequest *)request fieldsReference:(NSInteger)fieldsReference
             object:(NSString *)object {
    if (_threadVariables[key] != nil) {
        [self _answer:request listed:_threadVariables[key] fieldsReference:fieldsReference object:object];
        return;
    }
    BOOL asked = NO;
    for (NSArray *waiting in _threadVariableRequests) asked = asked || [waiting[0] isEqual:key];
    [_threadVariableRequests addObject:@[key, request, @(fieldsReference), object]];
    if (!asked) [_game inspectVariablesOfThread:[key[0] intValue] scopeDepth:[key[1] intValue]];
}

- (void)debuggerConnection:(UDScriptDebuggerConnection *)connection didReceiveVariables:(NSArray<UDScriptVariableInfo *> *)variables
                scopeDepth:(int)scopeDepth thread:(int)number {
    if (!_stopped) return;
    NSArray *key = @[@(number), @(scopeDepth)];
    _threadVariables[key] = variables;
    for (NSArray *waiting in [_threadVariableRequests copy]) {
        if (![waiting[0] isEqual:key]) continue;
        [_threadVariableRequests removeObject:waiting];
        [self _answer:waiting[1] listed:variables fieldsReference:[waiting[2] integerValue] object:waiting[3]];
    }
}

- (void)_answer:(UDDAPRequest *)request listed:(NSArray<UDScriptVariableInfo *> *)variables fieldsReference:(NSInteger)fieldsReference
         object:(NSString *)object {
    if ([request.command isEqualToString:@"variables"]) {
        BOOL fields = [request.arguments[@"variablesReference"] integerValue] == fieldsReference;
        [self _answer:request variables:variables fields:fields fieldsReference:fieldsReference object:object];
        return;
    }
    // an evaluate: its expression over the frame's variables
    UDScriptVariablesQuery *query = [[UDScriptVariablesQuery alloc] init];
    query.request = request;
    query.expression = [UDScriptExpression expressionWithText:[request.arguments[@"expression"]
        stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] error:NULL];
    if (query.expression == nil) {
        [request failWithMessage:@"Not an expression"];
        return;
    }
    query.names = query.expression.names.allObjects;
    query.values = [NSMutableDictionary dictionary];
    for (UDScriptVariableInfo *variable in variables) {
        if ([query.expression.names containsObject:variable.name]) query.values[variable.name] = variable.value;
    }
    if (object.length > 0 && [query.expression.names containsObject:@"self"]) {
        query.selfReference = fieldsReference;
        query.selfObject = object;
    }
    [self _answerEvaluate:query];
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
    if (query.expression != nil) {
        [self _answerEvaluate:query];
        return;
    }
    NSMutableArray *variables = [NSMutableArray array];
    for (NSString *name in query.names) {
        NSString *value = query.values[name] ?: @"???";
        [variables addObject:[self _describeVariable:name value:value selfReference:query.selfReference object:query.selfObject]];
    }
    [query.request respondWithBody:@{ @"variables": variables }];
}

- (NSInteger)_frameOfScopeDepth:(int)depth {
    return depth == -1 ? 0 : (NSInteger)_frames.count - depth;
}

#pragma mark - Setting a variable, going on from another line

/// A local, a parameter or one of self's fields (a newer server's), of the
/// stopped thread's frames or another's.
- (void)setVariable:(UDDAPRequest *)request {
    NSInteger reference = [request.arguments[@"variablesReference"] integerValue];
    NSString *name = request.arguments[@"name"];
    NSString *value = request.arguments[@"value"];
    if (!(_engineCapabilities & UDScriptDebuggerCapabilityInspect)) {
        [request failWithMessage:@"This dhewm3 cannot set a variable"];
        return;
    }
    NSArray *key = nil;
    NSInteger place = (reference - UDOtherReferenceBase - 1) / 2;
    if (reference >= UDOtherReferenceBase && place < (NSInteger)_otherFrames.count) {
        key = [self _keyOfOtherFrame:place];
    } else if (reference >= 1 && reference < UDEntityReferenceBase && (reference - 1) / 2 < (NSInteger)_frames.count) {
        key = @[@([self _currentThread]), @([self _scopeDepthOfFrame:(reference - 1) / 2])];
    }
    if (!_stopped || key == nil || ![name isKindOfClass:[NSString class]] || ![value isKindOfClass:[NSString class]]) {
        [request failWithMessage:@"Only a function's variables and its object's fields can be set"];
        return;
    }
    [_setRequests addObject:request];
    [_game setVariable:name value:value thread:[key[0] intValue] scopeDepth:[key[1] intValue]];
}

- (void)debuggerConnection:(UDScriptDebuggerConnection *)connection didSetVariable:(NSString *)name
                    thread:(int)number scopeDepth:(int)scopeDepth set:(BOOL)set value:(NSString *)value {
    // what was listed of the frame is not what it has now
    if (set) [_threadVariables removeObjectForKey:@[@(number), @(scopeDepth)]];
    for (UDDAPRequest *request in [_setRequests copy]) {
        if (![request.arguments[@"name"] isEqual:name]) continue;
        [_setRequests removeObject:request];
        if (set) [request respondWithBody:@{ @"value": value }];
        else [request failWithMessage:value];
        break;
    }
}

/// Where the stopped thread can go on from: a line of the function it is
/// in (the game says whether it has code there).
- (void)gotoTargets:(UDDAPRequest *)request {
    NSDictionary *source = request.arguments[@"source"];
    NSString *path = [source isKindOfClass:[NSDictionary class]] ? source[@"path"] : nil;
    int line = [request.arguments[@"line"] intValue];
    if (!(_engineCapabilities & UDScriptDebuggerCapabilityInspect)) {
        [request failWithMessage:@"This dhewm3 cannot go on from another line"];
        return;
    }
    NSString *gamePath = [path isKindOfClass:[NSString class]] ? [self gamePathOf:path] : nil;
    UDScriptStackFrame *top = _frames.firstObject;
    if (!_stopped || top == nil) {
        [request failWithMessage:@"The game is not stopped"];
        return;
    }
    // the function the stopped thread is in: a script thread jumps within it
    NSString *function = UDFunctionName(top.function);
    NSString *text = [self _textOf:top.path];
    NSRange lines = text != nil ? [UDScriptIndex linesOfFunctionAtLine:top.line inText:text] : NSMakeRange(NSNotFound, 0);
    BOOL sameFile = gamePath != nil && [gamePath caseInsensitiveCompare:top.path] == NSOrderedSame;
    if (!sameFile || (lines.location != NSNotFound && !NSLocationInRange((NSUInteger)line, lines))) {
        [request failWithMessage:[NSString stringWithFormat:@"The thread is stopped in %@: it can only jump to a line of that function",
                                  function]];
        return;
    }
    [request respondWithBody:@{ @"targets": @[ @{ @"id": @(line), @"label": [NSString stringWithFormat:@"Line %d", line],
                                                  @"line": @(line) } ] }];
}

- (void)gotoRequest:(UDDAPRequest *)request {
    if (!(_engineCapabilities & UDScriptDebuggerCapabilityInspect)) {
        [request failWithMessage:@"This dhewm3 cannot go on from another line"];
        return;
    }
    if (!_stopped) {
        [request failWithMessage:@"The game is not stopped"];
        return;
    }
    id thread = request.arguments[@"threadId"];
    if (thread != nil && [thread intValue] != [self _currentThread]) {
        [request failWithMessage:@"Only the thread the game stopped in can jump"];
        return;
    }
    _gotoRequest = request;
    [_game setNextStatementLine:[request.arguments[@"targetId"] intValue]];
}

/// The thread goes on from there: it stops there again, as DAP's goto has it.
- (void)debuggerConnection:(UDScriptDebuggerConnection *)connection didSetNextStatementLine:(int)line {
    UDDAPRequest *request = _gotoRequest;
    _gotoRequest = nil;
    if (request == nil) return;
    if (line == 0) {
        [request failWithMessage:[NSString stringWithFormat:@"Line %@ has no code of the function the thread is in",
                                  request.arguments[@"targetId"]]];
        return;
    }
    [request respondWithBody:nil];
    _stopLine = line;
    _frames = nil;
    [_variableQueries removeAllObjects];
    [_game inspectCallstack];
    [_connection sendEvent:@"stopped" body:@{ @"reason": @"goto", @"threadId": @([self _currentThread]), @"allThreadsStopped": @YES }];
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

/// Watches, hovers and the console: an expression (UDScriptExpression),
/// its variables asked of the game and it evaluated here. In the console,
/// what is not one (or a name that is no variable here: "noclip") is a
/// command for the game, as is anything after a "/".
- (void)evaluate:(UDDAPRequest *)request {
    NSString *text = [request.arguments[@"expression"] isKindOfClass:[NSString class]] ? request.arguments[@"expression"] : @"";
    text = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    BOOL console = [request.arguments[@"context"] isEqual:@"repl"];
    BOOL command = [text hasPrefix:@"/"] || [text hasPrefix:@"\\"];
    NSString *why = nil;
    UDScriptExpression *expression = command ? nil : [UDScriptExpression expressionWithText:text error:&why];
    if (console && (command || !_stopped || expression == nil)) {
        [self _executeCommand:command ? [text substringFromIndex:1] : text request:request];
        return;
    }
    if (!_stopped) {
        [request failWithMessage:@"The game is running"];
        return;
    }
    if (expression == nil) {
        [request failWithMessage:why];
        return;
    }
    NSInteger frame = request.arguments[@"frameId"] ? [request.arguments[@"frameId"] integerValue] - 1 : 0;
    // in another thread's frame: over its variables, as the game lists them
    NSInteger place = frame + 1 - UDOtherFrameBase;
    if (place >= 0) {
        if (place >= (NSInteger)_otherFrames.count || !(_engineCapabilities & UDScriptDebuggerCapabilityInspect)) {
            [request failWithMessage:@"This dhewm3 cannot read another thread's variables"];
            return;
        }
        [self _whenListedOtherFrame:place answer:request];
        return;
    }
    for (NSString *name in expression.names) {
        if ([self _canInspect:name inFrame:frame]) continue;
        if (console && expression.isVariable) [self _executeCommand:text request:request];
        else [request failWithMessage:[NSString stringWithFormat:@"%@ is not a variable here", name]];
        return;
    }
    UDScriptVariablesQuery *query = [[UDScriptVariablesQuery alloc] init];
    query.request = request;
    query.scopeDepth = (frame >= 0 && frame < (NSInteger)_frames.count) ? [self _scopeDepthOfFrame:frame] : -1;
    query.names = expression.names.allObjects;
    query.values = [NSMutableDictionary dictionary];
    query.expression = expression;
    NSString *object = [self _objectOfFrame:frame];
    if (object != nil && [expression.names containsObject:@"self"]) {
        query.selfReference = frame * 2 + 2;
        query.selfObject = object;
    }
    if (query.names.count == 0) {
        [self _answerEvaluate:query];
        return;
    }
    [_variableQueries addObject:query];
    for (NSString *name in query.names) [_game inspectVariable:name scopeDepth:query.scopeDepth];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, UDGameAnswerTimeout), _queue, ^{
        [self _answerVariables:query];
    });
}

- (void)_executeCommand:(NSString *)command request:(UDDAPRequest *)request {
    if (!_game.connected) {
        [request failWithMessage:@"The game is not connected"];
        return;
    }
    [_game executeCommand:command];
    [request respondWithBody:@{ @"result": @"", @"variablesReference": @0 }];
}

/// An evaluate's expression, its variables read: a variable alone as the
/// game writes it (a watch's missing one "???", as VS Code shows it; self
/// opening to its fields), else its value.
- (void)_answerEvaluate:(UDScriptVariablesQuery *)query {
    [_variableQueries removeObject:query];
    UDDAPRequest *request = query.request;
    UDScriptExpression *expression = query.expression;
    NSString *context = request.arguments[@"context"];
    if (expression.isVariable) {
        NSString *name = expression.names.anyObject;
        NSString *value = query.values[name] ?: @"???";
        // (a method's self the stock game cannot print: its type, as Locals shows it)
        BOOL isSelf = query.selfReference > 0 && [name isEqualToString:@"self"];
        if ([value isEqualToString:@"???"] && !isSelf && ![context isEqual:@"watch"]) {
            if ([context isEqual:@"repl"]) [self _executeCommand:expression.text request:request];
            else [request failWithMessage:[NSString stringWithFormat:@"%@ is not a variable here", name]];
            return;
        }
        NSDictionary *described = [self _describeVariable:name value:value selfReference:query.selfReference object:query.selfObject];
        NSMutableDictionary *body = [@{ @"result": described[@"value"], @"variablesReference": described[@"variablesReference"] } mutableCopy];
        if (described[@"type"] != nil) body[@"type"] = described[@"type"];
        [request respondWithBody:body];
        return;
    }
    NSString *why = nil;
    id value = [expression valueWithVariables:query.values error:&why];
    if (value == nil) {
        [request failWithMessage:why];
        return;
    }
    [request respondWithBody:@{ @"result": [UDScriptExpression displayOf:value], @"variablesReference": @0 }];
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
