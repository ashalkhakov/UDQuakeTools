/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 * UDReferencePicker.m
 */

#import "UDReferencePicker.h"

@interface UDReferencePicker () <NSTextFieldDelegate>
@property (nonatomic, copy) NSString *pickerTitle;
@property (nonatomic, copy) NSArray<NSString *> *names;
@property (nonatomic, copy) NSDictionary<NSString *, NSString *> *details;
@property (nonatomic, copy, nullable) NSString *current;
@property (nonatomic, copy, readwrite) NSArray<NSString *> *shownNames;
@property (nonatomic, copy, readwrite, nullable) NSString *chosenName;
@property (nonatomic, weak, nullable) id target;
@property (nonatomic, nullable) SEL action;
@end

@implementation UDReferencePicker

- (instancetype)initWithTitle:(NSString *)title names:(NSArray<NSString *> *)names
                      details:(NSArray<NSString *> *)details current:(NSString *)current {
    self = [super initWithWindowNibName:@"UDReferencePicker" owner:self];
    if (self) {
        _pickerTitle = [title copy];
        _names = [names copy];
        NSMutableDictionary<NSString *, NSString *> *byName = [NSMutableDictionary dictionary];
        for (NSUInteger i = 0; i < details.count && i < names.count; i++) byName[names[i]] = details[i];
        _details = byName;
        _current = [current copy];
        _shownNames = _names;
    }
    return self;
}

- (void)windowDidLoad {
    [super windowDidLoad];
    self.titleLabel.stringValue = self.pickerTitle;
    self.filterField.delegate = self;
    self.table.target = self;
    self.table.doubleAction = @selector(ok:);
    [self filterChanged:nil];
}

- (void)beginSheetForWindow:(NSWindow *)window target:(id)target action:(SEL)action {
    self.target = target;
    self.action = action;
    NSWindow *sheet = self.window;
    [sheet makeFirstResponder:self.filterField];
    [NSApp beginSheet:sheet modalForWindow:window modalDelegate:self
       didEndSelector:@selector(_sheetDidEnd:returnCode:contextInfo:) contextInfo:NULL];
}

/// The sheet down; on OK the target told. (On GNUstep -beginSheet:… runs
/// the sheet modally, and calls this as it returns.)
- (void)_sheetDidEnd:(NSWindow *)sheet returnCode:(NSInteger)returnCode contextInfo:(void *)contextInfo {
    [sheet orderOut:self];
    id target = self.target;
    if (returnCode == NSModalResponseOK && target != nil && self.action != NULL) {
        [NSApp sendAction:self.action to:target from:self];
    }
}

#pragma mark - The filter (XFDPalettePanel's rebuildRowsWithFilter:)

- (void)controlTextDidChange:(NSNotification *)notification {
    [self filterChanged:notification.object];
}

/// The names containing the filter, in any case; the current one (or the
/// first) chosen.
- (IBAction)filterChanged:(id)sender {
    NSString *filter = [self.filterField.stringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    if (filter.length == 0) {
        self.shownNames = self.names;
    } else {
        NSMutableArray<NSString *> *shown = [NSMutableArray array];
        for (NSString *name in self.names) {
            if ([name rangeOfString:filter options:NSCaseInsensitiveSearch].location != NSNotFound) [shown addObject:name];
        }
        self.shownNames = shown;
    }
    [self.table reloadData];
    NSUInteger row = self.current != nil ? [self.shownNames indexOfObject:self.current] : NSNotFound;
    if (row == NSNotFound && self.shownNames.count > 0) row = 0;
    if (row != NSNotFound) {
        [self.table selectRowIndexes:[NSIndexSet indexSetWithIndex:row] byExtendingSelection:NO];
        [self.table scrollRowToVisible:(NSInteger)row];
    } else {
        [self.table deselectAll:nil];
    }
    self.countLabel.stringValue = [NSString stringWithFormat:@"%lu of %lu", (unsigned long)self.shownNames.count,
                                   (unsigned long)self.names.count];
    self.okButton.enabled = self.shownNames.count > 0;
}

/// Up and down in the filter move the table's choice; Return chooses.
- (BOOL)control:(NSControl *)control textView:(NSTextView *)textView doCommandBySelector:(SEL)command {
    NSInteger row = self.table.selectedRow;
    if (command == @selector(moveDown:) || command == @selector(moveUp:)) {
        NSInteger next = row + (command == @selector(moveDown:) ? 1 : -1);
        if (next >= 0 && next < (NSInteger)self.shownNames.count) {
            [self.table selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)next] byExtendingSelection:NO];
            [self.table scrollRowToVisible:next];
        }
        return YES;
    }
    if (command == @selector(insertNewline:)) {
        [self ok:nil];
        return YES;
    }
    if (command == @selector(cancelOperation:)) {
        [self cancel:nil];
        return YES;
    }
    return NO;
}

- (IBAction)ok:(id)sender {
    NSInteger row = self.table.selectedRow;
    if (row < 0 || row >= (NSInteger)self.shownNames.count) {
        NSBeep();
        return;
    }
    self.chosenName = self.shownNames[(NSUInteger)row];
    [NSApp endSheet:self.window returnCode:NSModalResponseOK];
}

- (IBAction)cancel:(id)sender {
    [NSApp endSheet:self.window returnCode:NSModalResponseCancel];
}

/// Escape, through the panel's responders.
- (void)cancelOperation:(id)sender {
    [self cancel:sender];
}

#pragma mark - The table

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    return (NSInteger)self.shownNames.count;
}

- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)column row:(NSInteger)row {
    if (row < 0 || row >= (NSInteger)self.shownNames.count) return nil;
    NSString *name = self.shownNames[(NSUInteger)row];
    return [column.identifier isEqualToString:@"detail"] ? self.details[name] : name;
}

@end
