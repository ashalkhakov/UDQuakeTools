/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 * UDScriptDebugger.m
 */

#import "UDScriptDebugger.h"
#import "UDWorkspace.h"

@interface UDScriptDebugger ()
@property (nonatomic, strong, readwrite, nullable) UDDebugSession *session;
@property (nonatomic, weak) UDWorkspace *workspace;
/// Run asked while a session was on: run once it has ended.
@property (nonatomic) BOOL restarting;
@end

@implementation UDScriptDebugger

- (instancetype)initWithWorkspace:(UDWorkspace *)workspace {
    if (!(self = [super init])) return nil;
    _workspace = workspace;
    _breakpoints = [[UDBreakpointStore alloc] init];
    _bar = [[UDDebugBarViewController alloc] init];
    _navigator = [[UDDebugNavigatorViewController alloc] init];
    _area = [[UDDebugAreaViewController alloc] init];
    // the watches, before a session too
    _area.breakpoints = _breakpoints;
    _breakpointNavigator = [[UDBreakpointNavigatorViewController alloc] init];
    _breakpointNavigator.breakpoints = _breakpoints;
    return self;
}

- (BOOL)isDebugging {
    return self.session != nil && self.session.state != UDDebugSessionStateEnded;
}

+ (NSString *)adapterPath {
    return NSProcessInfo.processInfo.environment[@"UD_SCRIPT_DAP"]
        ?: [[NSBundle mainBundle] pathForAuxiliaryExecutable:@"udscript-dap"];
}

+ (NSArray<NSString *> *)argumentsOfCommandLine:(NSString *)line {
    NSMutableArray<NSString *> *words = [NSMutableArray array];
    NSMutableString *word = nil;
    BOOL quoted = NO;
    for (NSUInteger i = 0; i < line.length; i++) {
        unichar c = [line characterAtIndex:i];
        if (c == '"') {
            quoted = !quoted;
            if (word == nil) word = [NSMutableString string];
        } else if (!quoted && (c == ' ' || c == '\t' || c == '\n')) {
            if (word != nil) [words addObject:word];
            word = nil;
        } else {
            if (word == nil) word = [NSMutableString string];
            [word appendFormat:@"%C", c];
        }
    }
    if (word != nil) [words addObject:word];
    return words;
}

/// What launch and attach both take: the workspace's settings (its paths)
/// and the adapter's own arguments the workspace keeps ("Debugger": a
/// port, for the tests).
- (NSMutableDictionary *)_arguments {
    NSMutableDictionary *arguments = [NSMutableDictionary dictionary];
    [arguments addEntriesFromDictionary:[self.workspace settingsForTool:@"Debugger"] ?: @{}];
    arguments[@"settings"] = self.workspace.dictionaryRepresentation;
    return arguments;
}

- (BOOL)_start:(NSDictionary *)arguments launch:(BOOL)launch error:(NSError **)error {
    NSString *adapter = [[self class] adapterPath];
    if (adapter == nil) {
        if (error) *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileNoSuchFileError
                                            userInfo:@{NSLocalizedDescriptionKey: @"Quarry has no udscript-dap beside it."}];
        return NO;
    }
    [self stop];
    UDDebugSession *session = [[UDDebugSession alloc] initWithAdapterCommand:@[adapter] currentDirectoryPath:nil
                                                                 breakpoints:self.breakpoints];
    session.adapterID = @"udscript";
    session.clientName = @"Quarry";
    session.delegate = self;
    self.session = session;
    self.bar.session = session;
    self.navigator.session = session;
    self.area.session = session;
    if (launch) [session launchWithArguments:arguments];
    else [session attachWithArguments:arguments];
    if ([self.delegate respondsToSelector:@selector(scriptDebuggerDidStart:)]) [self.delegate scriptDebuggerDidStart:self];
    return YES;
}

- (BOOL)run:(NSError **)error {
    if (self.debugging) {
        // a restart: the game quit first, its debugger's port free
        self.restarting = YES;
        [self stop];
        return YES;
    }
    NSString *game = self.workspace.gameExecutable;
    if (game.length == 0) {
        if (error) *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileNoSuchFileError userInfo:@{
            NSLocalizedDescriptionKey: @"The workspace names no game to run.",
            NSLocalizedRecoverySuggestionErrorKey: @"Choose it in Workspace Settings, under Debugging."}];
        return NO;
    }
    NSMutableDictionary *arguments = [self _arguments];
    arguments[@"program"] = game;
    arguments[@"args"] = [[self class] argumentsOfCommandLine:self.workspace.gameArguments ?: @""];
    return [self _start:arguments launch:YES error:error];
}

- (BOOL)attach:(NSError **)error {
    return [self _start:[self _arguments] launch:NO error:error];
}

- (void)stop {
    if (self.debugging) [self.session stop];
}

#pragma mark - UDDebugSessionDelegate

- (void)debugSession:(UDDebugSession *)session showFile:(NSString *)path line:(NSInteger)line {
    NSString *gamePath = [self.workspace gamePathOfDiskPath:path];
    if (gamePath == nil) return;
    [self.delegate scriptDebugger:self showScript:gamePath line:line];
}

- (void)debugSessionDidEnd:(UDDebugSession *)session {
    if (session != self.session) return;
    if (self.restarting) {
        self.restarting = NO;
        NSError *error = nil;
        if ([self run:&error]) return;
    }
    if ([self.delegate respondsToSelector:@selector(scriptDebuggerDidEnd:)]) [self.delegate scriptDebuggerDidEnd:self];
}

@end
