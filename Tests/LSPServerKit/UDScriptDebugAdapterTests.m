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

    // a step, then going on
    [self responseTo:[self request:@"next" arguments:@{ @"threadId": @4 }]];
    XCTAssertNotNil([_game receiveType:14 /* STEPOVER */ within:3]);
    UDBitMsg *broke = [_game message:9];
    [broke writeInt:4];
    [broke writeString:@"script/lamp.script"];
    [_game send:broke];
    XCTAssertNotNil([_game receiveType:13 within:3]);
    UDBitMsg *threads2 = [_game message:13];
    [threads2 writeShort:1];
    [threads2 writeString:@"main"];
    [threads2 writeInt:4];
    [threads2 writeBits:1 numBits:1];
    [threads2 writeBits:0 numBits:3];
    [_game send:threads2];
    XCTAssertEqualObjects([self event:@"stopped"][@"body"][@"reason"], @"step");
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

@end
