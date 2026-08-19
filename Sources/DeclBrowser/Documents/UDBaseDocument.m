#import "UDBaseDocument.h"

@implementation UDBaseDocument

- (BOOL)ud_save:(NSError **)error {
    // The URL is never dereferenced; subclasses write through the workspace.
    return [self writeToURL:[NSURL URLWithString:@"http://localhost/unused.txt"]
                     ofType:@""
                      error:error];
}

@end
