#import <Foundation/Foundation.h>

@class UDGameWorkspace, LSPClient;

NS_ASSUME_NONNULL_BEGIN

/**
 * Each workspace's language server for its scripts: udscript-lsp, beside the
 * app's executable, over the workspace's settings. The script tabs share it;
 * each opens its script by its udfs: URL, so the server reads the rest from
 * the workspace's file system, and is told when the workspace writes a file.
 */
@interface UDScriptServer : NSObject

/// The server for @a workspace, started on first use; nil without udscript-lsp
/// (or $UD_SCRIPT_LSP, which names it instead).
+ (nullable LSPClient *)clientForWorkspace:(UDGameWorkspace *)workspace;

/// Stops @a workspace's server: it closes, or restarts with other settings.
+ (void)stopForWorkspace:(UDGameWorkspace *)workspace;

/// Tells @a workspace's server, if it has one, that the file at @a path was written.
+ (void)workspace:(UDGameWorkspace *)workspace didWriteFileAtPath:(NSString *)path;

/// A file's udfs: URL, and back.
+ (NSURL *)URLForPath:(NSString *)path;
+ (nullable NSString *)pathForURL:(NSURL *)url;

@end

NS_ASSUME_NONNULL_END
