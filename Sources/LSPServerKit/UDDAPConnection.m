//
//  UDDAPConnection.m
//  UDCore
//

#import "UDDAPConnection.h"
#import "UDJSONRPCConnection.h"

@interface UDDAPConnection ()
- (void)_send:(NSMutableDictionary *)message;
@end

@interface UDDAPRequest ()
- (instancetype)initWithMessage:(NSDictionary *)message connection:(UDDAPConnection *)connection;
@end

@implementation UDDAPRequest {
    __weak UDDAPConnection *_connection;
}

- (instancetype)initWithMessage:(NSDictionary *)message connection:(UDDAPConnection *)connection {
    if (!(self = [super init])) return nil;
    _command = [message[@"command"] copy];
    id arguments = message[@"arguments"];
    _arguments = [arguments isKindOfClass:[NSDictionary class]] ? [arguments copy] : @{};
    _seq = [message[@"seq"] integerValue];
    _connection = connection;
    return self;
}

- (void)_answer:(BOOL)success body:(NSDictionary *)body message:(NSString *)message {
    if (_answered) return;
    _answered = YES;
    NSMutableDictionary *response = [@{ @"type": @"response", @"request_seq": @(_seq), @"success": @(success),
                                        @"command": _command ?: @"" } mutableCopy];
    if (body != nil) response[@"body"] = body;
    if (message != nil) response[@"message"] = message;
    [_connection _send:response];
}

- (void)respondWithBody:(NSDictionary *)body {
    [self _answer:YES body:body message:nil];
}

- (void)failWithMessage:(NSString *)message {
    [self _answer:NO body:@{ @"error": @{ @"id": @1, @"format": message ?: @"" } } message:message];
}

@end

@implementation UDDAPConnection {
    __weak id _target;
    dispatch_queue_t _queue;
    FILE *_output;
    NSMutableDictionary<NSString *, NSString *> *_actions;
    NSInteger _seq;
}

- (instancetype)initWithTarget:(id)target queue:(dispatch_queue_t)queue output:(FILE *)output {
    if (!(self = [super init])) return nil;
    _target = target;
    _queue = queue;
#if !OS_OBJECT_USE_OBJC
    dispatch_retain(queue);
#endif
    _output = output;
    _actions = [NSMutableDictionary dictionary];
    return self;
}

#if !OS_OBJECT_USE_OBJC
- (void)dealloc {
    dispatch_release(_queue);
}
#endif

- (void)setRequestAction:(SEL)action forCommand:(NSString *)command {
    _actions[command] = NSStringFromSelector(action);
}

- (void)_send:(NSMutableDictionary *)message {
    @synchronized (self) {
        message[@"seq"] = @(++_seq);
        [UDJSONRPCConnection writeMessage:message toFile:_output];
    }
}

- (void)sendEvent:(NSString *)event body:(NSDictionary *)body {
    NSMutableDictionary *message = [@{ @"type": @"event", @"event": event } mutableCopy];
    if (body != nil) message[@"body"] = body;
    [self _send:message];
}

- (void)handleMessage:(NSDictionary *)message {
    if (![message[@"type"] isEqual:@"request"] || ![message[@"command"] isKindOfClass:[NSString class]]) return;
    UDDAPRequest *request = [[UDDAPRequest alloc] initWithMessage:message connection:self];
    NSString *action = _actions[request.command];
    id target = _target;
    if (action == nil || target == nil) {
        [request failWithMessage:[NSString stringWithFormat:@"%@ is not supported", request.command]];
        return;
    }
    SEL selector = NSSelectorFromString(action);
    void (*handle)(id, SEL, UDDAPRequest *) = (void (*)(id, SEL, UDDAPRequest *))[target methodForSelector:selector];
    @try {
        handle(target, selector, request);
    } @catch (NSException *exception) {
        [request failWithMessage:[NSString stringWithFormat:@"%@: %@", request.command, exception.reason]];
    }
}

- (void)startReadingInput:(FILE *)input {
    NSThread *reader = [[NSThread alloc] initWithTarget:self selector:@selector(_read:)
                                                 object:[NSValue valueWithPointer:input]];
    [reader start];
}

/// The reading thread: each message on to the queue, then the close.
- (void)_read:(NSValue *)file {
    FILE *input = file.pointerValue;
    for (;;) {
        @autoreleasepool {
            NSData *body = [UDJSONRPCConnection readMessageFromFile:input];
            if (body == nil) break;
            NSDictionary *message = [NSJSONSerialization JSONObjectWithData:body options:0 error:NULL];
            if (![message isKindOfClass:[NSDictionary class]]) continue;
            dispatch_async(_queue, ^{
                [self handleMessage:message];
            });
        }
    }
    dispatch_async(_queue, ^{
        id target = self.closeTarget;
        SEL close = self.closeAction;
        if (target != nil && close != NULL && [target respondsToSelector:close]) {
            void (*closed)(id, SEL, UDDAPConnection *) = (void (*)(id, SEL, UDDAPConnection *))[target methodForSelector:close];
            closed(target, close, self);
        }
    });
}

@end
