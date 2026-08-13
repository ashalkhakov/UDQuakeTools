#import "UDDeclDocument.h"

@interface UDDeclDocument ()
@property (nonatomic, weak) NSTextView *textView;
@end

@implementation UDDeclDocument

- (instancetype)initWithType:(declType_t)type name:(NSString *)name inWorkspace:(UDWorkspace *)workspace error:(NSError **)error {
    self = [super initWithType:@"public.plain-text" error:error];
    if (self) {
        self.workspace = workspace;
        _decl = [workspace.declManager declByName:name type:type error:error];
        if (!_decl) {
            return nil;
        }
    }
    return self;
}

// Don't create a window; the workspace window controller hosts the view.
- (void)makeWindowControllers {
}

- (BOOL)readFromURL:(NSURL *)url ofType:(NSString *)typeName error:(NSError **)error {
    NSMutableData *declText = [[NSMutableData alloc] init];
    [_decl text:declText];

    NSString *text = [[NSString alloc] initWithData:declText encoding:NSUTF8StringEncoding];
    _textContent = text ?: @"";
    return YES;
}

- (BOOL)writeToURL:(NSURL *)url ofType:(NSString *)typeName error:(NSError **)error {
    NSString *content = self.textView ? self.textView.string : self.textContent ?: @"";
    NSMutableData *buffer = [[content dataUsingEncoding:NSUTF8StringEncoding] mutableCopy];

    [_decl setText:buffer];
    if (![_decl replaceSourceFileText:error]) {
        return NO;
    }
    [_decl invalidate];
    
    return YES;
}

- (void)setTextView:(NSTextView *)textView {
    _textView = textView;
    if (textView && self.textContent) {
        [textView.textStorage beginEditing];
        [textView.textStorage
            replaceCharactersInRange:NSMakeRange(0, textView.textStorage.length)
                          withString:self.textContent];
        [textView.textStorage endEditing];
    }
    textView.undoManager.levelsOfUndo = 50;
}

@end
