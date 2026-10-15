#import "UDScriptServer.h"
#import "UDWorkspace.h"
#import <LSPKit/LSPKit.h>

@implementation UDScriptServer

static NSMapTable<UDWorkspace *, LSPClient *> *UDClients(void) {
    static NSMapTable *clients = nil;
    if (clients == nil) clients = [NSMapTable strongToStrongObjectsMapTable];
    return clients;
}

+ (LSPClient *)clientForWorkspace:(UDWorkspace *)workspace {
    LSPClient *client = [UDClients() objectForKey:workspace];
    if (client != nil) return client;

    // $UD_SCRIPT_LSP, for the tests, whose main bundle is not the app.
    NSString *tool = NSProcessInfo.processInfo.environment[@"UD_SCRIPT_LSP"]
        ?: [[NSBundle mainBundle] pathForAuxiliaryExecutable:@"udscript-lsp"];
    if (tool == nil) return nil;
    NSData *settings = [NSJSONSerialization dataWithJSONObject:workspace.dictionaryRepresentation options:0 error:NULL];
    if (settings == nil) return nil;
    client = [[LSPClient alloc] initWithPath:tool
                                   arguments:@[ @"--settings", [[NSString alloc] initWithData:settings encoding:NSUTF8StringEncoding] ]
                        currentDirectoryPath:nil
                                  languageID:@"idscript"];
    [UDClients() setObject:client forKey:workspace];
    return client;
}

+ (void)stopForWorkspace:(UDWorkspace *)workspace {
    LSPClient *client = [UDClients() objectForKey:workspace];
    [UDClients() removeObjectForKey:workspace];
    [client terminate];
}

+ (void)workspace:(UDWorkspace *)workspace didWriteFileAtPath:(NSString *)path {
    LSPClient *client = [UDClients() objectForKey:workspace];
    if (client == nil) return;
    [client sendNotification:@"workspace/didChangeWatchedFiles"
                      params:@{ @"changes": @[ @{ @"uri": [self URLForPath:path].absoluteString, @"type": @2 } ] }];
}

// udfs:///<path>, as udscript-lsp names a file in the file system.
+ (NSURL *)URLForPath:(NSString *)path {
    NSURLComponents *components = [[NSURLComponents alloc] init];
    components.scheme = @"udfs";
    components.host = @"";
    components.path = [@"/" stringByAppendingString:path];
    return components.URL;
}

+ (NSString *)pathForURL:(NSURL *)url {
    if (![url.scheme isEqualToString:@"udfs"]) return nil;
    NSString *path = url.path;
    while ([path hasPrefix:@"/"]) path = [path substringFromIndex:1];
    return path.length > 0 ? path : nil;
}

@end
