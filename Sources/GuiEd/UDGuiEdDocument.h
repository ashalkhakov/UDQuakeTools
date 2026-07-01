/*
 * SPDX-License-Identifier: GPL-2.0-or-later
 * UDGuiEdDocument — document wrapper for .ui editor files.
 */

#import <AppKit/AppKit.h>

@class UDGuiDocument;
@class UDGuiEditorService;
@class UDGuiEditorViewModel;
@class UDGuiDocumentCodec;

NS_ASSUME_NONNULL_BEGIN

@interface UDGuiEdDocument : NSDocument

@property (nonatomic, copy, readonly) NSString *sourceText;
@property (nonatomic, strong, readonly, nullable) UDGuiDocument *guiDocument;
@property (nonatomic, strong, readonly, nullable) UDGuiEditorService *editorService;
@property (nonatomic, strong, readonly, nullable) UDGuiEditorViewModel *viewModel;
@property (nonatomic, strong, readonly) UDGuiDocumentCodec *codec;

- (void)updateSourceText:(NSString *)sourceText;
- (void)syncSourceTextFromGUIModel;
- (void)notifyGUIModelDidChange;

- (nullable NSString *)serializedSourceText;

@end

NS_ASSUME_NONNULL_END