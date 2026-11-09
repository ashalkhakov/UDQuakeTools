/*
 * udscript-lsp — the language server for a mod's scripts.
 *
 * Usage:
 *   udscript-lsp [--settings <json>]
 *
 * --settings is a workspace's settings, as its file holds them (fs_basepath,
 * fs_game, ...): the scripts are that workspace's file system's. Without it,
 * the workspace of the .qworkspace in the folder "initialize" names (UDCode's
 * project's), or, with none, only the open documents'. Messages come on stdin and responses go to
 * stdout, as LSP's base protocol frames them; what goes wrong goes to stderr.
 * See UDScriptLanguageServer.
 */

#import <Foundation/Foundation.h>

#import "UDScriptLanguageServer.h"
#import "UDGameWorkspace.h"
#import "UDStandardStreams.h"

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        UDStandardStreamsForMessages();
        UDGameWorkspace *workspace = nil;
        for (int i = 1; i < argc; i++) {
            if (strcmp(argv[i], "--settings") == 0 && i + 1 < argc) {
                NSData *json = [@(argv[++i]) dataUsingEncoding:NSUTF8StringEncoding];
                NSDictionary *settings = [NSJSONSerialization JSONObjectWithData:json options:0 error:NULL];
                if (![settings isKindOfClass:[NSDictionary class]]) {
                    fprintf(stderr, "udscript-lsp: --settings is no JSON object\n");
                    return 2;
                }
                workspace = [[UDGameWorkspace alloc] initWithDictionary:settings rootDirectory:settings[@"fs_basepath"] ?: @""];
            } else {
                fprintf(stderr, "Usage: udscript-lsp [--settings <json>]\n");
                return 2;
            }
        }
        NSError *error = nil;
        if (workspace != nil && ![workspace startup:&error]) {
            fprintf(stderr, "udscript-lsp: the workspace does not start: %s\n", error.localizedDescription.UTF8String ?: "");
            workspace = nil;
        }

        UDScriptLanguageServer *server = [[UDScriptLanguageServer alloc] initWithFileSystem:workspace.fileSystem];
        __block UDGameWorkspace *projects = nil;
        server.fileSystemOfFolder = ^idFileSystem *(NSString *folder) {
            NSArray *names = [[[NSFileManager defaultManager] contentsOfDirectoryAtPath:folder error:NULL]
                                 sortedArrayUsingSelector:@selector(compare:)];
            for (NSString *name in names) {
                if (![name.pathExtension isEqualToString:@"qworkspace"]) continue;
                NSData *json = [NSData dataWithContentsOfFile:[folder stringByAppendingPathComponent:name]];
                NSDictionary *settings = json ? [NSJSONSerialization JSONObjectWithData:json options:0 error:NULL] : nil;
                if (![settings isKindOfClass:[NSDictionary class]]) break;
                projects = [[UDGameWorkspace alloc] initWithDictionary:settings rootDirectory:settings[@"fs_basepath"] ?: @""];
                NSError *failure = nil;
                if (![projects startup:&failure]) {
                    fprintf(stderr, "udscript-lsp: %s does not start: %s\n", name.UTF8String, failure.localizedDescription.UTF8String ?: "");
                    projects = nil;
                }
                break;
            }
            return projects.fileSystem;
        };
        [server.connection runWithInput:stdin output:stdout];
        [workspace shutdown];
        [projects shutdown];
        return server.shutDown ? 0 : 1;
    }
}
