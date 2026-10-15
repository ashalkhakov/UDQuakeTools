#import "UDBaseDocument.h"

NSString * const UDBaseDocumentEditedStateDidChangeNotification = @"UDBaseDocumentEditedStateDidChangeNotification";

@implementation UDBaseDocument {
    NSString *_fileLineEnding;   // "\r\n" or "\n": what the file had
}

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

- (NSString *)editorTextFromFileText:(NSString *)text {
    _fileLineEnding = [text rangeOfString:@"\r\n"].location != NSNotFound ? @"\r\n" : @"\n";
    NSString *lf = [text stringByReplacingOccurrencesOfString:@"\r\n" withString:@"\n"];
    return [lf stringByReplacingOccurrencesOfString:@"\r" withString:@"\n"];
}

- (NSString *)fileTextFromEditorText:(NSString *)text {
    if (![_fileLineEnding isEqualToString:@"\r\n"]) return text;
    return [text stringByReplacingOccurrencesOfString:@"\n" withString:@"\r\n"];
}

@end
