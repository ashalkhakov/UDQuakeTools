//
//  UDScriptDebuggerConnection.m
//  UDCore
//

#import "UDScriptDebuggerConnection.h"
#import "UDBitMsg.h"
#import "UDDatagramSocket.h"

#include <errno.h>

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

@implementation UDScriptVariableInfo

- (instancetype)initWithName:(NSString *)name value:(NSString *)value kind:(UDScriptVariableKind)kind {
    if (!(self = [super init])) return nil;
    _name = [name copy];
    _value = [value copy];
    _kind = kind;
    return self;
}

- (instancetype)initWithName:(NSString *)name value:(NSString *)value field:(BOOL)field {
    return [self initWithName:name value:value kind:field ? UDScriptVariableField : UDScriptVariableLocal];
}

- (BOOL)isField {
    return _kind == UDScriptVariableField;
}

@end

@implementation UDScriptDebuggerConnection {
    NSString *_host;
    uint16_t _port;
    uint16_t _localPort;
    dispatch_queue_t _queue;
    UDDatagramSocket _socket;
    NSData *_address;
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
    _socket = UDDatagramNone;
    return self;
}

- (void)dealloc {
    [self close];
#if !OS_OBJECT_USE_OBJC
    dispatch_release(_queue);
#endif
}

- (BOOL)open:(NSError **)error {
    if (_socket != UDDatagramNone) return YES;
    // the game's address (Sys_StringToNetAdr's lookup)
    _address = UDDatagramAddress(_host, _port);
    if (!_address) {
        if (error) *error = [NSError errorWithDomain:NSPOSIXErrorDomain code:EADDRNOTAVAIL
                                            userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"no such host: %@", _host]}];
        return NO;
    }
    UDDatagramSocket s = UDDatagramOpen(_localPort, error);
    if (s == UDDatagramNone) return NO;
    _socket = s;

    _source = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, (uintptr_t)s, 0, _queue);
    __weak UDScriptDebuggerConnection *weakSelf = self;
    dispatch_source_set_event_handler(_source, ^{
        [weakSelf _readPackets];
    });
    dispatch_source_set_cancel_handler(_source, ^{
        UDDatagramClose(s);
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
    } else if (_socket != UDDatagramNone) {
        UDDatagramClose(_socket);
    }
    _socket = UDDatagramNone;
    _connected = NO;
}

#pragma mark - Sending (rvDebuggerClient::SendMessage, SendPacket)

- (void)_send:(UDBitMsg *)message {
    if (_socket == UDDatagramNone) return;
    UDDatagramSend(_socket, _address, message.data);
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
- (void)stepOut { [self _sendType:UDScriptDebuggerStepOut]; }

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

- (void)setBreakOnErrors:(UDScriptDebuggerErrorFlags)flags {
    UDBitMsg *message = [[self class] _message:UDScriptDebuggerBreakOnErrors];
    [message writeInt:flags];
    [self _send:message];
}

- (void)inspectCallstackOfThread:(int)number {
    UDBitMsg *message = [[self class] _message:UDScriptDebuggerInspectThreadCallstack];
    [message writeInt:number];
    [self _send:message];
}

- (void)inspectVariablesOfThread:(int)number scopeDepth:(int)scopeDepth {
    UDBitMsg *message = [[self class] _message:UDScriptDebuggerInspectVariables];
    [message writeInt:number];
    [message writeShort:scopeDepth];
    [self _send:message];
}

- (void)inspectEntity:(NSString *)name {
    UDBitMsg *message = [[self class] _message:UDScriptDebuggerInspectEntity];
    [message writeString:name];
    [self _send:message];
}

- (void)setVariable:(NSString *)name value:(NSString *)value thread:(int)number scopeDepth:(int)scopeDepth {
    UDBitMsg *message = [[self class] _message:UDScriptDebuggerSetVariable];
    [message writeInt:number];
    [message writeShort:scopeDepth];
    [message writeString:name];
    [message writeString:value];
    [self _send:message];
}

- (void)setNextStatementLine:(int)line {
    UDBitMsg *message = [[self class] _message:UDScriptDebuggerSetNextStatement];
    [message writeInt:line];
    [self _send:message];
}

/// MSG_WriteInterpreterInfo's: a short depth, then each frame.
static NSArray<UDScriptStackFrame *> *UDReadFrames(UDBitMsg *message) {
    NSMutableArray<UDScriptStackFrame *> *frames = [NSMutableArray array];
    for (int depth = (short)[message readShort]; depth > 0; depth--) {
        NSString *function = [message readString];
        NSString *path = [message readString];
        int line = [message readInt];
        [frames addObject:[[UDScriptStackFrame alloc] initWithFunction:function path:path line:line]];
    }
    return frames;
}

/// A short count, then each one's name, value and kind (a byte).
static NSArray<UDScriptVariableInfo *> *UDReadVariables(UDBitMsg *message) {
    NSMutableArray<UDScriptVariableInfo *> *variables = [NSMutableArray array];
    for (int count = (short)[message readShort]; count > 0; count--) {
        NSString *name = [message readString];
        NSString *value = [message readString];
        UDScriptVariableKind kind = (UDScriptVariableKind)[message readBits:8];
        [variables addObject:[[UDScriptVariableInfo alloc] initWithName:name value:value kind:kind]];
    }
    return variables;
}

#pragma mark - Receiving (rvDebuggerClient::ProcessMessages)

- (void)_readPackets {
    NSData *packet;
    while ((packet = UDDatagramReceive(_socket))) {
        [self _handle:[UDBitMsg.alloc initWithData:[packet mutableCopy]]];
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
            NSArray<UDScriptStackFrame *> *frames = UDReadFrames(message);
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
        case UDScriptDebuggerVersion: {
            int version = [message readInt];
            int capabilities = [message readInt];
            if ([delegate respondsToSelector:@selector(debuggerConnection:didReceiveVersion:capabilities:)]) {
                [delegate debuggerConnection:self didReceiveVersion:version capabilities:capabilities];
            }
            break;
        }

        case UDScriptDebuggerScriptError: {
            BOOL isError = [message readBits:8] != 0;
            NSString *text = [message readString];
            if ([delegate respondsToSelector:@selector(debuggerConnection:didStopAtScriptError:isError:)]) {
                [delegate debuggerConnection:self didStopAtScriptError:text isError:isError];
            }
            break;
        }
        case UDScriptDebuggerInspectThreadCallstack: {
            int number = [message readInt];
            NSArray<UDScriptStackFrame *> *frames = UDReadFrames(message);
            if ([delegate respondsToSelector:@selector(debuggerConnection:didReceiveCallstack:thread:)]) {
                [delegate debuggerConnection:self didReceiveCallstack:frames thread:number];
            }
            break;
        }
        case UDScriptDebuggerInspectVariables: {
            int number = [message readInt];
            int depth = (short)[message readShort];
            NSArray<UDScriptVariableInfo *> *variables = UDReadVariables(message);
            if ([delegate respondsToSelector:@selector(debuggerConnection:didReceiveVariables:scopeDepth:thread:)]) {
                [delegate debuggerConnection:self didReceiveVariables:variables scopeDepth:depth thread:number];
            }
            break;
        }
        case UDScriptDebuggerInspectEntity: {
            NSString *name = [message readString];
            NSArray<UDScriptVariableInfo *> *variables = UDReadVariables(message);
            if ([delegate respondsToSelector:@selector(debuggerConnection:didReceiveEntity:variables:)]) {
                [delegate debuggerConnection:self didReceiveEntity:name variables:variables];
            }
            break;
        }
        case UDScriptDebuggerSetVariable: {
            int number = [message readInt];
            int depth = (short)[message readShort];
            NSString *name = [message readString];
            BOOL set = [message readBits:8] != 0;
            NSString *value = [message readString];
            if ([delegate respondsToSelector:@selector(debuggerConnection:didSetVariable:thread:scopeDepth:set:value:)]) {
                [delegate debuggerConnection:self didSetVariable:name thread:number scopeDepth:depth set:set value:value];
            }
            break;
        }
        case UDScriptDebuggerSetNextStatement: {
            int line = [message readInt];
            if ([delegate respondsToSelector:@selector(debuggerConnection:didSetNextStatementLine:)]) {
                [delegate debuggerConnection:self didSetNextStatementLine:line];
            }
            break;
        }
        default:
            break;
    }
}

@end
