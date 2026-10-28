/*
 * udscript-lsp — the language server for a mod's scripts.
 *
 * Usage:
 *   udscript-lsp [--settings <json>]
 *
 * --settings is a workspace's settings, as its file holds them (fs_basepath,
 * fs_game, ...): the scripts are that workspace's file system's. Without it,
 * only the open documents'. Messages come on stdin and responses go to
 * stdout, as LSP's base protocol frames them; what goes wrong goes to stderr.
 * See UDScriptLanguageServer.
 */

#import <Foundation/Foundation.h>

#import "UDScriptLanguageServer.h"
#import "UDWorkspace.h"
#import "UDStandardStreams.h"

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        UDStandardStreamsForMessages();
        UDWorkspace *workspace = nil;
        for (int i = 1; i < argc; i++) {
            if (strcmp(argv[i], "--settings") == 0 && i + 1 < argc) {
                NSData *json = [@(argv[++i]) dataUsingEncoding:NSUTF8StringEncoding];
                NSDictionary *settings = [NSJSONSerialization JSONObjectWithData:json options:0 error:NULL];
                if (![settings isKindOfClass:[NSDictionary class]]) {
                    fprintf(stderr, "udscript-lsp: --settings is no JSON object\n");
                    return 2;
                }
                workspace = [[UDWorkspace alloc] initWithDictionary:settings rootDirectory:settings[@"fs_basepath"] ?: @""];
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
        [server.connection runWithInput:stdin output:stdout];
        [workspace shutdown];
        return server.shutDown ? 0 : 1;
    }
}
