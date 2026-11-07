//
//  UDScriptLanguageServer.h
//  udscript-lsp
//
//  The language server for a mod's scripts. It answers
//  textDocument/definition from a UDScriptIndex of every .script the file
//  system has, completion and hover from it and from the events
//  doom_events.script declares. Open documents' text overrides the file
//  system's; workspace/didChangeWatchedFiles says when the file system's
//  changed. A script is named by its path in the file system, as UDCode's
//  UDQuakeTools extension names a game file ("quarry:/file/script/lamp.script").
//  The protocol is LSPServerKit's.
//

#import <Foundation/Foundation.h>
#import "UDLanguageServer.h"

@class idFileSystem;

NS_ASSUME_NONNULL_BEGIN

@interface UDScriptLanguageServer : UDLanguageServer

/// A server over @a fileSystem's scripts, or over the open documents alone.
- (instancetype)initWithFileSystem:(nullable idFileSystem *)fileSystem;

/// Without a file system: the one of the project whose folder "initialize"
/// names (its rootUri), asked of this as it comes; nil, the open documents'
/// alone.
@property (nonatomic, copy, nullable) idFileSystem *_Nullable (^fileSystemOfFolder)(NSString *folder);

+ (NSString *)URIForPath:(NSString *)path;
/// The path a quarry:/file/ URI names, or nil.
+ (nullable NSString *)pathForURI:(NSString *)uri;

@end

NS_ASSUME_NONNULL_END
