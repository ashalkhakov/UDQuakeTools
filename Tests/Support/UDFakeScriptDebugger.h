//
//  UDFakeScriptDebugger.h
//  UDQuakeToolsTests
//
//  The game's side of the script debugger, for the tests: a UDP socket on
//  the game's port that reads what the debugger sends and answers as
//  rvDebuggerServer would, each message written by hand with UDBitMsg.
//

#import <Foundation/Foundation.h>
#import "UDBitMsg.h"

NS_ASSUME_NONNULL_BEGIN

@interface UDFakeScriptDebugger : NSObject

/// Two free ports, near each other: the game's and its debugger's.
+ (uint16_t)gamePort;
+ (uint16_t)debuggerPort;

/// Listening on @a port, answering to @a debuggerPort (both on 127.0.0.1).
- (nullable instancetype)initWithPort:(uint16_t)port debuggerPort:(uint16_t)debuggerPort;

/// The next message the debugger sent (nil after @a timeout seconds), read
/// past its DBMSG_* short; its type in @a type.
- (nullable UDBitMsg *)receiveWithin:(NSTimeInterval)timeout type:(int *)type;
/// The next message of @a type, those before it skipped.
- (nullable UDBitMsg *)receiveType:(int)type within:(NSTimeInterval)timeout;

/// A message of @a type, for its fields to be written, and its sending.
- (UDBitMsg *)message:(int)type;
- (void)send:(UDBitMsg *)message;

@end

NS_ASSUME_NONNULL_END
