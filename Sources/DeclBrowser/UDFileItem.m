#import "UDFileItem.h"
#import "UDWorkspace.h"
#import "idFileSystem.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

@implementation UDFileItem

- (instancetype)initWithPath:(NSString *)path {
    NSString *name = path.lastPathComponent;
    self = [super initWithName:name path:path];
    if (self) {
        // Detect UTI from file extension.
        NSString *ext = path.pathExtension;
        if (ext.length > 0) {
            if (@available(macOS 11.0, *)) {
                UTType *type = [UTType typeWithFilenameExtension:ext];
                _fileUTI = type.identifier;
            } else {
                CFStringRef uti = UTTypeCreatePreferredIdentifierForTag(
                    kUTTagClassFilenameExtension,
                    (__bridge CFStringRef)ext,
                    NULL);
                if (uti) {
                    _fileUTI = CFBridgingRelease(uti);
                }
            }
        }
    }
    return self;
}

- (UDWorkspaceItemKind)kind {
    return UDWorkspaceItemKindFile;
}

- (NSString *)text:(UDWorkspace *)workspace {
    void *buffer = NULL;
    NSError *error = nil;
    int bufferLen = [workspace.fileSystem readFile:self.path buffer:&buffer timestamp:NULL error:&error];
    
    if (bufferLen == -1) {
        return @""; // FIXME: what's up?
    }
    
    if (error) {
        NSLog(@"Failed to open %@: %@", self.path, [error localizedDescription]);
        return @"";
    }
    
    if (!bufferLen) {
        return @"";
    }
    
    NSString *text = [[NSString alloc] initWithBytes:buffer length:bufferLen encoding:NSUTF8StringEncoding];
    [workspace.fileSystem freeFile:buffer error:nil];
    return text;
}

- (BOOL)matchesTextSearch:(NSString *)query inWorkspace:(UDWorkspace *)workspace {
    if (query.length == 0) return YES;
    // TODO: replace with LSP / cache
    NSString *t = [self text:workspace];
    if (!t) return NO;
    return [t rangeOfString:query options:NSCaseInsensitiveSearch].location != NSNotFound;
}

@end
