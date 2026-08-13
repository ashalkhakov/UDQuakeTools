#import "UDTextFileDocument.h"
#import "UDWorkspace.h"
#import "idFileSystem.h"

@interface UDTextFileDocument ()
@property (nonatomic, weak) NSTextView *textView;
@end

@implementation UDTextFileDocument

- (instancetype)initWithPath:(NSString *)path inWorkspace:(UDWorkspace *)workspace error:(NSError **)error {
    self = [super initWithType:@"public.plain-text" error:error];
    if (self) {
        self.workspace = workspace;
        _path = path;
    }
    return self;
}

// Don't create a window; the workspace window controller hosts the view.
- (void)makeWindowControllers {
}

- (BOOL)readFromURL:(NSURL *)url ofType:(NSString *)typeName error:(NSError **)error {
    void *buffer = NULL;
    int bufferLen = [self.workspace.fileSystem readFile:_path buffer:&buffer timestamp:NULL error:error];

    if (bufferLen == -1) {
        return NO; // FIXME: what's up?
    }
    
    if (error && *error) {
        NSLog(@"Failed to open %@: %@", _path, [*error localizedDescription]);
        return NO;
    }
    
    if (!bufferLen) {
        return NO;
    }
        
    NSString *text = [[NSString alloc] initWithBytes:buffer length:bufferLen encoding:NSUTF8StringEncoding];
    [self.workspace.fileSystem freeFile:buffer error:nil];
    _textContent = text;
    return YES;
}

- (BOOL)writeToURL:(NSURL *)url ofType:(NSString *)typeName error:(NSError **)error {
    NSString *content = self.textView ? self.textView.string : self.textContent ?: @"";
    NSData *buffer = [content dataUsingEncoding:NSUTF8StringEncoding];

    int written = [self.workspace.fileSystem writeFile:_path buffer:buffer.bytes size:(int)buffer.length basePath:nil error:error];
    if (written == -1) {
        return NO;
    }

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
