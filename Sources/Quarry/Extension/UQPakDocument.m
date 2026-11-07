/*---------------------------------------------------------------------------------------------
 *  UQPakDocument.m
 *--------------------------------------------------------------------------------------------*/

#import "UQPakDocument.h"
#import "UDArchiveDocument.h"
#import "UDArchiveEditor.h"
#import "UDCodecRegistry.h"
#import "UDPAKCodec.h"
#import "UDPAK2Codec.h"
#import "UDDaikatanaPAKCodec.h"
#import "UDPK3Codec.h"
#import "UDPK4Codec.h"

/// The formats Pak Manager reads and writes, once (its app delegate did it as it launched).
static void UQRegisterCodecs(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        UDCodecRegistry *registry = [UDCodecRegistry sharedRegistry];
        [registry registerCodec:[[UDPAKCodec alloc] init]];
        [registry registerCodec:[[UDPAK2Codec alloc] init]];
        [registry registerCodec:[[UDDaikatanaPAKCodec alloc] init]];
        [registry registerCodec:[[UDPK3Codec alloc] init]];
        [registry registerCodec:[[UDPK4Codec alloc] init]];
    });
}

@implementation UQPakDocument

+ (BOOL)isPakURL:(NSURL *)url {
    return url.isFileURL && [@[ @"pak", @"pk3", @"pk4" ] containsObject:url.pathExtension.lowercaseString];
}

- (instancetype)initWithURL:(NSURL *)url error:(NSError **)error {
    if (!(self = [super init])) return nil;
    UQRegisterCodecs();
    _URL = [url copy];
    _archiveDocument = [[UDArchiveDocument alloc] init];
    if (![_archiveDocument readFromURL:url ofType:@"" error:error]) return nil;
    _archiveDocument.fileURL = url;
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_didChange:)
                                                 name:UDArchiveEditorDidChangeNotification object:nil];
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

/// Its archive's edits (the editor's notice is any archive's: this one's only).
- (void)_didChange:(NSNotification *)note {
    if (note.object && note.object != _archiveDocument.editor) return;
    [[NSNotificationCenter defaultCenter] postNotificationName:UDCustomDocumentDidChangeNotification object:self];
}

- (NSUndoManager *)undoManager {
    return _archiveDocument.undoManager;
}

/// Its entries other than the file's (its editor's own measure: an edit
/// undone back to them is none).
- (BOOL)isEdited {
    return _archiveDocument.editor.isDirty;
}

/// Written over its file, then read again: what is saved is what it is of.
- (BOOL)saveCustomDocument:(NSError **)error {
    if (![_archiveDocument writeToURL:_URL ofType:_archiveDocument.fileType ?: @"" error:error]) return NO;
    return [self revertCustomDocument:error];
}

- (BOOL)revertCustomDocument:(NSError **)error {
    if (![_archiveDocument readFromURL:_URL ofType:@"" error:error]) return NO;
    [_archiveDocument updateChangeCount:NSChangeCleared];
    [[NSNotificationCenter defaultCenter] postNotificationName:UDArchiveEditorDidChangeNotification object:_archiveDocument.editor];
    [[NSNotificationCenter defaultCenter] postNotificationName:UDCustomDocumentDidChangeNotification object:self];
    return YES;
}

@end
