//
//  UDFakeScriptDebugger.m
//  UDQuakeToolsTests
//

#import "UDFakeScriptDebugger.h"

#include <arpa/inet.h>
#include <netinet/in.h>
#include <poll.h>
#include <sys/socket.h>
#include <unistd.h>

@implementation UDFakeScriptDebugger {
    int _socket;
    uint16_t _debuggerPort;
}

// Away from the game's own (27980, 27981), and from another test run's.
+ (uint16_t)gamePort {
    return (uint16_t)(41000 + (getpid() % 2000) * 2);
}

+ (uint16_t)debuggerPort {
    return (uint16_t)([self gamePort] + 1);
}

- (instancetype)initWithPort:(uint16_t)port debuggerPort:(uint16_t)debuggerPort {
    if (!(self = [super init])) return nil;
    _debuggerPort = debuggerPort;
    _socket = socket(AF_INET, SOCK_DGRAM, 0);
    int yes = 1;
    setsockopt(_socket, SOL_SOCKET, SO_REUSEADDR, &yes, sizeof yes);
    struct sockaddr_in address = {0};
    address.sin_family = AF_INET;
    address.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    address.sin_port = htons(port);
    if (_socket < 0 || bind(_socket, (struct sockaddr *)&address, sizeof address) != 0) {
        if (_socket >= 0) close(_socket);
        return nil;
    }
    return self;
}

- (void)dealloc {
    if (_socket >= 0) close(_socket);
}

- (UDBitMsg *)receiveWithin:(NSTimeInterval)timeout type:(int *)type {
    struct pollfd wanted = { _socket, POLLIN, 0 };
    if (poll(&wanted, 1, (int)(timeout * 1000)) <= 0) return nil;
    uint8_t buffer[65536];
    ssize_t length = recv(_socket, buffer, sizeof buffer, 0);
    if (length <= 0) return nil;
    UDBitMsg *message = [[UDBitMsg alloc] initWithData:[NSMutableData dataWithBytes:buffer length:(NSUInteger)length]];
    int read = [message readShort];
    if (type != NULL) *type = read;
    return message;
}

- (UDBitMsg *)receiveType:(int)type within:(NSTimeInterval)timeout {
    NSDate *until = [NSDate dateWithTimeIntervalSinceNow:timeout];
    while (until.timeIntervalSinceNow > 0) {
        int got = -1;
        UDBitMsg *message = [self receiveWithin:until.timeIntervalSinceNow type:&got];
        if (message == nil) return nil;
        if (got == type) return message;
    }
    return nil;
}

- (UDBitMsg *)message:(int)type {
    UDBitMsg *message = [[UDBitMsg alloc] init];
    [message writeShort:type];
    return message;
}

- (void)send:(UDBitMsg *)message {
    struct sockaddr_in address = {0};
    address.sin_family = AF_INET;
    address.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    address.sin_port = htons(_debuggerPort);
    sendto(_socket, message.data.bytes, message.data.length, 0, (struct sockaddr *)&address, sizeof address);
}

@end
