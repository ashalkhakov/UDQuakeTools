/*---------------------------------------------------------------------------------------------
 *  UQGuiDocument.m
 *--------------------------------------------------------------------------------------------*/

#import "UQGuiDocument.h"
#import "UDTextFileDocument.h"
#import "UDFileItem.h"
#import "UDGuiEditorViewController.h"

static NSURL *UQUnusedURL(void) {
    return [NSURL URLWithString:@"http://localhost/unused.txt"];
}

@implementation UQGuiDocument

+ (BOOL)isGuiPath:(NSString *)path {
    return [path.pathExtension caseInsensitiveCompare:@"gui"] == NSOrderedSame;
}

- (instancetype)initWithPath:(NSString *)path inWorkspace:(UDGameWorkspace *)workspace error:(NSError **)error {
    if (!(self = [super init])) return nil;
    _workspace = workspace;
    _textDocument = [[UDTextFileDocument alloc] initWithPath:path inWorkspace:workspace error:error];
    if (!_textDocument || ![_textDocument readFromURL:UQUnusedURL() ofType:@"" error:error]) return nil;
    _item = [[UDFileItem alloc] initWithPath:path];
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    NSUndoManager *undo = _textDocument.undoManager;
    // its edits (an undo group closing), their undo and redo, a save
    for (NSNotificationName name in @[ NSUndoManagerWillCloseUndoGroupNotification, NSUndoManagerDidUndoChangeNotification,
                                       NSUndoManagerDidRedoChangeNotification ]) {
        [center addObserver:self selector:@selector(_didChange:) name:name object:undo];
    }
    [center addObserver:self selector:@selector(_didChange:) name:UDBaseDocumentEditedStateDidChangeNotification object:_textDocument];
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)_didChange:(NSNotification *)note {
    [[NSNotificationCenter defaultCenter] postNotificationName:UDCustomDocumentDidChangeNotification object:self];
}

// ---------------------------------------------------------------------------
// MARK: - UDCustomDocument
// ---------------------------------------------------------------------------

- (NSUndoManager *)undoManager {
    return _textDocument.undoManager;
}

- (BOOL)isEdited {
    return _textDocument.isDocumentEdited;
}

- (BOOL)saveCustomDocument:(NSError **)error {
    return [_textDocument ud_save:error];
}

- (BOOL)revertCustomDocument:(NSError **)error {
    if (![_textDocument readFromURL:UQUnusedURL() ofType:@"" error:error]) return NO;
    [_editor reloadText:_textDocument.textContent ?: @""];
    [_textDocument.undoManager removeAllActions];
    [_textDocument updateChangeCount:NSChangeCleared];
    return YES;
}

- (NSString *)textOfDocument {
    return _editor ? _editor.currentText : _textDocument.textContent ?: @"";
}

- (BOOL)applyText:(NSString *)text error:(NSError **)error {
    if (_editor) {
        [_editor replaceTextUndoably:text];
    } else {
        _textDocument.textContent = text;
        [_textDocument updateChangeCount:NSChangeDone];
    }
    return YES;
}

@end
