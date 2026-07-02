/*
 * SPDX-License-Identifier: GPL-2.0-or-later
 */

#import "UDGuiEdDocument.h"
#import "UDGuiEdDocumentWindowController.h"

#import "../UDCore/UDGuiDocumentCodec.h"
#import "../UDCore/UDGuiEditorService.h"
#import "../UDCore/UDGuiEditorViewModel.h"
#import "../UDCore/UDGuiModel.h"

@interface UDGuiEdDocument ()
@property (nonatomic, copy, readwrite) NSString *sourceText;
@property (nonatomic, strong, readwrite, nullable) UDGuiDocument *guiDocument;
@property (nonatomic, strong, readwrite, nullable) UDGuiEditorService *editorService;
@property (nonatomic, strong, readwrite, nullable) UDGuiEditorViewModel *viewModel;
@property (nonatomic, strong, readwrite) UDGuiDocumentCodec *codec;
@end

@implementation UDGuiEdDocument

- (instancetype)init {
    self = [super init];
    if (!self) {
        return nil;
    }

    _codec = [[UDGuiDocumentCodec alloc] init];
    _sourceText = @"";
    _guiDocument = [[UDGuiDocument alloc] initWithSourceVirtualPath:@"Untitled.ui"];
    _editorService = [[UDGuiEditorService alloc] initWithDocument:_guiDocument undoManager:[self undoManager]];
    _viewModel = [[UDGuiEditorViewModel alloc] initWithService:_editorService];
    return self;
}

- (void)makeWindowControllers {
    UDGuiEdDocumentWindowController *windowController = [[UDGuiEdDocumentWindowController alloc] initWithDocument:self];
    [self addWindowController:windowController];
}

- (void)updateSourceText:(NSString *)sourceText {
    _sourceText = [sourceText copy] ?: @"";

    NSError *parseError = nil;
    UDGuiDocument *document = [self.codec parseDocumentFromText:self.sourceText
                                              sourceVirtualPath:self.fileURL.path ?: @"Untitled.ui"
                                                          error:&parseError];
    if (document) {
        _guiDocument = document;
        _editorService = [[UDGuiEditorService alloc] initWithDocument:document undoManager:[self undoManager]];
        _viewModel = [[UDGuiEditorViewModel alloc] initWithService:_editorService];
    } else if (parseError) {
        NSLog(@"GuiEd parse warning: %@", parseError.localizedDescription);
    }

    [self updateChangeCount:NSChangeDone];
}

- (nullable NSString *)serializedSourceText {
    if (!self.guiDocument) {
        return @"";
    }

    NSError *serializeError = nil;
    NSString *serializedText = [self.codec serializeDocument:self.guiDocument error:&serializeError];
    if (!serializedText) {
        if (serializeError) {
            NSLog(@"GuiEd serialize warning: %@", serializeError.localizedDescription);
        }
        return self.sourceText ?: @"";
    }

    return serializedText;
}

- (void)syncSourceTextFromGUIModel {
    self.sourceText = [self serializedSourceText] ?: @"";
}

- (void)notifyGUIModelDidChange {
    [self syncSourceTextFromGUIModel];
    [self updateChangeCount:NSChangeDone];
}

- (NSArray<NSString *> *)readableTypes {
    return @[@"com.udquake.ui"];
}

- (NSArray<NSString *> *)writableTypes {
    return @[@"com.udquake.ui"];
}

- (NSArray<NSString *> *)writableTypesForSaveOperation:(NSSaveOperationType)saveOperation {
    (void)saveOperation;
    return [self writableTypes];
}

- (NSString *)displayNameForType:(NSString *)typeName {
    return [typeName isEqualToString:@"com.udquake.ui"] ? @"Doom 3 / Quake 3 GUI" : typeName;
}

- (NSString *)fileNameExtensionForType:(NSString *)typeName
                         saveOperation:(NSSaveOperationType)saveOperation {
    (void)typeName;
    (void)saveOperation;
    return @"ui";
}

- (BOOL)readFromURL:(NSURL *)url ofType:(NSString *)typeName error:(NSError **)error {
    (void)typeName;
    NSString *text = [NSString stringWithContentsOfURL:url
                                              encoding:NSUTF8StringEncoding
                                                 error:error];
    if (!text) {
        return NO;
    }

    self.sourceText = text;
    UDGuiDocument *document = [self.codec parseDocumentFromText:text
                                              sourceVirtualPath:url.path ?: url.absoluteString
                                                          error:error];
    if (!document) {
        return NO;
    }

    _guiDocument = document;
    _editorService = [[UDGuiEditorService alloc] initWithDocument:document undoManager:[self undoManager]];
    _viewModel = [[UDGuiEditorViewModel alloc] initWithService:_editorService];
    return YES;
}

- (BOOL)writeToURL:(NSURL *)url ofType:(NSString *)typeName error:(NSError **)error {
    (void)typeName;
    NSString *text = [self serializedSourceText] ?: @"";
    self.sourceText = text;
    return [text writeToURL:url atomically:YES encoding:NSUTF8StringEncoding error:error];
}

@end