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

    NSArray<id<UDArchiveCodec>> *candidates = [reg codecCandidatesForURL:url typeName:typeName];
    if (candidates.count == 0) {
        candidates = [reg codecCandidatesForURL:url typeName:nil];
    }

    if (candidates.count == 0) {
        if (error) {
            *error = [NSError errorWithDomain:NSCocoaErrorDomain
                                         code:NSFileReadUnknownError
                                     userInfo:@{NSLocalizedDescriptionKey:
                                                    @"No codec found for this file type."}];
        }
        return NO;
    }

    NSError *lastReadError = nil;
    UDArchive *archive = nil;
    id<UDArchiveCodec> selectedCodec = nil;

    for (id<UDArchiveCodec> candidate in candidates) {
        NSError *candidateError = nil;
        archive = [candidate readArchiveFromURL:url error:&candidateError];
        if (archive) {
            selectedCodec = candidate;
            break;
        }
        if (candidateError) {
            lastReadError = candidateError;
        }
    }

    if (!archive || !selectedCodec) {
        if (error) {
            if (lastReadError) {
                *error = lastReadError;
            } else {
                *error = [NSError errorWithDomain:NSCocoaErrorDomain
                                             code:NSFileReadUnknownError
                                         userInfo:@{NSLocalizedDescriptionKey:
                                                        @"No compatible codec could read this archive."}];
            }
        }
        return NO;
    }

    _codec   = selectedCodec;
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
