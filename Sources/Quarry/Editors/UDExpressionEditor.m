/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 * UDExpressionEditor.m
 */

#import "UDExpressionEditor.h"
#import "UDExpressionTextStorage.h"

@implementation UDExpressionEntry

+ (instancetype)entryNamed:(NSString *)name insertion:(NSString *)insertion summary:(NSString *)summary {
    UDExpressionEntry *entry = [[UDExpressionEntry alloc] init];
    entry->_name = [name copy];
    entry->_insertion = [insertion ?: name copy];
    entry->_summary = [summary copy];
    return entry;
}

@end

@implementation UDExpressionCategory

+ (instancetype)categoryNamed:(NSString *)name entries:(NSArray<UDExpressionEntry *> *)entries {
    UDExpressionCategory *category = [[UDExpressionCategory alloc] init];
    category->_name = [name copy];
    category->_entries = [entries copy];
    return category;
}

@end

@interface UDExpressionEditor ()
@property (nonatomic, copy) NSString *editorTitle;
@property (nonatomic, copy) NSString *initialText;
@property (nonatomic, copy) NSArray<UDExpressionCategory *> *categories;
@property (nonatomic, copy) NSArray<UDExpressionEntry *> *items;
@property (nonatomic, weak, nullable) id target;
@property (nonatomic, nullable) SEL action;
@end

@implementation UDExpressionEditor

- (instancetype)initWithTitle:(NSString *)title text:(NSString *)text categories:(NSArray<UDExpressionCategory *> *)categories {
    self = [super initWithWindowNibName:@"UDExpressionEditor" owner:self];
    if (self) {
        _editorTitle = [title copy];
        _initialText = [text copy];
        _categories = [categories copy];
        _items = @[];
    }
    return self;
}

- (void)windowDidLoad {
    [super windowDidLoad];
    self.titleLabel.stringValue = self.editorTitle;
    // in code, not the XIB: a text view's storage is its layout manager's
    UDExpressionTextStorage *storage = [UDExpressionTextStorage installedInTextView:self.sourceView];
    NSMutableSet<NSString *> *known = [NSMutableSet set];
    NSMutableSet<NSString *> *tables = [NSMutableSet set];
    for (UDExpressionCategory *category in self.categories) {
        for (UDExpressionEntry *entry in category.entries) {
            [(category.tables ? tables : known) addObject:entry.name];
        }
    }
    storage.knownNames = known;
    storage.tableNames = tables;
    self.sourceView.richText = NO;
    self.sourceView.allowsUndo = YES;
    self.sourceView.delegate = self;
    [self setText:self.initialText];
    self.itemTable.target = self;
    self.itemTable.doubleAction = @selector(insert:);
    if (self.categories.count > 0) [self selectCategoryNamed:self.categories[0].name];
}

- (void)beginSheetForWindow:(NSWindow *)window target:(id)target action:(SEL)action {
    self.target = target;
    self.action = action;
    NSWindow *sheet = self.window;
    [sheet makeFirstResponder:self.sourceView];
    [NSApp beginSheet:sheet modalForWindow:window modalDelegate:self
       didEndSelector:@selector(_sheetDidEnd:returnCode:contextInfo:) contextInfo:NULL];
}

/// The sheet down; on OK the target called (in an app-modal session NSApp's
/// sendAction:to:from: would not reach it).
- (void)_sheetDidEnd:(NSWindow *)sheet returnCode:(NSInteger)returnCode contextInfo:(void *)contextInfo {
    [sheet orderOut:self];
    id target = self.target;
    if (returnCode == NSModalResponseOK && target != nil && self.action != NULL && [target respondsToSelector:self.action]) {
        void (*send)(id, SEL, id) = (void (*)(id, SEL, id))[target methodForSelector:self.action];
        send(target, self.action, self);
    }
}

#pragma mark - The text

- (NSString *)text {
    return [self.sourceView.string copy] ?: self.initialText;
}

- (void)setText:(NSString *)text {
    (void)self.window;
    NSTextStorage *storage = self.sourceView.textStorage;
    [storage replaceCharactersInRange:NSMakeRange(0, storage.length) withString:text ?: @""];
    [self check];
}

- (NSString *)status {
    return self.statusLabel.stringValue;
}

/// The checker's word on it: what is wrong, or that it reads.
- (void)check {
    NSString *problem = [self.checker expressionEditor:self problemWith:self.text];
    if (problem.length > 0) {
        self.statusLabel.stringValue = problem;
        self.statusLabel.textColor = [NSColor colorWithCalibratedRed:0.85 green:0.32 blue:0.26 alpha:1];
    } else {
        self.statusLabel.stringValue = self.text.length > 0 ? @"Reads as the engine reads it." : @"";
        self.statusLabel.textColor = [NSColor secondaryLabelColor];
    }
}

- (void)textDidChange:(NSNotification *)notification {
    [self check];
}

#pragma mark - Inserting

- (void)selectCategoryNamed:(NSString *)name {
    (void)self.window;
    for (NSUInteger i = 0; i < self.categories.count; i++) {
        if ([self.categories[i].name isEqualToString:name]) {
            [self.categoryTable selectRowIndexes:[NSIndexSet indexSetWithIndex:i] byExtendingSelection:NO];
            self.items = self.categories[i].entries;
            [self.itemTable reloadData];
            [self _showSummary];
            return;
        }
    }
}

- (BOOL)insertEntryNamed:(NSString *)name {
    for (NSUInteger i = 0; i < self.items.count; i++) {
        if ([self.items[i].name isEqualToString:name]) {
            [self.itemTable selectRowIndexes:[NSIndexSet indexSetWithIndex:i] byExtendingSelection:NO];
            [self insert:nil];
            return YES;
        }
    }
    return NO;
}

/// The entry at the caret, in the selection's place.
- (IBAction)insert:(id)sender {
    NSInteger row = self.itemTable.selectedRow;
    if (row < 0 || row >= (NSInteger)self.items.count) {
        NSBeep();
        return;
    }
    NSString *insertion = self.items[(NSUInteger)row].insertion;
    NSRange at = self.sourceView.selectedRange;
    if (at.location == NSNotFound || NSMaxRange(at) > self.sourceView.string.length) {
        at = NSMakeRange(self.sourceView.string.length, 0);
    }
    if ([self.sourceView shouldChangeTextInRange:at replacementString:insertion]) {
        [self.sourceView.textStorage replaceCharactersInRange:at withString:insertion];
        [self.sourceView didChangeText];
    }
    self.sourceView.selectedRange = NSMakeRange(at.location + insertion.length, 0);
    [self check];
}

- (void)_showSummary {
    NSInteger row = self.itemTable.selectedRow;
    self.summaryLabel.stringValue = row >= 0 && row < (NSInteger)self.items.count ? self.items[(NSUInteger)row].summary : @"";
}

- (IBAction)ok:(id)sender {
    [NSApp endSheet:self.window returnCode:NSModalResponseOK];
}

- (IBAction)cancel:(id)sender {
    [NSApp endSheet:self.window returnCode:NSModalResponseCancel];
}

- (void)cancelOperation:(id)sender {
    [self cancel:sender];
}

#pragma mark - The tables

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    return tableView == self.categoryTable ? (NSInteger)self.categories.count : (NSInteger)self.items.count;
}

- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)column row:(NSInteger)row {
    if (tableView == self.categoryTable) {
        return row >= 0 && row < (NSInteger)self.categories.count ? self.categories[(NSUInteger)row].name : nil;
    }
    return row >= 0 && row < (NSInteger)self.items.count ? self.items[(NSUInteger)row].name : nil;
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification {
    if (notification.object == self.categoryTable) {
        NSInteger row = self.categoryTable.selectedRow;
        if (row >= 0 && row < (NSInteger)self.categories.count) {
            self.items = self.categories[(NSUInteger)row].entries;
            [self.itemTable reloadData];
        }
    }
    [self _showSummary];
}

@end
