//
//  UDFakeScriptDebugger.m
//  UDQuakeToolsTests
//

#import "UDFakeScriptDebugger.h"
#import "UDDatagramSocket.h"

@implementation UDFakeScriptDebugger {
    UDDatagramSocket _socket;
    NSData *_debugger;
}

// Away from the game's own (27980, 27981), and from another test run's.
+ (uint16_t)gamePort {
    return (uint16_t)(41000 + ([NSProcessInfo processInfo].processIdentifier % 2000) * 2);
}

+ (uint16_t)debuggerPort {
    return (uint16_t)([self gamePort] + 1);
}

- (instancetype)initWithPort:(uint16_t)port debuggerPort:(uint16_t)debuggerPort {
    if (!(self = [super init])) return nil;
    _debugger = UDDatagramAddress(@"127.0.0.1", debuggerPort);
    _socket = UDDatagramOpen(port, NULL);
    if (_socket == UDDatagramNone) return nil;
    return self;
}

- (void)dealloc {
    if (_socket != UDDatagramNone) UDDatagramClose(_socket);
}

- (UDBitMsg *)receiveWithin:(NSTimeInterval)timeout type:(int *)type {
    if (!UDDatagramWait(_socket, timeout)) return nil;
    NSData *packet = UDDatagramReceive(_socket);
    if (!packet) return nil;
    UDBitMsg *message = [[UDBitMsg alloc] initWithData:[packet mutableCopy]];
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
    UDDatagramSend(_socket, _debugger, message.data);
}

@end
