/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 * UDExpressionEditor.h — a field's expression in a larger editor: RDLKit's
 * RDLExpressionEditor, as a sheet (modal on GNUstep). The text coloured as
 * it is typed (UDExpressionTextStorage); what it may name, by category
 * (parms, tables, variables, operators), inserted at the caret; what the
 * engine's parser says of it, as it is typed (its checker's). Laid out in
 * UDExpressionEditor.xib.
 */

#import <Cocoa/Cocoa.h>

@class UDExpressionEditor;

NS_ASSUME_NONNULL_BEGIN

/// A name an expression may use: what is inserted, and what it is.
@interface UDExpressionEntry : NSObject
+ (instancetype)entryNamed:(NSString *)name insertion:(nullable NSString *)insertion summary:(NSString *)summary;
@property (nonatomic, copy, readonly) NSString *name;
@property (nonatomic, copy, readonly) NSString *insertion;
@property (nonatomic, copy, readonly) NSString *summary;
@end

@interface UDExpressionCategory : NSObject
+ (instancetype)categoryNamed:(NSString *)name entries:(NSArray<UDExpressionEntry *> *)entries;
@property (nonatomic, copy, readonly) NSString *name;
@property (nonatomic, copy, readonly) NSArray<UDExpressionEntry *> *entries;
/// Its entries are tables (coloured as a lookup before "[").
@property (nonatomic) BOOL tables;
@end

/// What the engine's parser says of an expression: nil when it reads, or
/// what is wrong.
@protocol UDExpressionChecking <NSObject>
- (nullable NSString *)expressionEditor:(UDExpressionEditor *)editor problemWith:(NSString *)text;
@end

@interface UDExpressionEditor : NSWindowController <NSTableViewDataSource, NSTableViewDelegate, NSTextViewDelegate>

- (instancetype)initWithTitle:(NSString *)title text:(NSString *)text categories:(NSArray<UDExpressionCategory *> *)categories;
@property (nonatomic, weak, nullable) id<UDExpressionChecking> checker;

/// The sheet over @a window; on OK, @a action sent to @a target (the sender
/// the editor, its text the expression).
- (void)beginSheetForWindow:(NSWindow *)window target:(id)target action:(SEL)action;

/// The expression as edited; what the status says of it.
@property (nonatomic, copy, readonly) NSString *text;
@property (nonatomic, copy, readonly) NSString *status;
- (void)setText:(NSString *)text;
/// The category shown (by name), and its entry @a name inserted.
- (void)selectCategoryNamed:(NSString *)name;
- (BOOL)insertEntryNamed:(NSString *)name;

@property (weak) IBOutlet NSTextField *titleLabel;
@property (unsafe_unretained) IBOutlet NSTextView *sourceView;
@property (weak) IBOutlet NSTableView *categoryTable;
@property (weak) IBOutlet NSTableView *itemTable;
@property (weak) IBOutlet NSTextField *summaryLabel;
@property (weak) IBOutlet NSTextField *statusLabel;
- (IBAction)insert:(nullable id)sender;
- (IBAction)ok:(nullable id)sender;
- (IBAction)cancel:(nullable id)sender;

@end

NS_ASSUME_NONNULL_END
