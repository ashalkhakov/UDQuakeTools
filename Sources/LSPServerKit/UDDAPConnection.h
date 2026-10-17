//
//  UDDAPConnection.h
//  UDCore
//
//  The Debug Adapter Protocol, from the adapter's side: messages framed as
//  LSP's base protocol frames them (UDJSONRPCConnection's), each a request
//  ({seq, type: "request", command, arguments}), its response, or an event.
//  A request goes to the action its target registered for the command,
//  which answers it at once or later (a debugger's answers wait on the
//  debuggee); events go out whenever the adapter has them.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class UDDAPConnection;

/// One request, answered once.
@interface UDDAPRequest : NSObject
@property (nonatomic, copy, readonly) NSString *command;
@property (nonatomic, copy, readonly) NSDictionary *arguments;
@property (nonatomic, readonly) NSInteger seq;
@property (nonatomic, readonly, getter=isAnswered) BOOL answered;
/// Its response, successful, with @a body (nil: none).
- (void)respondWithBody:(nullable NSDictionary *)body;
/// Its response, failed, @a message saying why.
- (void)failWithMessage:(NSString *)message;
@end

@interface UDDAPConnection : NSObject

/// Requests go to @a target on @a queue; what is sent goes to @a output.
- (instancetype)initWithTarget:(id)target queue:(dispatch_queue_t)queue output:(FILE *)output;

/// Requests for @a command go to @a action, -(void)request:(UDDAPRequest *)request,
/// which answers it. A command with no action is answered as unsupported;
/// an action that raises, as failed.
- (void)setRequestAction:(SEL)action forCommand:(NSString *)command;
/// Told the input ended: the close target's -(void)connectionDidClose:(UDDAPConnection *)connection.
@property (nonatomic, weak, nullable) id closeTarget;
@property (nonatomic, nullable) SEL closeAction;

/// One message, as read: a request, handled on the caller's thread (the
/// queue's, normally).
- (void)handleMessage:(NSDictionary *)message;
/// Reads messages from @a input on a thread of its own, each handled on the
/// queue; at its end, the close action.
- (void)startReadingInput:(FILE *)input;

- (void)sendEvent:(NSString *)event body:(nullable NSDictionary *)body;

@end

NS_ASSUME_NONNULL_END
