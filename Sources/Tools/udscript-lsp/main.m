/*
 * udscript-lsp — the language server for a mod's scripts.
 *
 * Usage:
 *   udscript-lsp [--settings <json>]
 *
 * --settings is a workspace's settings, as its file holds them (fs_basepath,
 * fs_game, ...): the scripts are that workspace's file system's. Without it,
 * only the open documents'. Messages come on stdin and replies go to stdout,
 * each framed by a Content-Length header, as LSP's base protocol has them;
 * what goes wrong goes to stderr. See UDScriptLanguageServer.
 */

#import <Foundation/Foundation.h>

#import "UDScriptLanguageServer.h"
#import "UDWorkspace.h"

/// The next message's body, or nil at the end of the input.
static NSData *readMessage(FILE *in) {
    char line[1024];
    long length = -1;
    while (fgets(line, sizeof line, in) != NULL) {
        if (strcmp(line, "\r\n") == 0 || strcmp(line, "\n") == 0) {
            if (length < 0) continue;
            NSMutableData *body = [NSMutableData dataWithLength:(NSUInteger)length];
            if (length > 0 && fread(body.mutableBytes, 1, (size_t)length, in) != (size_t)length) return nil;
            return body;
        }
        if (strncasecmp(line, "Content-Length:", 15) == 0) {
            length = strtol(line + 15, NULL, 10);
        }
    }
    return nil;
}

static void writeMessage(FILE *out, NSDictionary *message) {
    NSData *body = [NSJSONSerialization dataWithJSONObject:message options:0 error:NULL];
    fprintf(out, "Content-Length: %lu\r\n\r\n", (unsigned long)body.length);
    fwrite(body.bytes, 1, body.length, out);
    fflush(out);
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
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
        while (!server.exited) {
            @autoreleasepool {
                NSData *body = readMessage(stdin);
                if (body == nil) break;
                NSDictionary *message = [NSJSONSerialization JSONObjectWithData:body options:0 error:NULL];
                if (![message isKindOfClass:[NSDictionary class]]) {
                    writeMessage(stdout, @{ @"jsonrpc": @"2.0", @"id": [NSNull null],
                                            @"error": @{ @"code": @(-32700), @"message": @"Parse error" } });
                    continue;
                }
                NSDictionary *reply = [server replyToMessage:message];
                if (reply != nil) writeMessage(stdout, reply);
            }
        }
        [workspace shutdown];
        return server.shutDown ? 0 : 1;
    }
}
