//
//  UDDAPConnectionTests.m
//  UDQuakeToolsTests
//

#import <XCTest/XCTest.h>
#import "UDDAPConnection.h"
#import "UDJSONRPCConnection.h"

#include <poll.h>
#include <unistd.h>

@interface UDDAPConnectionTests : XCTestCase
@property (nonatomic, strong, nullable) UDDAPRequest *held;
@end

@implementation UDDAPConnectionTests {
    FILE *_written;     // what the connection writes
    FILE *_reading;     // the test's end of it
}

- (void)setUp {
    [super setUp];
    int fds[2];
    XCTAssertEqual(pipe(fds), 0);
    _reading = fdopen(fds[0], "r");
    setvbuf(_reading, NULL, _IONBF, 0);
    _written = fdopen(fds[1], "w");
}

- (void)tearDown {
    fclose(_written);
    fclose(_reading);
    [super tearDown];
}

/// The next message written, or nil within a second.
- (NSDictionary *)nextMessage {
    struct pollfd wanted = { fileno(_reading), POLLIN, 0 };
    if (poll(&wanted, 1, 1000) <= 0) return nil;
    NSData *body = [UDJSONRPCConnection readMessageFromFile:_reading];
    return body ? [NSJSONSerialization JSONObjectWithData:body options:0 error:NULL] : nil;
}

- (void)answerNow:(UDDAPRequest *)request {
    [request respondWithBody:@{ @"echo": request.arguments[@"text"] ?: @"" }];
}

- (void)answerLater:(UDDAPRequest *)request {
    self.held = request;
}

- (void)raise:(UDDAPRequest *)request {
    [NSException raise:NSInternalInconsistencyException format:@"broken"];
}

- (void)testRequestsAreAnsweredNowOrLaterAndEventsSent {
    UDDAPConnection *connection = [[UDDAPConnection alloc] initWithTarget:self queue:dispatch_get_main_queue() output:_written];
    [connection setRequestAction:@selector(answerNow:) forCommand:@"echo"];
    [connection setRequestAction:@selector(answerLater:) forCommand:@"later"];
    [connection setRequestAction:@selector(raise:) forCommand:@"broken"];

    [connection handleMessage:@{ @"seq": @1, @"type": @"request", @"command": @"echo", @"arguments": @{ @"text": @"hi" } }];
    NSDictionary *response = [self nextMessage];
    XCTAssertEqualObjects(response[@"type"], @"response");
    XCTAssertEqualObjects(response[@"request_seq"], @1);
    XCTAssertEqualObjects(response[@"command"], @"echo");
    XCTAssertEqualObjects(response[@"success"], @YES);
    XCTAssertEqualObjects(response[@"body"][@"echo"], @"hi");
    XCTAssertEqualObjects(response[@"seq"], @1, @"the adapter's own sequence");

    [connection handleMessage:@{ @"seq": @2, @"type": @"request", @"command": @"later" }];
    XCTAssertNil([self nextMessage], @"not answered yet");
    [connection sendEvent:@"stopped" body:@{ @"reason": @"pause" }];
    NSDictionary *event = [self nextMessage];
    XCTAssertEqualObjects(event[@"type"], @"event");
    XCTAssertEqualObjects(event[@"event"], @"stopped");
    XCTAssertEqualObjects(event[@"body"][@"reason"], @"pause");
    [self.held respondWithBody:nil];
    [self.held failWithMessage:@"twice"];
    NSDictionary *later = [self nextMessage];
    XCTAssertEqualObjects(later[@"request_seq"], @2);
    XCTAssertEqualObjects(later[@"success"], @YES);
    XCTAssertNil([self nextMessage], @"answered once");

    [connection handleMessage:@{ @"seq": @3, @"type": @"request", @"command": @"stepBack" }];
    NSDictionary *unsupported = [self nextMessage];
    XCTAssertEqualObjects(unsupported[@"success"], @NO);
    XCTAssertTrue([unsupported[@"message"] containsString:@"stepBack"], @"%@", unsupported);
    [connection handleMessage:@{ @"seq": @4, @"type": @"request", @"command": @"broken" }];
    NSDictionary *raised = [self nextMessage];
    XCTAssertEqualObjects(raised[@"success"], @NO);
    XCTAssertTrue([raised[@"message"] containsString:@"broken"], @"%@", raised);
}

@end
