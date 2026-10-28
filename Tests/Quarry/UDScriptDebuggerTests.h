//
//  UDScriptDebuggerTests.h
//  QuarryTests
//
//  The script debugger's tests (UDScriptDebuggerTests.m), and what those of
//  one system only share with them (posix/: the game a shell script).
//

#import "UDQuarryTestCase.h"
#import "UDFakeScriptDebugger.h"

NS_ASSUME_NONNULL_BEGIN

@interface UDScriptDebuggerTests : UDQuarryTestCase
@property (nonatomic, strong, nullable) UDFakeScriptDebugger *game;

/// The next message of @a type the debugger sent the game, the run loop
/// turning meanwhile (the session's answers come on it).
- (nullable UDBitMsg *)receive:(int)type within:(NSTimeInterval)timeout;
@end

NS_ASSUME_NONNULL_END
