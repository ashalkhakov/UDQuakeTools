//
//  UDScriptDebugAdapterTests.m
//  UDQuakeToolsTests
//
//  udscript-dap's adapter, between a DAP client (the test, on a pipe) and
//  the game (UDFakeScriptDebugger, on UDP), a mod's script on disk.
//

#import <XCTest/XCTest.h>
#import "UDScriptDebugAdapter.h"
#import "UDJSONRPCConnection.h"
#import "UDFakeScriptDebugger.h"
#import "UDScriptExpression.h"

#include <poll.h>
#include <unistd.h>

static NSString *const UDLampScript =
    @"void lamp_glow( float level ) {\n"           // 1
    @"    float times = level * 2;\n"              // 2
    @"    vector color = '1 1 1';\n"               // 3
    @"    sys.wait( times );\n"                    // 4
    @"}\n"                                         // 5
    @"\n"                                          // 6
    @"void main() {\n"                             // 7
    @"    entity lamp = sys.getEntity( \"lamp\" );\n"
    @"    lamp_glow( 0.5 );\n"                     // 9
    @"}\n";

@interface UDScriptDebugAdapterTests : XCTestCase
@end

@implementation UDScriptDebugAdapterTests {
    FILE *_written;
    FILE *_reading;
    dispatch_queue_t _queue;
    UDScriptDebugAdapter *_adapter;
    UDFakeScriptDebugger *_game;
    NSMutableArray<NSDictionary *> *_backlog;
    NSInteger _seq;
    NSString *_root;
    NSString *_script;
    NSNumber *_selfReference;
}

- (void)setUp {
    [super setUp];
    int fds[2];
    XCTAssertEqual(pipe(fds), 0);
    _reading = fdopen(fds[0], "r");
    setvbuf(_reading, NULL, _IONBF, 0);
    _written = fdopen(fds[1], "w");
    _queue = dispatch_queue_create("UDScriptDebugAdapterTests", DISPATCH_QUEUE_SERIAL);
    _adapter = [[UDScriptDebugAdapter alloc] initWithQueue:_queue output:_written];
    _game = [[UDFakeScriptDebugger alloc] initWithPort:[UDFakeScriptDebugger gamePort] debuggerPort:[UDFakeScriptDebugger debuggerPort]];
    _backlog = [NSMutableArray array];
    _root = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSUUID UUID].UUIDString];
    _script = [_root stringByAppendingPathComponent:@"base/script/lamp.script"];
    [[NSFileManager defaultManager] createDirectoryAtPath:_script.stringByDeletingLastPathComponent
                              withIntermediateDirectories:YES attributes:nil error:NULL];
    [UDLampScript writeToFile:_script atomically:YES encoding:NSUTF8StringEncoding error:NULL];
}

- (void)tearDown {
    [self request:@"disconnect" arguments:@{}];
    dispatch_sync(_queue, ^{});
    _adapter = nil;
    _game = nil;
    fclose(_written);
    fclose(_reading);
    [[NSFileManager defaultManager] removeItemAtPath:_root error:NULL];
    [super tearDown];
}

#pragma mark - The client's side

- (NSInteger)request:(NSString *)command arguments:(NSDictionary *)arguments {
    NSInteger seq = ++_seq;
    NSDictionary *message = @{ @"seq": @(seq), @"type": @"request", @"command": command, @"arguments": arguments };
    UDScriptDebugAdapter *adapter = _adapter;
    dispatch_async(_queue, ^{
        [adapter.connection handleMessage:message];
    });
    return seq;
}

- (NSDictionary *)readMessageWithin:(NSTimeInterval)timeout {
    struct pollfd wanted = { fileno(_reading), POLLIN, 0 };
    if (poll(&wanted, 1, (int)(timeout * 1000)) <= 0) return nil;
    NSData *body = [UDJSONRPCConnection readMessageFromFile:_reading];
    return body ? [NSJSONSerialization JSONObjectWithData:body options:0 error:NULL] : nil;
}

/// The next message @a matches, those before it kept for later.
- (NSDictionary *)messageWhere:(BOOL (^)(NSDictionary *message))matches {
    for (NSDictionary *message in [_backlog copy]) {
        if (matches(message)) {
            [_backlog removeObject:message];
            return message;
        }
    }
    NSDate *until = [NSDate dateWithTimeIntervalSinceNow:3];
    while (until.timeIntervalSinceNow > 0) {
        NSDictionary *message = [self readMessageWithin:until.timeIntervalSinceNow];
        if (message == nil) break;
        if (matches(message)) return message;
        [_backlog addObject:message];
    }
    return nil;
}

- (NSDictionary *)responseTo:(NSInteger)seq {
    return [self messageWhere:^BOOL(NSDictionary *message) {
        return [message[@"type"] isEqual:@"response"] && [message[@"request_seq"] integerValue] == seq;
    }];
}

- (NSDictionary *)event:(NSString *)name {
    return [self messageWhere:^BOOL(NSDictionary *message) {
        return [message[@"type"] isEqual:@"event"] && [message[@"event"] isEqual:name];
    }];
}

#pragma mark - The game's side

/// DBMSG_BREAK, and (once asked) the threads' answer, @a thread the current one.
- (void)breakAtLine:(int)line path:(NSString *)path thread:(int)thread {
    UDBitMsg *broke = [_game message:9 /* BREAK */];
    [broke writeInt:line];
    [broke writeString:path];
    [_game send:broke];
    XCTAssertNotNil([_game receiveType:13 /* INSPECTTHREADS */ within:3]);
    UDBitMsg *threads = [_game message:13];
    [threads writeShort:2];
    for (int number = 4; number <= 5; number++) {
        [threads writeString:number == 4 ? @"main" : @"lamp_blink"];
        [threads writeInt:number];
        [threads writeBits:number == thread ? 1 : 0 numBits:1];
        [threads writeBits:0 numBits:3];
    }
    [_game send:threads];
}

/// DBMSG_INSPECTCALLSTACK's answer: @[function, path, line] each.
- (void)sendCallstack:(NSArray<NSArray *> *)frames {
    UDBitMsg *stack = [_game message:12];
    [stack writeShort:(int)frames.count];
    for (NSArray *frame in frames) {
        [stack writeString:frame[0]];
        [stack writeString:frame[1]];
        [stack writeInt:[frame[2] intValue]];
    }
    [_game send:stack];
}

/// The temporary breakpoints a step set (their lines), up to its RESUME.
- (NSSet<NSNumber *> *)stepBreakpointLinesUntilResume {
    NSMutableSet<NSNumber *> *lines = [NSMutableSet set];
    for (;;) {
        int type = -1;
        UDBitMsg *message = [_game receiveWithin:3 type:&type];
        if (message == nil || type == 7 /* RESUME */ || type == 15 /* STEPINTO */) break;
        if (type != 4) continue;
        [message readBits:1];
        int line = [message readInt];
        if ([message readInt] >= 1000000) [lines addObject:@(line)];
    }
    return lines;
}

/// A variable's value, as the game answers DBMSG_INSPECTVARIABLE.
- (void)answerVariable:(NSString *)name value:(NSString *)value depth:(int)depth {
    UDBitMsg *answer = [_game message:11];
    [answer writeShort:depth];
    [answer writeString:name];
    [answer writeString:value];
    [_game send:answer];
}

#pragma mark - The session

/// Initialized, a breakpoint set, attached to the game, which connects
/// and stops at the breakpoint in lamp_glow, called from main.
- (void)attachAndStop {
    NSDictionary *initialize = [self responseTo:[self request:@"initialize" arguments:@{ @"adapterID": @"idscript" }]];
    XCTAssertEqualObjects(initialize[@"body"][@"supportsConfigurationDoneRequest"], @YES);

    NSInteger attach = [self request:@"attach" arguments:@{ @"sourceRoots": @[[_root stringByAppendingPathComponent:@"base"]],
                                                           @"port": @([UDFakeScriptDebugger gamePort]),
                                                           @"localPort": @([UDFakeScriptDebugger debuggerPort]) }];
    XCTAssertNotNil([self event:@"initialized"], @"the workspace known, the breakpoints asked for");
    XCTAssertNotNil([_game receiveType:1 /* CONNECT */ within:3], @"attach connects");
    NSDictionary *set = [self responseTo:[self request:@"setBreakpoints" arguments:@{
        @"source": @{ @"path": _script }, @"breakpoints": @[ @{ @"line": @3 } ] }]];
    XCTAssertEqualObjects(set[@"body"][@"breakpoints"][0][@"verified"], @NO, @"not yet: the game is not connected");
    [_game send:[_game message:2 /* CONNECTED */]];
    XCTAssertEqualObjects([self responseTo:attach][@"success"], @YES);

    // the breakpoint, sent as the game names the script
    UDBitMsg *add = [_game receiveType:4 /* ADDBREAKPOINT */ within:3];
    XCTAssertNotNil(add);
    XCTAssertEqual([add readBits:1], 0u);
    XCTAssertEqual([add readInt], 3);
    int identifier = [add readInt];
    XCTAssertEqualObjects([add readString], @"script/lamp.script");
    NSDictionary *verified = [self event:@"breakpoint"];
    XCTAssertEqualObjects(verified[@"body"][@"breakpoint"][@"verified"], @YES);
    XCTAssertEqualObjects(verified[@"body"][@"breakpoint"][@"id"], @(identifier));
    XCTAssertEqualObjects([self responseTo:[self request:@"configurationDone" arguments:@{}]][@"success"], @YES);

    // the game stops there
    UDBitMsg *broke = [_game message:9 /* BREAK */];
    [broke writeInt:3];
    [broke writeString:@"script/lamp.script"];
    [_game send:broke];
    XCTAssertNotNil([_game receiveType:13 /* INSPECTTHREADS */ within:3]);
    UDBitMsg *threads = [_game message:13];
    [threads writeShort:1];
    [threads writeString:@"main"];
    [threads writeInt:4];
    [threads writeBits:1 numBits:1];
    [threads writeBits:0 numBits:1];
    [threads writeBits:0 numBits:1];
    [threads writeBits:0 numBits:1];
    [_game send:threads];
    UDBitMsg *stack = [_game message:12 /* INSPECTCALLSTACK */];
    [stack writeShort:2];
    [stack writeString:@"lamp_glow(  )"];
    [stack writeString:@"script/lamp.script"];
    [stack writeInt:3];
    [stack writeString:@"main(  )"];
    [stack writeString:@"script/lamp.script"];
    [stack writeInt:9];
    [_game send:stack];

    NSDictionary *stopped = [self event:@"stopped"];
    XCTAssertEqualObjects(stopped[@"body"][@"reason"], @"breakpoint");
    XCTAssertEqualObjects(stopped[@"body"][@"threadId"], @4);
    XCTAssertEqualObjects(stopped[@"body"][@"hitBreakpointIds"], @[@(identifier)]);
}

- (void)testABreakpointStopsTheGameAndItsFramesAndVariablesAreRead {
    if (_game == nil) return;
    [self attachAndStop];

    NSDictionary *threads = [self responseTo:[self request:@"threads" arguments:@{}]];
    XCTAssertEqualObjects(threads[@"body"][@"threads"], (@[ @{ @"id": @4, @"name": @"main" } ]));
    NSDictionary *trace = [self responseTo:[self request:@"stackTrace" arguments:@{ @"threadId": @4 }]];
    NSArray *frames = trace[@"body"][@"stackFrames"];
    XCTAssertEqual(frames.count, 2u);
    XCTAssertEqualObjects(frames[0][@"name"], @"lamp_glow");
    XCTAssertEqualObjects(frames[0][@"line"], @3);
    XCTAssertEqualObjects(frames[0][@"source"][@"path"], _script.stringByStandardizingPath, @"the script on disk");
    XCTAssertEqualObjects(frames[1][@"name"], @"main");
    XCTAssertEqualObjects(frames[1][@"line"], @9);

    // a frame's variables: its function's, each read by name
    NSDictionary *scopes = [self responseTo:[self request:@"scopes" arguments:@{ @"frameId": frames[0][@"id"] }]];
    NSNumber *locals = scopes[@"body"][@"scopes"][0][@"variablesReference"];
    NSInteger variables = [self request:@"variables" arguments:@{ @"variablesReference": locals }];
    NSMutableSet *asked = [NSMutableSet set];
    for (int i = 0; i < 3; i++) {
        UDBitMsg *inspect = [_game receiveType:11 /* INSPECTVARIABLE */ within:3];
        XCTAssertEqual([inspect readShort], -1, @"the function stopped in");
        NSString *name = [inspect readString];
        [asked addObject:name];
        UDBitMsg *value = [_game message:11];
        [value writeShort:-1];
        [value writeString:name];
        [value writeString:[name isEqualToString:@"color"] ? @"1,1,1" : @"0.5"];
        [_game send:value];
    }
    XCTAssertEqualObjects(asked, ([NSSet setWithArray:@[@"level", @"times", @"color"]]));
    NSArray *read = [self responseTo:variables][@"body"][@"variables"];
    XCTAssertEqualObjects([read valueForKey:@"name"], (@[@"level", @"times", @"color"]));
    XCTAssertEqualObjects(read[2][@"value"], @"1,1,1");

    // a hover in the frame under it: the interpreter's call stack's
    NSInteger hover = [self request:@"evaluate" arguments:@{ @"expression": @"lamp", @"frameId": frames[1][@"id"], @"context": @"hover" }];
    UDBitMsg *inspect = [_game receiveType:11 within:3];
    XCTAssertEqual([inspect readShort], 1, @"callStack[depth - 1]");
    XCTAssertEqualObjects([inspect readString], @"lamp");
    UDBitMsg *value = [_game message:11];
    [value writeShort:1];
    [value writeString:@"lamp"];
    [value writeString:@"<entity lamp>"];
    [_game send:value];
    XCTAssertEqualObjects([self responseTo:hover][@"body"][@"result"], @"<entity lamp>");
    // in the console, a command
    [self responseTo:[self request:@"evaluate" arguments:@{ @"expression": @"/god", @"context": @"repl" }]];
    XCTAssertEqualObjects([[_game receiveType:17 /* EXECCOMMAND */ within:3] readString], @"god");

    // a step (the stock server's own steps end when any thread returns: the
    // adapter's, temporary breakpoints where it may end), then going on
    [self responseTo:[self request:@"next" arguments:@{ @"threadId": @4 }]];
    NSSet<NSNumber *> *lines = [self stepBreakpointLinesUntilResume];
    XCTAssertTrue([lines containsObject:@4] && [lines containsObject:@2], @"the function's lines: %@", lines);
    XCTAssertFalse([lines containsObject:@3], @"not the one it is on: %@", lines);
    XCTAssertTrue([lines containsObject:@9], @"the caller's, where it returns: %@", lines);
    [self breakAtLine:4 path:@"script/lamp.script" thread:4];
    XCTAssertEqualObjects([self event:@"stopped"][@"body"][@"reason"], @"step");
    XCTAssertNotNil([_game receiveType:5 /* REMOVEBREAKPOINT */ within:3], @"the step's breakpoints taken off");
    XCTAssertEqualObjects([self responseTo:[self request:@"continue" arguments:@{ @"threadId": @4 }]][@"success"], @YES);
    XCTAssertNotNil([_game receiveType:7 /* RESUME */ within:3]);

    // the game's console, as output
    UDBitMsg *print = [_game message:10 /* PRINT */];
    [print writeString:@"lamp lit\n"];
    [_game send:print];
    NSDictionary *output = [self messageWhere:^BOOL(NSDictionary *message) {
        return [message[@"event"] isEqual:@"output"] && [message[@"body"][@"category"] isEqual:@"console"];
    }];
    XCTAssertEqualObjects(output[@"body"][@"output"], @"lamp lit\n");
}

/// A line with no code: the game takes the breakpoint off, and it is
/// unverified; a script elsewhere is never one of the game's.
- (void)testABreakpointTheGameRefusesIsUnverified {
    if (_game == nil) return;
    [self attachAndStop];
    NSInteger set = [self request:@"setBreakpoints" arguments:@{ @"source": @{ @"path": _script }, @"breakpoints": @[ @{ @"line": @6 } ] }];
    XCTAssertNotNil([_game receiveType:5 /* REMOVEBREAKPOINT */ within:3], @"the old one taken off");
    XCTAssertNotNil([_game receiveType:4 within:3]);
    XCTAssertEqualObjects([self responseTo:set][@"body"][@"breakpoints"][0][@"verified"], @YES);
    UDBitMsg *refused = [_game message:5];
    [refused writeInt:6];
    [refused writeString:@"script/lamp.script"];
    [_game send:refused];
    NSDictionary *changed = [self event:@"breakpoint"];
    XCTAssertEqualObjects(changed[@"body"][@"breakpoint"][@"verified"], @NO);
    XCTAssertEqualObjects(changed[@"body"][@"breakpoint"][@"line"], @6);

    NSDictionary *elsewhere = [self responseTo:[self request:@"setBreakpoints" arguments:@{
        @"source": @{ @"path": @"/nowhere/else.script" }, @"breakpoints": @[ @{ @"line": @1 } ] }]];
    XCTAssertEqualObjects(elsewhere[@"body"][@"breakpoints"][0][@"verified"], @NO);
}

/// In a namespace's function the game is asked only for the function's
/// variables: for another name, idInterpreter::GetRegisterValue looks for
/// the namespace's superclass, and the game aborts.
- (void)testANamespacesFunctionIsAskedOnlyForItsVariables {
    if (_game == nil) return;
    NSString *lamps = [_root stringByAppendingPathComponent:@"base/script/lamps.script"];
    [@"namespace lamps {\n"
     @"    void glow( float level ) {\n"
     @"        sys.wait( level );\n"
     @"    }\n"
     @"}\n" writeToFile:lamps atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    [self attachAndStop];
    [self responseTo:[self request:@"continue" arguments:@{ @"threadId": @4 }]];
    XCTAssertNotNil([_game receiveType:7 /* RESUME */ within:3]);

    UDBitMsg *broke = [_game message:9];
    [broke writeInt:3];
    [broke writeString:@"script/lamps.script"];
    [_game send:broke];
    XCTAssertNotNil([_game receiveType:13 within:3]);
    UDBitMsg *threads = [_game message:13];
    [threads writeShort:1];
    [threads writeString:@"main"];
    [threads writeInt:4];
    [threads writeBits:1 numBits:1];
    [threads writeBits:0 numBits:3];
    [_game send:threads];
    UDBitMsg *stack = [_game message:12];
    [stack writeShort:1];
    [stack writeString:@"lamps::glow(  )"];
    [stack writeString:@"script/lamps.script"];
    [stack writeInt:3];
    [_game send:stack];
    XCTAssertNotNil([self event:@"stopped"]);
    [self responseTo:[self request:@"stackTrace" arguments:@{ @"threadId": @4 }]];

    NSDictionary *unknown = [self responseTo:[self request:@"evaluate" arguments:@{ @"expression": @"nosuchname", @"frameId": @1, @"context": @"hover" }]];
    XCTAssertEqualObjects(unknown[@"success"], @NO);
    XCTAssertNil([_game receiveType:11 within:0.5], @"not asked of the game");
    [self request:@"evaluate" arguments:@{ @"expression": @"level", @"frameId": @1, @"context": @"hover" }];
    UDBitMsg *inspect = [_game receiveType:11 within:3];
    XCTAssertNotNil(inspect, @"its parameter is");
    [inspect readShort];
    XCTAssertEqualObjects([inspect readString], @"level");
}

/// A breakpoint's condition, hit count and log message: the adapter reads
/// what they name and decides (the game has none of them).
- (void)testABreakpointsConditionHitCountAndLogMessageAreTheAdapters {
    if (_game == nil) return;
    [self attachAndStop];
    [self responseTo:[self request:@"continue" arguments:@{ @"threadId": @4 }]];
    XCTAssertNotNil([_game receiveType:7 within:3]);
    NSDictionary *set = [self responseTo:[self request:@"setBreakpoints" arguments:@{ @"source": @{ @"path": _script }, @"breakpoints": @[
        @{ @"line": @2, @"condition": @"level > 1 && level != 3" },
        @{ @"line": @3, @"hitCondition": @"2" },
        @{ @"line": @4, @"logMessage": @"glowing {level * 2} {{x}}" },
        @{ @"line": @9, @"condition": @"level >" } ] }]];
    NSArray *answered = set[@"body"][@"breakpoints"];
    XCTAssertEqualObjects(answered[3][@"verified"], @NO, @"a condition that does not read");
    XCTAssertNotNil(answered[3][@"message"]);

    // the condition false: on, the client told nothing
    [self breakAtLine:2 path:@"script/lamp.script" thread:4];
    UDBitMsg *inspect = [_game receiveType:11 within:3];
    XCTAssertEqual([inspect readShort], -1);
    XCTAssertEqualObjects([inspect readString], @"level");
    [self answerVariable:@"level" value:@"0.5" depth:-1];
    XCTAssertNotNil([_game receiveType:7 /* RESUME */ within:3], @"level 0.5: on");
    // true: stopped
    [self breakAtLine:2 path:@"script/lamp.script" thread:4];
    XCTAssertNotNil([_game receiveType:11 within:3]);
    [self answerVariable:@"level" value:@"2" depth:-1];
    NSDictionary *stopped = [self event:@"stopped"];
    XCTAssertEqualObjects(stopped[@"body"][@"reason"], @"breakpoint");
    [self responseTo:[self request:@"continue" arguments:@{ @"threadId": @4 }]];
    XCTAssertNotNil([_game receiveType:7 within:3]);

    // the hit count: the second time
    [self breakAtLine:3 path:@"script/lamp.script" thread:4];
    XCTAssertNotNil([_game receiveType:7 within:3], @"the first time: on");
    [self breakAtLine:3 path:@"script/lamp.script" thread:4];
    XCTAssertEqualObjects([self event:@"stopped"][@"body"][@"reason"], @"breakpoint");
    [self responseTo:[self request:@"continue" arguments:@{ @"threadId": @4 }]];
    XCTAssertNotNil([_game receiveType:7 within:3]);

    // the logpoint: its message, and on
    [self breakAtLine:4 path:@"script/lamp.script" thread:4];
    XCTAssertNotNil([_game receiveType:11 within:3]);
    [self answerVariable:@"level" value:@"1.5" depth:-1];
    NSDictionary *logged = [self messageWhere:^BOOL(NSDictionary *message) {
        return [message[@"event"] isEqual:@"output"] && [message[@"body"][@"category"] isEqual:@"console"];
    }];
    XCTAssertEqualObjects(logged[@"body"][@"output"], @"glowing 3 {x}\n");
    XCTAssertNotNil([_game receiveType:7 within:3], @"a logpoint does not stop");
}

/// A step's breakpoint reached by another thread is gone on from; the
/// step ends in its own thread.
- (void)testAStepEndsInItsOwnThread {
    if (_game == nil) return;
    [self attachAndStop];
    [self responseTo:[self request:@"stackTrace" arguments:@{ @"threadId": @4 }]];
    [self responseTo:[self request:@"stepOut" arguments:@{ @"threadId": @4 }]];
    NSSet<NSNumber *> *lines = [self stepBreakpointLinesUntilResume];
    XCTAssertTrue([lines containsObject:@9], @"step out: the caller's lines %@", lines);
    XCTAssertFalse([lines containsObject:@2], @"not the function's: %@", lines);
    [self breakAtLine:9 path:@"script/lamp.script" thread:5];
    XCTAssertNotNil([_game receiveType:7 /* RESUME */ within:3], @"another thread there: on");
    [self breakAtLine:9 path:@"script/lamp.script" thread:4];
    XCTAssertEqualObjects([self event:@"stopped"][@"body"][@"reason"], @"step");
}

/// A server that says it can (DBMSG_VERSION): its own steps, and its lists
/// of a frame's variables, Locals and Fields.
- (void)testANewerServersStepsAndVariablesAreUsed {
    if (_game == nil) return;
    NSString *lamps = [_root stringByAppendingPathComponent:@"base/script/lamps.script"];
    [@"object lamp {\n"
     @"    float brightness;\n"
     @"    void glow( float level );\n"
     @"};\n"
     @"void lamp::glow( float level ) {\n"
     @"    brightness = level;\n"
     @"}\n" writeToFile:lamps atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    [self responseTo:[self request:@"initialize" arguments:@{}]];
    NSInteger attach = [self request:@"attach" arguments:@{ @"sourceRoots": @[[_root stringByAppendingPathComponent:@"base"]],
                                                           @"port": @([UDFakeScriptDebugger gamePort]),
                                                           @"localPort": @([UDFakeScriptDebugger debuggerPort]) }];
    XCTAssertNotNil([_game receiveType:1 within:3]);
    [_game send:[_game message:2]];
    UDBitMsg *version = [_game message:18 /* VERSION */];
    [version writeInt:2];
    [version writeInt:3];
    [_game send:version];
    XCTAssertEqualObjects([self responseTo:attach][@"success"], @YES);

    [self breakAtLine:6 path:@"script/lamps.script" thread:4];
    [self sendCallstack:@[ @[ @"lamp::glow(  )", @"script/lamps.script", @6 ] ]];
    XCTAssertNotNil([self event:@"stopped"]);
    NSArray *frames = [self responseTo:[self request:@"stackTrace" arguments:@{ @"threadId": @4 }]][@"body"][@"stackFrames"];
    NSArray *scopes = [self responseTo:[self request:@"scopes" arguments:@{ @"frameId": frames[0][@"id"] }]][@"body"][@"scopes"];
    XCTAssertEqualObjects([scopes valueForKey:@"name"], @[@"Locals"]);
    // the server's list: Locals with self, which opens to the fields
    for (int i = 0; i < 2; i++) {
        NSInteger asked = [self request:@"variables" arguments:@{ @"variablesReference": i == 0 ? scopes[0][@"variablesReference"] : _selfReference }];
        UDBitMsg *list = [_game receiveType:20 /* INSPECTVARIABLES */ within:3];
        XCTAssertEqual([list readShort], -1);
        UDBitMsg *answer = [_game message:20];
        [answer writeShort:-1];
        [answer writeShort:3];
        [answer writeString:@"self"];
        [answer writeString:@"$lamp_1"];
        [answer writeBits:0 numBits:8];
        [answer writeString:@"level"];
        [answer writeString:@"0.5"];
        [answer writeBits:0 numBits:8];
        [answer writeString:@"brightness"];
        [answer writeString:@"1"];
        [answer writeBits:1 numBits:8];
        [_game send:answer];
        NSArray *variables = [self responseTo:asked][@"body"][@"variables"];
        if (i == 0) {
            XCTAssertEqualObjects([variables valueForKey:@"name"], (@[@"self", @"level"]));
            XCTAssertEqualObjects(variables[0][@"value"], @"$lamp_1 (lamp)");
            _selfReference = variables[0][@"variablesReference"];
            XCTAssertGreaterThan([_selfReference integerValue], 0, @"self opens");
        } else {
            XCTAssertEqualObjects([variables valueForKey:@"name"], @[@"brightness"], @"self's fields");
        }
    }

    [self responseTo:[self request:@"stepOut" arguments:@{ @"threadId": @4 }]];
    XCTAssertNotNil([_game receiveType:19 /* STEPOUT */ within:3], @"the server's own step");
}

/// Without a newer server, a method's fields come from the scripts: its
/// object's and its superclasses'.
- (void)testAMethodsFieldsAreItsObjectsAndItsSuperclasses {
    if (_game == nil) return;
    NSString *lamps = [_root stringByAppendingPathComponent:@"base/script/lamps.script"];
    [@"object light_base {\n"
     @"    float lit;\n"
     @"};\n"
     @"object lamp : light_base {\n"
     @"    float brightness;\n"
     @"    void glow();\n"
     @"};\n"
     @"void lamp::glow() {\n"
     @"    brightness = 1;\n"
     @"}\n" writeToFile:lamps atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    [self attachAndStop];
    UDBitMsg *scripts = [_game message:16 /* INSPECTSCRIPTS */];
    [scripts writeInt:2];
    [scripts writeString:@"script/lamp.script"];
    [scripts writeString:@"script/lamps.script"];
    [_game send:scripts];
    [self responseTo:[self request:@"continue" arguments:@{ @"threadId": @4 }]];
    [self breakAtLine:9 path:@"script/lamps.script" thread:4];
    [self sendCallstack:@[ @[ @"lamp::glow(  )", @"script/lamps.script", @9 ] ]];
    XCTAssertNotNil([self event:@"stopped"]);
    NSArray *frames = [self responseTo:[self request:@"stackTrace" arguments:@{ @"threadId": @4 }]][@"body"][@"stackFrames"];
    NSArray *scopes = [self responseTo:[self request:@"scopes" arguments:@{ @"frameId": frames[0][@"id"] }]][@"body"][@"scopes"];
    XCTAssertEqual(scopes.count, 1u);
    // Locals: self (the script declares it not), which opens to the fields
    NSInteger locals = [self request:@"variables" arguments:@{ @"variablesReference": scopes[0][@"variablesReference"] }];
    UDBitMsg *inspectSelf = [_game receiveType:11 within:3];
    int selfDepth = [inspectSelf readShort];
    XCTAssertEqualObjects([inspectSelf readString], @"self");
    [self answerVariable:@"self" value:@"???" depth:selfDepth];
    NSArray *localVariables = [self responseTo:locals][@"body"][@"variables"];
    XCTAssertEqualObjects(localVariables[0][@"name"], @"self");
    XCTAssertEqualObjects(localVariables[0][@"value"], @"lamp", @"the stock game cannot print an object: its type");
    NSInteger fields = [self request:@"variables" arguments:@{ @"variablesReference": localVariables[0][@"variablesReference"] }];
    NSMutableArray *asked = [NSMutableArray array];
    for (int i = 0; i < 2; i++) {
        UDBitMsg *inspect = [_game receiveType:11 within:3];
        int depth = [inspect readShort];
        NSString *name = [inspect readString];
        [asked addObject:name];
        [self answerVariable:name value:@"1" depth:depth];
    }
    XCTAssertEqualObjects(asked, (@[@"brightness", @"lit"]), @"the object's, then its superclass's");
    XCTAssertEqual([[self responseTo:fields][@"body"][@"variables"] count], 2u);
}

/// The adapter's expressions, over the game's formatting of values.
- (void)testExpressionsAreEvaluatedOverTheGamesValues {
    NSDictionary *values = @{ @"count": @"3", @"name": @"\"lamp\"", @"owner": @"$player1", @"origin": @"1,2,3", @"missing": @"???" };
    NSArray<NSArray *> *cases = @[
        @[@"count > 2 && count != 4", @YES], @[@"!(count == 3)", @NO], @[@"count * 2 - 1 == 5", @YES],
        @[@"name == \"lamp\"", @YES], @[@"owner == $player1", @YES], @[@"origin == \"1,2,3\"", @YES],
        @[@"count % 2 == 1 || missing", @YES], @[@"-count < 0", @YES],
    ];
    for (NSArray *test in cases) {
        NSString *error = nil;
        UDScriptExpression *expression = [UDScriptExpression expressionWithText:test[0] error:&error];
        XCTAssertNotNil(expression, @"%@: %@", test[0], error);
        id value = [expression valueWithVariables:values error:&error];
        XCTAssertNotNil(value, @"%@: %@", test[0], error);
        XCTAssertEqual([UDScriptExpression isTrue:value], [test[1] boolValue], @"%@", test[0]);
    }
    NSString *error = nil;
    XCTAssertNil([[UDScriptExpression expressionWithText:@"missing > 1" error:NULL] valueWithVariables:values error:&error]);
    XCTAssertTrue([error containsString:@"missing"], @"%@", error);
    XCTAssertNil([UDScriptExpression expressionWithText:@"count >" error:&error]);
    XCTAssertNil([UDScriptExpression expressionWithText:@"(count" error:&error]);
    XCTAssertEqualObjects([[UDScriptExpression expressionWithText:@"count" error:NULL] names], [NSSet setWithObject:@"count"]);
    // hit counts, as VS Code's
    XCTAssertTrue([UDScriptExpression hitCount:5 passes:@"5" error:NULL]);
    XCTAssertFalse([UDScriptExpression hitCount:4 passes:@"== 5" error:NULL]);
    XCTAssertTrue([UDScriptExpression hitCount:6 passes:@">= 5" error:NULL]);
    XCTAssertTrue([UDScriptExpression hitCount:10 passes:@"% 5" error:NULL]);
    XCTAssertFalse([UDScriptExpression hitCount:1 passes:@"often" error:&error]);
    // a logpoint's pieces
    NSArray *parts = [UDScriptExpression partsOfMessage:@"a {count} {{b}}" error:NULL];
    XCTAssertEqual(parts.count, 3u);
    XCTAssertEqualObjects(parts[0], @"a ");
    XCTAssertEqualObjects(parts[2], @" {b}");
}

@end
