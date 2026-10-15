//
//  UDJSONRPCConnection.h
//  UDCore
//
//  JSON-RPC 2.0 over LSP's base protocol: each message framed by a
//  Content-Length header. A connection hands each request and notification
//  to the action its target registered for the method, and answers requests
//  with what the action returns.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSErrorDomain const UDJSONRPCErrorDomain;

/// JSON-RPC's error codes, for an NSError in UDJSONRPCErrorDomain.
typedef NS_ENUM(NSInteger, UDJSONRPCErrorCode) {
    UDJSONRPCParseError = -32700,
    UDJSONRPCInvalidRequest = -32600,
    UDJSONRPCMethodNotFound = -32601,
    UDJSONRPCInvalidParams = -32602,
    UDJSONRPCInternalError = -32603,
};

@interface UDJSONRPCConnection : NSObject

- (instancetype)initWithTarget:(id)target;

/// Requests named @a method go to @a action, -(id)request:(NSDictionary *)params:
/// its result (NSNull for null), or an NSError, whose code and description
/// the error response carries.
- (void)setRequestAction:(SEL)action forMethod:(NSString *)method;

/// Notifications named @a method go to @a action, -(void)notification:(NSDictionary *)params.
- (void)setNotificationAction:(SEL)action forMethod:(NSString *)method;

/// The response to @a message, a request; nil for a notification. A request
/// no action answers is answered with UDJSONRPCMethodNotFound.
- (nullable NSDictionary *)replyToMessage:(NSDictionary *)message;

/// Reads messages from @a input and writes the responses to @a output, until
/// the input ends or -stop.
- (void)runWithInput:(FILE *)input output:(FILE *)output;
- (void)stop;

/// One framed message's body, or nil at the end of @a input; and the framing of one.
+ (nullable NSData *)readMessageFromFile:(FILE *)input;
+ (void)writeMessage:(NSDictionary *)message toFile:(FILE *)output;

@end

NS_ASSUME_NONNULL_END
