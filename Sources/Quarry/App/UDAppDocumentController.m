#import "UDAppDocumentController.h"
#import "UDWorkspaceDocument.h"

@implementation UDAppDocumentController

/**
 * For non-workspace documents we suppress display (display:NO) so
 * AppKit doesn't open a standalone window.  The workspace window
 * controller opens the file inside its own tab via EditorTabManager.
 *
 * For workspace documents we pass display:YES so their window appears.
 */
- (void)openDocumentWithContentsOfURL:(NSURL *)url
                              display:(BOOL)displayDocument
                    completionHandler:(void (^)(NSDocument * _Nullable, BOOL, NSError * _Nullable))completionHandler {
    NSString *ext = url.pathExtension.lowercaseString;
    BOOL isWorkspace = [ext isEqualToString:@"qworkspace"];

    [super openDocumentWithContentsOfURL:url
                                 display:isWorkspace ? YES : NO
                       completionHandler:completionHandler];
}

@end
