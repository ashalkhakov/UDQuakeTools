//
//  UDScriptLanguageServer.h
//  UDCore
//
//  A language server for a mod's scripts, as messages in and replies out:
//  udscript-lsp frames them on stdin and stdout, the tests call it directly.
//  It answers textDocument/definition from a UDScriptIndex of every .script
//  the file system has, completion and hover from it and from the events
//  doom_events.script declares. Open documents' text overrides the file
//  system's; workspace/didChangeWatchedFiles says when the file system's
//  changed. A script is named by its path in the file system, as a udfs: URI
//  ("udfs:///script/lamp.script").
//

#import <Foundation/Foundation.h>

@class idFileSystem;

NS_ASSUME_NONNULL_BEGIN

@interface UDScriptLanguageServer : NSObject

/// A server over @a fileSystem's scripts, or over the open documents alone.
- (instancetype)initWithFileSystem:(nullable idFileSystem *)fileSystem;

/// The response to @a message, a JSON-RPC request; nil for a notification.
- (nullable NSDictionary *)replyToMessage:(NSDictionary *)message;

/// Once "exit" has come.
@property (nonatomic, readonly) BOOL exited;
/// Whether "shutdown" came before it.
@property (nonatomic, readonly) BOOL shutDown;

+ (NSString *)URIForPath:(NSString *)path;
/// The path a udfs: URI names, or nil.
+ (nullable NSString *)pathForURI:(NSString *)uri;

@end

NS_ASSUME_NONNULL_END
