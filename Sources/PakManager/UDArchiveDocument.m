/*
 * SPDX-License-Identifier: GPL-2.0-or-later
 */

#import "UDArchiveDocument.h"
#import "UDArchiveBrowserController.h"
#import "UDArchive.h"
#import "UDArchiveEditor.h"
#import "UDArchiveCodec.h"
#import "UDCodecRegistry.h"

@implementation UDArchiveDocument

@synthesize archive = _archive;
@synthesize editor  = _editor;
@synthesize codec   = _codec;

/* ------------------------------------------------------------------ */
#pragma mark - NSDocument overrides

- (void)makeWindowControllers {
    UDArchiveBrowserController *wc =
        [[UDArchiveBrowserController alloc] initWithDocument:self];
    [self addWindowController:wc];
}

- (BOOL)readFromURL:(NSURL *)url ofType:(NSString *)typeName error:(NSError **)error {
    UDCodecRegistry *reg = [UDCodecRegistry sharedRegistry];

    /* First try to match by the document type name the system resolved. */
    id<UDArchiveCodec> codec = [reg codecForURL:url typeName:typeName];
    /* Fall back to signature / extension detection. */
    if (!codec) {
        codec = [reg codecForURL:url typeName:nil];
    }
    if (!codec) {
        if (error) {
            *error = [NSError errorWithDomain:NSCocoaErrorDomain
                                         code:NSFileReadUnknownError
                                     userInfo:@{NSLocalizedDescriptionKey:
                                                    @"No codec found for this file type."}];
        }
        return NO;
    }

    UDArchive *archive = [codec readArchiveFromURL:url error:error];
    if (!archive) {
        return NO;
    }

    _codec   = codec;
    _archive = archive;
    _editor  = [[UDArchiveEditor alloc] initWithArchive:archive];
    return YES;
}

- (BOOL)writeToURL:(NSURL *)url ofType:(NSString *)typeName error:(NSError **)error {
    (void)typeName;
    if (!_codec) {
        if (error) {
            *error = [NSError errorWithDomain:NSCocoaErrorDomain
                                         code:NSFileWriteUnknownError
                                     userInfo:@{NSLocalizedDescriptionKey:
                                                    @"No codec available for writing."}];
        }
        return NO;
    }
    return [_codec writeEditedArchive:_editor toURL:url error:error];
}

@end
