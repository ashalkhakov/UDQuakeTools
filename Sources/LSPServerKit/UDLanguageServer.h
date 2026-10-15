//
//  UDLanguageServer.h
//  UDCore
//
//  What every language server does, over a UDJSONRPCConnection: the
//  lifecycle (initialize, shutdown, exit) and the open documents' text
//  (textDocument/didOpen, didChange with the full text, didClose). A
//  subclass gives its capabilities, registers its requests on the
//  connection, and is told of the documents' changes.
//

#import <Foundation/Foundation.h>
#import "UDJSONRPCConnection.h"

NS_ASSUME_NONNULL_BEGIN

@interface UDLanguageServer : NSObject

- (instancetype)initWithName:(NSString *)name;

@property (nonatomic, readonly) UDJSONRPCConnection *connection;
/// Once "shutdown" has come, and once "exit" has.
@property (nonatomic, readonly) BOOL shutDown;
@property (nonatomic, readonly) BOOL exited;

/// The open document @a uri's text, or nil.
- (nullable NSString *)openTextOfDocument:(NSString *)uri;

#pragma mark For subclasses

/// The capabilities beyond textDocumentSync (which is full).
- (NSDictionary *)capabilities;
/// After "initialize", before its response.
- (void)serverWillInitialize;
/// After the open document's text changed: opened, edited or closed.
- (void)documentDidChange:(NSString *)uri;

/// A textDocument/... request's document, its text and the position's index
/// in it (through @a uri and @a index); nil when the text is unknown.
/// The text is -textOfDocument:'s.
- (nullable NSString *)textOfPositionParams:(NSDictionary *)params uri:(NSString *_Nullable *_Nonnull)uri index:(NSUInteger *)index;
/// A document's text: its open text (a subclass may know others).
- (nullable NSString *)textOfDocument:(NSString *)uri;

#pragma mark Positions

/// The UTF-16 index of an LSP position ({line, character}) in @a text, at
/// most its line's end; NSNotFound past the last line.
+ (NSUInteger)indexOfPosition:(NSDictionary *)position inText:(NSString *)text;
/// A Location: @a length characters from @a line's @a character, in @a uri.
+ (NSDictionary *)locationWithURI:(NSString *)uri line:(NSInteger)line character:(NSInteger)character length:(NSInteger)length;

@end

NS_ASSUME_NONNULL_END
