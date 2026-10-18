/*
 * udscript-dap — the debug adapter for a mod's scripts.
 *
 * Usage:
 *   udscript-dap
 *
 * Speaks the Debug Adapter Protocol on stdin and stdout, as LSP's base
 * protocol frames it, to a running dhewm3's script debugger (UDP 27980,
 * answered on 27981); what goes wrong goes to stderr. A launch or attach
 * request says which game and workspace. See UDScriptDebugAdapter.
 */

#import <Foundation/Foundation.h>

#import "UDScriptDebugAdapter.h"

@interface UDScriptDebugAdapterMain : NSObject
@end

@implementation UDScriptDebugAdapterMain

/// The client went: the adapter goes too.
- (void)connectionDidClose:(UDDAPConnection *)connection {
    exit(0);
}

@end

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc > 1) {
            fprintf(stderr, "Usage: udscript-dap\n");
            return 2;
        }
        static UDScriptDebugAdapter *adapter;
        static UDScriptDebugAdapterMain *closer;
        adapter = [[UDScriptDebugAdapter alloc] initWithQueue:dispatch_get_main_queue() output:stdout];
        closer = [[UDScriptDebugAdapterMain alloc] init];
        adapter.connection.closeTarget = closer;
        adapter.connection.closeAction = @selector(connectionDidClose:);
        [adapter.connection startReadingInput:stdin];
    }
    dispatch_main();
}
