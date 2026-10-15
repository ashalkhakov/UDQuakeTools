//
//  UDJSONRPCConnectionTests.m
//  UDQuakeToolsTests
//

#import <XCTest/XCTest.h>
#import "UDJSONRPCConnection.h"

@interface UDJSONRPCConnectionTests : XCTestCase
@property (nonatomic, strong) UDJSONRPCConnection *connection;
@property (nonatomic, copy) NSArray *notified;
@end

@implementation UDJSONRPCConnectionTests

- (void)setUp {
    [super setUp];
    self.notified = @[];
    self.connection = [[UDJSONRPCConnection alloc] initWithTarget:self];
    [self.connection setRequestAction:@selector(sum:) forMethod:@"sum"];
    [self.connection setRequestAction:@selector(refuse:) forMethod:@"refuse"];
    [self.connection setNotificationAction:@selector(note:) forMethod:@"note"];
    [self.connection setRequestAction:@selector(fail:) forMethod:@"fail"];
}

- (id)fail:(NSDictionary *)params {
    [NSException raise:NSInvalidArgumentException format:@"broken"];
    return nil;
}

- (id)sum:(NSDictionary *)params {
    return @([params[@"a"] integerValue] + [params[@"b"] integerValue]);
}

- (id)refuse:(NSDictionary *)params {
    return [NSError errorWithDomain:UDJSONRPCErrorDomain code:UDJSONRPCInvalidParams
                           userInfo:@{ NSLocalizedDescriptionKey: @"no thanks" }];
}

- (void)note:(NSDictionary *)params {
    self.notified = [self.notified arrayByAddingObject:params[@"text"] ?: @""];
}

- (void)testARequestIsAnsweredByItsAction {
    NSDictionary *reply = [self.connection replyToMessage:@{ @"jsonrpc": @"2.0", @"id": @3, @"method": @"sum",
                                                             @"params": @{ @"a": @2, @"b": @5 } }];
    XCTAssertEqualObjects(reply, (@{ @"jsonrpc": @"2.0", @"id": @3, @"result": @7 }));

    reply = [self.connection replyToMessage:@{ @"jsonrpc": @"2.0", @"id": @"x", @"method": @"refuse" }];
    XCTAssertEqualObjects(reply[@"id"], @"x");
    XCTAssertEqualObjects(reply[@"error"], (@{ @"code": @(UDJSONRPCInvalidParams), @"message": @"no thanks" }));

    reply = [self.connection replyToMessage:@{ @"jsonrpc": @"2.0", @"id": @4, @"method": @"divide" }];
    XCTAssertEqualObjects(reply[@"error"][@"code"], @(UDJSONRPCMethodNotFound));

    // A request whose action raises is answered, and the server goes on.
    reply = [self.connection replyToMessage:@{ @"jsonrpc": @"2.0", @"id": @5, @"method": @"fail" }];
    XCTAssertEqualObjects(reply[@"error"][@"code"], @(UDJSONRPCInternalError));
    XCTAssertTrue([reply[@"error"][@"message"] containsString:@"broken"]);
}

- (void)testANotificationIsHandedOverAndNotAnswered {
    NSDictionary *reply = [self.connection replyToMessage:@{ @"jsonrpc": @"2.0", @"method": @"note", @"params": @{ @"text": @"hi" } }];
    XCTAssertNil(reply);
    reply = [self.connection replyToMessage:@{ @"jsonrpc": @"2.0", @"method": @"unheard" }];
    XCTAssertNil(reply);
    XCTAssertEqualObjects(self.notified, @[ @"hi" ]);
}

static NSString *UDFramed(NSString *body) {
    return [NSString stringWithFormat:@"Content-Length: %lu\r\n\r\n%@", (unsigned long)[body lengthOfBytesUsingEncoding:NSUTF8StringEncoding], body];
}

- (void)testMessagesAreReadAndAnsweredFramed {
    NSString *input = [@[ UDFramed(@"{\"jsonrpc\":\"2.0\",\"method\":\"note\",\"params\":{\"text\":\"été\"}}"),
                          UDFramed(@"{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"sum\",\"params\":{\"a\":1,\"b\":1}}"),
                          UDFramed(@"{oops") ] componentsJoinedByString:@""];
    NSData *bytes = [input dataUsingEncoding:NSUTF8StringEncoding];
    FILE *in = fmemopen((void *)bytes.bytes, bytes.length, "r");
    char *written = NULL;
    size_t writtenLength = 0;
    FILE *out = open_memstream(&written, &writtenLength);

    [self.connection runWithInput:in output:out];
    fclose(in);
    fclose(out);

    XCTAssertEqualObjects(self.notified, @[ @"été" ]);
    NSData *output = [NSData dataWithBytes:written length:writtenLength];
    free(written);
    in = fmemopen((void *)output.bytes, output.length, "r");
    NSDictionary *first = [NSJSONSerialization JSONObjectWithData:[UDJSONRPCConnection readMessageFromFile:in] options:0 error:NULL];
    NSDictionary *second = [NSJSONSerialization JSONObjectWithData:[UDJSONRPCConnection readMessageFromFile:in] options:0 error:NULL];
    XCTAssertNil([UDJSONRPCConnection readMessageFromFile:in]);
    fclose(in);
    XCTAssertEqualObjects(first[@"result"], @2);
    XCTAssertEqualObjects(second[@"error"][@"code"], @(UDJSONRPCParseError));
}

@end
