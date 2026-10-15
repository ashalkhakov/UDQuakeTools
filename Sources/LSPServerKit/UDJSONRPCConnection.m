//
//  UDJSONRPCConnection.m
//  UDCore
//

#import "UDJSONRPCConnection.h"

NSErrorDomain const UDJSONRPCErrorDomain = @"UDJSONRPCErrorDomain";

@implementation UDJSONRPCConnection {
    __weak id _target;
    NSMutableDictionary<NSString *, NSString *> *_requestActions;
    NSMutableDictionary<NSString *, NSString *> *_notificationActions;
    BOOL _stopped;
}

- (instancetype)initWithTarget:(id)target {
    if (!(self = [super init])) return nil;
    _target = target;
    _requestActions = [NSMutableDictionary dictionary];
    _notificationActions = [NSMutableDictionary dictionary];
    return self;
}

- (void)setRequestAction:(SEL)action forMethod:(NSString *)method {
    _requestActions[method] = NSStringFromSelector(action);
}

- (void)setNotificationAction:(SEL)action forMethod:(NSString *)method {
    _notificationActions[method] = NSStringFromSelector(action);
}

static NSDictionary *UDErrorResponse(id identifier, NSInteger code, NSString *message) {
    return @{ @"jsonrpc": @"2.0", @"id": identifier ?: [NSNull null],
              @"error": @{ @"code": @(code), @"message": message ?: @"" } };
}

- (NSDictionary *)replyToMessage:(NSDictionary *)message {
    NSString *method = message[@"method"];
    id identifier = message[@"id"];
    id params = message[@"params"];
    if (![params isKindOfClass:[NSDictionary class]]) params = @{};
    if (![method isKindOfClass:[NSString class]]) {
        return identifier ? UDErrorResponse(identifier, UDJSONRPCInvalidRequest, @"no method") : nil;
    }

    if (identifier == nil) {                                  // a notification
        NSString *action = _notificationActions[method];
        if (action != nil) {
            SEL selector = NSSelectorFromString(action);
            void (*notify)(id, SEL, NSDictionary *) = (void (*)(id, SEL, NSDictionary *))[_target methodForSelector:selector];
            notify(_target, selector, params);
        }
        return nil;
    }

    NSString *action = _requestActions[method];
    if (action == nil) {
        return UDErrorResponse(identifier, UDJSONRPCMethodNotFound, [NSString stringWithFormat:@"%@: no such method", method]);
    }
    SEL selector = NSSelectorFromString(action);
    id (*request)(id, SEL, NSDictionary *) = (id (*)(id, SEL, NSDictionary *))[_target methodForSelector:selector];
    id result = request(_target, selector, params);
    if ([result isKindOfClass:[NSError class]]) {
        NSError *error = result;
        return UDErrorResponse(identifier, error.code, error.localizedDescription);
    }
    return @{ @"jsonrpc": @"2.0", @"id": identifier, @"result": result ?: [NSNull null] };
}

- (void)runWithInput:(FILE *)input output:(FILE *)output {
    _stopped = NO;
    while (!_stopped) {
        @autoreleasepool {
            NSData *body = [[self class] readMessageFromFile:input];
            if (body == nil) break;
            NSDictionary *message = [NSJSONSerialization JSONObjectWithData:body options:0 error:NULL];
            NSDictionary *reply = [message isKindOfClass:[NSDictionary class]]
                ? [self replyToMessage:message]
                : UDErrorResponse(nil, UDJSONRPCParseError, @"Parse error");
            if (reply != nil) [[self class] writeMessage:reply toFile:output];
        }
    }
}

- (void)stop {
    _stopped = YES;
}

+ (NSData *)readMessageFromFile:(FILE *)input {
    char line[1024];
    long length = -1;
    while (fgets(line, sizeof line, input) != NULL) {
        if (strcmp(line, "\r\n") == 0 || strcmp(line, "\n") == 0) {
            if (length < 0) continue;                         // no header yet
            NSMutableData *body = [NSMutableData dataWithLength:(NSUInteger)length];
            if (length > 0 && fread(body.mutableBytes, 1, (size_t)length, input) != (size_t)length) return nil;
            return body;
        }
        if (strncasecmp(line, "Content-Length:", 15) == 0) {
            length = strtol(line + 15, NULL, 10);
        }
    }
    return nil;
}

+ (void)writeMessage:(NSDictionary *)message toFile:(FILE *)output {
    NSData *body = [NSJSONSerialization dataWithJSONObject:message options:0 error:NULL];
    fprintf(output, "Content-Length: %lu\r\n\r\n", (unsigned long)body.length);
    fwrite(body.bytes, 1, body.length, output);
    fflush(output);
}

@end
