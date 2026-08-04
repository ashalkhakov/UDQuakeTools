#import <Cocoa/Cocoa.h>

@class idDecl;

@interface UDEditorTabViewController : NSTabViewController

- (void)openDeclInNewTab:(idDecl *)decl;

@end
