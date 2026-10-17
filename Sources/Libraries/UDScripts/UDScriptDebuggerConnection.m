//
//  UDScriptDebuggerConnection.m
//  UDCore
//

#import "UDScriptDebuggerConnection.h"
#import "UDBitMsg.h"

#include <arpa/inet.h>
#include <errno.h>
#include <fcntl.h>
#include <netdb.h>
#include <netinet/in.h>
#include <string.h>
#include <sys/socket.h>
#include <unistd.h>

@implementation UDScriptStackFrame

- (instancetype)initWithFunction:(NSString *)function path:(NSString *)path line:(int)line {
    if (!(self = [super init])) return nil;
    _function = [function copy];
    _path = [path copy];
    _line = line;
    return self;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"%@ %@:%d", _function, _path, _line];
}

@end

@implementation UDScriptThreadInfo

- (instancetype)initWithName:(NSString *)name number:(int)number current:(BOOL)current
              doneProcessing:(BOOL)doneProcessing waiting:(BOOL)waiting dying:(BOOL)dying {
    if (!(self = [super init])) return nil;
    _name = [name copy];
    _number = number;
    _current = current;
    _doneProcessing = doneProcessing;
    _waiting = waiting;
    _dying = dying;
    return self;
}

@end

@implementation UDScriptDebuggerConnection {
    NSString *_host;
    uint16_t _port;
    uint16_t _localPort;
    dispatch_queue_t _queue;
    int _socket;
    struct sockaddr_storage _address;
    socklen_t _addressLength;
    dispatch_source_t _source;
}

- (instancetype)initWithHost:(NSString *)host port:(uint16_t)port localPort:(uint16_t)localPort queue:(dispatch_queue_t)queue {
    if (!(self = [super init])) return nil;
    _host = [host copy];
    _port = port;
    _localPort = localPort;
    _queue = queue;
#if !OS_OBJECT_USE_OBJC
    dispatch_retain(queue);         // no object ARC keeps, where dispatch's are no Objective-C objects
#endif
    _socket = -1;
    return self;
}

- (void)dealloc {
    [self close];
#if !OS_OBJECT_USE_OBJC
    dispatch_release(_queue);
#endif
}

static NSError *UDSocketError(NSString *what) {
    return [NSError errorWithDomain:NSPOSIXErrorDomain code:errno
                           userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"%@: %s", what, strerror(errno)]}];
}

- (BOOL)open:(NSError **)error {
    if (_socket >= 0) return YES;
    // the game's address (Sys_StringToNetAdr's lookup)
    struct addrinfo hints = {0}, *found = NULL;
    hints.ai_family = AF_INET;
    hints.ai_socktype = SOCK_DGRAM;
    char port[8];
    snprintf(port, sizeof port, "%u", _port);
    if (getaddrinfo(_host.UTF8String, port, &hints, &found) != 0 || found == NULL) {
        if (error) *error = [NSError errorWithDomain:NSPOSIXErrorDomain code:EADDRNOTAVAIL
                                            userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"no such host: %@", _host]}];
        return NO;
    }
    memcpy(&_address, found->ai_addr, found->ai_addrlen);
    _addressLength = found->ai_addrlen;
    freeaddrinfo(found);

    int s = socket(AF_INET, SOCK_DGRAM, 0);
    if (s < 0) {
        if (error) *error = UDSocketError(@"socket");
        return NO;
    }
    int yes = 1;
    setsockopt(s, SOL_SOCKET, SO_REUSEADDR, &yes, sizeof yes);
    struct sockaddr_in local = {0};
    local.sin_family = AF_INET;
    local.sin_addr.s_addr = htonl(INADDR_ANY);
    local.sin_port = htons(_localPort);
    if (bind(s, (struct sockaddr *)&local, sizeof local) != 0) {
        if (error) *error = UDSocketError([NSString stringWithFormat:@"UDP port %u", _localPort]);
        close(s);
        return NO;
    }
    fcntl(s, F_SETFL, fcntl(s, F_GETFL) | O_NONBLOCK);
    _socket = s;

    _source = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, (uintptr_t)s, 0, _queue);
    __weak UDScriptDebuggerConnection *weakSelf = self;
    dispatch_source_set_event_handler(_source, ^{
        [weakSelf _readPackets];
    });
    dispatch_source_set_cancel_handler(_source, ^{
        close(s);
    });
    dispatch_resume(_source);
    return YES;
}

- (void)close {
    if (_source != nil) {
        dispatch_source_cancel(_source);
#if !OS_OBJECT_USE_OBJC
        dispatch_release(_source);
#endif
        _source = nil;
    } else if (_socket >= 0) {
        close(_socket);
    }
    _socket = -1;
    _connected = NO;
}

#pragma mark - Sending (rvDebuggerClient::SendMessage, SendPacket)

- (void)_send:(UDBitMsg *)message {
    if (_socket < 0) return;
    sendto(_socket, message.data.bytes, message.data.length, 0, (struct sockaddr *)&_address, _addressLength);
}

+ (UDBitMsg *)_message:(UDScriptDebuggerMessage)type {
    UDBitMsg *message = [[UDBitMsg alloc] init];
    [message writeShort:type];
    return message;
}

+ (NSData *)messageWithType:(UDScriptDebuggerMessage)type {
    return [self _message:type].data;
}

- (void)_sendType:(UDScriptDebuggerMessage)type {
    [self _send:[[self class] _message:type]];
}

- (void)sendConnect { [self _sendType:UDScriptDebuggerConnect]; }
- (void)resume { [self _sendType:UDScriptDebuggerResume]; }
- (void)breakNext { [self _sendType:UDScriptDebuggerBreak]; }
- (void)stepOver { [self _sendType:UDScriptDebuggerStepOver]; }
- (void)stepInto { [self _sendType:UDScriptDebuggerStepInto]; }
- (void)inspectCallstack { [self _sendType:UDScriptDebuggerInspectCallstack]; }
- (void)inspectThreads { [self _sendType:UDScriptDebuggerInspectThreads]; }
- (void)inspectScripts { [self _sendType:UDScriptDebuggerInspectScripts]; }

- (void)sendDisconnect {
    [self _sendType:UDScriptDebuggerDisconnect];
    _connected = NO;
}

/// rvDebuggerClient::SendAddBreakpoint.
- (void)addBreakpointAtLine:(int)line path:(NSString *)path identifier:(int)identifier onceOnly:(BOOL)onceOnly {
    UDBitMsg *message = [[self class] _message:UDScriptDebuggerAddBreakpoint];
    [message writeBits:onceOnly ? 1 : 0 numBits:1];
    [message writeInt:line];
    [message writeInt:identifier];
    [message writeString:path];
    [self _send:message];
}

- (void)removeBreakpoint:(int)identifier {
    UDBitMsg *message = [[self class] _message:UDScriptDebuggerRemoveBreakpoint];
    [message writeInt:identifier];
    [self _send:message];
}

- (void)inspectVariable:(NSString *)name scopeDepth:(int)scopeDepth {
    UDBitMsg *message = [[self class] _message:UDScriptDebuggerInspectVariable];
    [message writeShort:scopeDepth];
    [message writeString:name];
    [self _send:message];
}

- (void)executeCommand:(NSString *)command {
    UDBitMsg *message = [[self class] _message:UDScriptDebuggerExecCommand];
    [message writeString:command];
    [self _send:message];
}

#pragma mark - Receiving (rvDebuggerClient::ProcessMessages)

- (void)_readPackets {
    uint8_t buffer[65536];
    for (;;) {
        ssize_t length = recv(_socket, buffer, sizeof buffer, 0);
        if (length <= 0) return;
        [self _handle:[UDBitMsg.alloc initWithData:[NSMutableData dataWithBytes:buffer length:(NSUInteger)length]]];
    }
}

- (void)_handle:(UDBitMsg *)message {
    id<UDScriptDebuggerConnectionDelegate> delegate = self.delegate;
    switch ((UDScriptDebuggerMessage)[message readShort]) {
        case UDScriptDebuggerConnect:
            _connected = YES;
            [self _sendType:UDScriptDebuggerConnected];
            if ([delegate respondsToSelector:@selector(debuggerConnectionDidConnect:)]) [delegate debuggerConnectionDidConnect:self];
            break;
        case UDScriptDebuggerConnected:
            _connected = YES;
            if ([delegate respondsToSelector:@selector(debuggerConnectionDidConnect:)]) [delegate debuggerConnectionDidConnect:self];
            break;
        case UDScriptDebuggerDisconnect:
            _connected = NO;
            if ([delegate respondsToSelector:@selector(debuggerConnectionDidDisconnect:)]) [delegate debuggerConnectionDidDisconnect:self];
            break;
        case UDScriptDebuggerBreak: {
            int line = [message readInt];
            NSString *path = [message readString];
            if ([delegate respondsToSelector:@selector(debuggerConnection:didBreakAtLine:path:)]) {
                [delegate debuggerConnection:self didBreakAtLine:line path:path];
            }
            break;
        }
        case UDScriptDebuggerResumed:
            if ([delegate respondsToSelector:@selector(debuggerConnectionDidResume:)]) [delegate debuggerConnectionDidResume:self];
            break;
        case UDScriptDebuggerPrint: {
            NSString *text = [message readString];
            if ([delegate respondsToSelector:@selector(debuggerConnection:didPrint:)]) [delegate debuggerConnection:self didPrint:text];
            break;
        }
        case UDScriptDebuggerRemoveBreakpoint: {
            int line = [message readInt];
            NSString *path = [message readString];
            if ([delegate respondsToSelector:@selector(debuggerConnection:didRemoveBreakpointAtLine:path:)]) {
                [delegate debuggerConnection:self didRemoveBreakpointAtLine:line path:path];
            }
            break;
        }
        case UDScriptDebuggerInspectCallstack: {
            NSMutableArray<UDScriptStackFrame *> *frames = [NSMutableArray array];
            for (int depth = (short)[message readShort]; depth > 0; depth--) {
                NSString *function = [message readString];
                NSString *path = [message readString];
                int line = [message readInt];
                [frames addObject:[[UDScriptStackFrame alloc] initWithFunction:function path:path line:line]];
            }
            if ([delegate respondsToSelector:@selector(debuggerConnection:didReceiveCallstack:)]) {
                [delegate debuggerConnection:self didReceiveCallstack:frames];
            }
            break;
        }
        case UDScriptDebuggerInspectThreads: {
            NSMutableArray<UDScriptThreadInfo *> *threads = [NSMutableArray array];
            for (int count = (short)[message readShort]; count > 0; count--) {
                NSString *name = [message readString];
                int number = [message readInt];
                BOOL current = [message readBits:1] != 0;
                BOOL done = [message readBits:1] != 0;
                BOOL waiting = [message readBits:1] != 0;
                BOOL dying = [message readBits:1] != 0;
                [threads addObject:[[UDScriptThreadInfo alloc] initWithName:name number:number current:current
                                                             doneProcessing:done waiting:waiting dying:dying]];
            }
            if ([delegate respondsToSelector:@selector(debuggerConnection:didReceiveThreads:)]) {
                [delegate debuggerConnection:self didReceiveThreads:threads];
            }
            break;
        }
        case UDScriptDebuggerInspectVariable: {
            int depth = (short)[message readShort];
            NSString *name = [message readString];
            NSString *value = [message readString];
            if ([delegate respondsToSelector:@selector(debuggerConnection:didReceiveValue:variable:scopeDepth:)]) {
                [delegate debuggerConnection:self didReceiveValue:value variable:name scopeDepth:depth];
            }
            break;
        }
        case UDScriptDebuggerInspectScripts: {
            NSMutableArray<NSString *> *paths = [NSMutableArray array];
            for (int count = [message readInt]; count > 0; count--) {
                [paths addObject:[message readString]];
            }
            if ([delegate respondsToSelector:@selector(debuggerConnection:didReceiveScripts:)]) {
                [delegate debuggerConnection:self didReceiveScripts:paths];
            }
            break;
        }
        default:
            break;
    }
}

@end
