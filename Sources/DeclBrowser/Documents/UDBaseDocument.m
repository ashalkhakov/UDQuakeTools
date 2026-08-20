#import "UDBaseDocument.h"

NSString * const UDBaseDocumentEditedStateDidChangeNotification = @"UDBaseDocumentEditedStateDidChangeNotification";

@implementation UDBaseDocument

- (void)updateChangeCount:(NSDocumentChangeType)change {
    [super updateChangeCount:change];
    [[NSNotificationCenter defaultCenter] postNotificationName:UDBaseDocumentEditedStateDidChangeNotification
                                                        object:self];
}

- (BOOL)ud_save:(NSError **)error {
    // The URL is never dereferenced; subclasses write through the workspace.
    return [self writeToURL:[NSURL URLWithString:@"http://localhost/unused.txt"]
                     ofType:@""
                      error:error];
}

@end
