//
//  UDScriptDebuggerConnectionTests.m
//  UDQuakeToolsTests
//

#import <XCTest/XCTest.h>
#import "UDScriptDebuggerConnection.h"
#import "UDFakeScriptDebugger.h"

@interface UDScriptDebuggerConnectionTests : XCTestCase <UDScriptDebuggerConnectionDelegate>
@property (nonatomic, strong) NSMutableArray *heard;
@end

@implementation UDScriptDebuggerConnectionTests {
    dispatch_queue_t _queue;
    dispatch_semaphore_t _told;
}

- (void)setUp {
    [super setUp];
    _queue = dispatch_queue_create("UDScriptDebuggerConnectionTests", DISPATCH_QUEUE_SERIAL);
    _told = dispatch_semaphore_create(0);
    self.heard = [NSMutableArray array];
}

/// What the delegate was told next (nil after two seconds).
- (id)nextHeard {
    if (dispatch_semaphore_wait(_told, dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC)) != 0) return nil;
    __block id first = nil;
    dispatch_sync(self->_queue, ^{
        first = self.heard.firstObject;
        if (first != nil) [self.heard removeObjectAtIndex:0];
    });
    return first;
}

- (void)hear:(id)what {
    [self.heard addObject:what];
    dispatch_semaphore_signal(_told);
}

- (void)debuggerConnectionDidConnect:(UDScriptDebuggerConnection *)connection { [self hear:@"connected"]; }
- (void)debuggerConnectionDidDisconnect:(UDScriptDebuggerConnection *)connection { [self hear:@"disconnected"]; }
- (void)debuggerConnectionDidResume:(UDScriptDebuggerConnection *)connection { [self hear:@"resumed"]; }
- (void)debuggerConnection:(UDScriptDebuggerConnection *)connection didBreakAtLine:(int)line path:(NSString *)path {
    [self hear:[NSString stringWithFormat:@"break %@:%d", path, line]];
}
- (void)debuggerConnection:(UDScriptDebuggerConnection *)connection didPrint:(NSString *)text {
    [self hear:[@"print " stringByAppendingString:text]];
}
- (void)debuggerConnection:(UDScriptDebuggerConnection *)connection didRemoveBreakpointAtLine:(int)line path:(NSString *)path {
    [self hear:[NSString stringWithFormat:@"removed %@:%d", path, line]];
}
- (void)debuggerConnection:(UDScriptDebuggerConnection *)connection didReceiveCallstack:(NSArray<UDScriptStackFrame *> *)frames {
    [self hear:frames];
}
- (void)debuggerConnection:(UDScriptDebuggerConnection *)connection didReceiveThreads:(NSArray<UDScriptThreadInfo *> *)threads {
    [self hear:threads];
}
- (void)debuggerConnection:(UDScriptDebuggerConnection *)connection didReceiveValue:(NSString *)value
                  variable:(NSString *)name scopeDepth:(int)scopeDepth {
    [self hear:[NSString stringWithFormat:@"%@@%d = %@", name, scopeDepth, value]];
}
- (void)debuggerConnection:(UDScriptDebuggerConnection *)connection didReceiveScripts:(NSArray<NSString *> *)paths {
    [self hear:paths];
}

/// The bytes idBitMsg writes: a short, a bit, ints across byte bounds, a
/// string from the next whole byte, NUL-ended.
- (void)testMessagesAreTheBytesIdBitMsgWrites {
    UDBitMsg *message = [[UDBitMsg alloc] init];
    [message writeShort:UDScriptDebuggerAddBreakpoint];
    [message writeBits:0 numBits:1];
    [message writeInt:5];
    [message writeInt:2];
    [message writeString:@"a.script"];
    const uint8_t expected[] = { 0x04, 0x00, 0x0A, 0x00, 0x00, 0x00, 0x04, 0x00, 0x00, 0x00, 0x00,
                                 'a', '.', 's', 'c', 'r', 'i', 'p', 't', 0x00 };
    XCTAssertEqualObjects(message.data, [NSData dataWithBytes:expected length:sizeof expected]);

    UDBitMsg *inspect = [[UDBitMsg alloc] init];
    [inspect writeShort:UDScriptDebuggerInspectVariable];
    [inspect writeShort:-1];
    [inspect writeString:@"x"];
    const uint8_t variable[] = { 0x0B, 0x00, 0xFF, 0xFF, 'x', 0x00 };
    XCTAssertEqualObjects(inspect.data, [NSData dataWithBytes:variable length:sizeof variable]);

    UDBitMsg *read = [[UDBitMsg alloc] initWithData:[message.data mutableCopy]];
    XCTAssertEqual([read readShort], UDScriptDebuggerAddBreakpoint);
    XCTAssertEqual([read readBits:1], 0u);
    XCTAssertEqual([read readInt], 5);
    XCTAssertEqual([read readInt], 2);
    XCTAssertEqualObjects([read readString], @"a.script");
    XCTAssertEqual([read readShort], -1, @"past the end, as idBitMsg reads it");
    UDBitMsg *percent = [[UDBitMsg alloc] init];
    [percent writeString:@"100%"];
    XCTAssertEqualObjects([[[UDBitMsg alloc] initWithData:[percent.data mutableCopy]] readString], @"100.",
                          @"ReadString's '%' read as '.'");
}

/// rvDebuggerClient's half: it connects, sends what it asks, and hears
/// what the game sends.
- (void)testTheGameIsHeardAndAsked {
    uint16_t gamePort = [UDFakeScriptDebugger gamePort], debuggerPort = [UDFakeScriptDebugger debuggerPort];
    UDFakeScriptDebugger *game = [[UDFakeScriptDebugger alloc] initWithPort:gamePort debuggerPort:debuggerPort];
    XCTAssertNotNil(game);
    UDScriptDebuggerConnection *connection = [[UDScriptDebuggerConnection alloc] initWithHost:@"127.0.0.1" port:gamePort
                                                                                    localPort:debuggerPort queue:_queue];
    connection.delegate = self;
    NSError *error = nil;
    XCTAssertTrue([connection open:&error], @"%@", error);

    // DBMSG_CONNECT, answered
    [connection sendConnect];
    XCTAssertNotNil([game receiveType:UDScriptDebuggerConnect within:2]);
    [game send:[game message:UDScriptDebuggerConnected]];
    XCTAssertEqualObjects([self nextHeard], @"connected");
    XCTAssertTrue(connection.connected);
    // the game's own connect: answered with DBMSG_CONNECTED
    [game send:[game message:UDScriptDebuggerConnect]];
    XCTAssertEqualObjects([self nextHeard], @"connected");
    XCTAssertNotNil([game receiveType:UDScriptDebuggerConnected within:2]);

    // a breakpoint, as HandleAddBreakpoint reads it
    [connection addBreakpointAtLine:12 path:@"script/lamp.script" identifier:7 onceOnly:YES];
    UDBitMsg *add = [game receiveType:UDScriptDebuggerAddBreakpoint within:2];
    XCTAssertEqual([add readBits:1], 1u);
    XCTAssertEqual([add readInt], 12);
    XCTAssertEqual([add readInt], 7);
    XCTAssertEqualObjects([add readString], @"script/lamp.script");
    [connection inspectVariable:@"times" scopeDepth:2];
    UDBitMsg *inspect = [game receiveType:UDScriptDebuggerInspectVariable within:2];
    XCTAssertEqual([inspect readShort], 2);
    XCTAssertEqualObjects([inspect readString], @"times");
    [connection executeCommand:@"god"];
    XCTAssertEqualObjects([[game receiveType:UDScriptDebuggerExecCommand within:2] readString], @"god");

    // what the game sends, as rvDebuggerServer writes it
    UDBitMsg *broke = [game message:UDScriptDebuggerBreak];
    [broke writeInt:12];
    [broke writeString:@"script/lamp.script"];
    [game send:broke];
    XCTAssertEqualObjects([self nextHeard], @"break script/lamp.script:12");

    UDBitMsg *stack = [game message:UDScriptDebuggerInspectCallstack];
    [stack writeShort:2];
    [stack writeString:@"lamp::flicker(  )"];
    [stack writeString:@"script/lamp.script"];
    [stack writeInt:12];
    [stack writeString:@"main(  )"];
    [stack writeString:@"script/doom_main.script"];
    [stack writeInt:40];
    [game send:stack];
    NSArray<UDScriptStackFrame *> *frames = [self nextHeard];
    XCTAssertEqual(frames.count, 2u);
    XCTAssertEqualObjects(frames[1].function, @"main(  )");
    XCTAssertEqualObjects(frames[1].path, @"script/doom_main.script");
    XCTAssertEqual(frames[1].line, 40);

    UDBitMsg *threads = [game message:UDScriptDebuggerInspectThreads];
    [threads writeShort:2];
    [threads writeString:@"lamp_1"];
    [threads writeInt:3];
    [threads writeBits:1 numBits:1];
    [threads writeBits:0 numBits:1];
    [threads writeBits:0 numBits:1];
    [threads writeBits:0 numBits:1];
    [threads writeString:@"main"];
    [threads writeInt:1];
    [threads writeBits:0 numBits:1];
    [threads writeBits:0 numBits:1];
    [threads writeBits:1 numBits:1];
    [threads writeBits:0 numBits:1];
    [game send:threads];
    NSArray<UDScriptThreadInfo *> *heardThreads = [self nextHeard];
    XCTAssertEqual(heardThreads.count, 2u);
    XCTAssertEqualObjects(heardThreads[0].name, @"lamp_1");
    XCTAssertEqual(heardThreads[0].number, 3);
    XCTAssertTrue(heardThreads[0].current);
    XCTAssertTrue(heardThreads[1].waiting);
    XCTAssertFalse(heardThreads[1].current);

    UDBitMsg *value = [game message:UDScriptDebuggerInspectVariable];
    [value writeShort:2];
    [value writeString:@"times"];
    [value writeString:@"3"];
    [game send:value];
    XCTAssertEqualObjects([self nextHeard], @"times@2 = 3");

    UDBitMsg *removed = [game message:UDScriptDebuggerRemoveBreakpoint];
    [removed writeInt:13];
    [removed writeString:@"script/lamp.script"];
    [game send:removed];
    XCTAssertEqualObjects([self nextHeard], @"removed script/lamp.script:13");

    UDBitMsg *scripts = [game message:UDScriptDebuggerInspectScripts];
    [scripts writeInt:2];
    [scripts writeString:@"script/doom_main.script"];
    [scripts writeString:@"script/lamp.script"];
    [game send:scripts];
    XCTAssertEqualObjects([self nextHeard], (@[@"script/doom_main.script", @"script/lamp.script"]));

    UDBitMsg *print = [game message:UDScriptDebuggerPrint];
    [print writeString:@"lamp lit\n"];
    [game send:print];
    XCTAssertEqualObjects([self nextHeard], @"print lamp lit\n");
    [game send:[game message:UDScriptDebuggerResumed]];
    XCTAssertEqualObjects([self nextHeard], @"resumed");
    [game send:[game message:UDScriptDebuggerDisconnect]];
    XCTAssertEqualObjects([self nextHeard], @"disconnected");
    XCTAssertFalse(connection.connected);
    [connection close];
}

@end
