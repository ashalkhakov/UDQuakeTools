#import "UDImageFileDocument.h"

@implementation UDImageFileDocument

- (void)makeWindowControllers {
    // No standalone window; the workspace hosts the view.
}

- (BOOL)readFromURL:(NSURL *)url ofType:(NSString *)typeName error:(NSError **)outError {
    NSImage *image = [[NSImage alloc] initWithContentsOfURL:url];
    if (!image) {
        if (outError) {
            *outError = [NSError errorWithDomain:NSCocoaErrorDomain
                                           code:NSFileReadUnknownError
                                       userInfo:@{NSURLErrorKey: url}];
        }
        return NO;
    }
    _image = image;
    return YES;
}

@end
