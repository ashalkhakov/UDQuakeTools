/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 * UDReferencePicker.h — what a field names, chosen from a list: a sheet
 * (modal on GNUstep) with the candidates in a table, filtered as a name is
 * typed (the names containing it, in any case), the current one chosen.
 * XFormsKit's palette panel's filter, in a XIB (UDReferencePicker.xib).
 * Double-click or OK chooses; Escape or Cancel does not.
 */

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface UDReferencePicker : NSWindowController <NSTableViewDataSource, NSTableViewDelegate>

/// @a names to choose from (each with what it is, in @a details, if
/// given), @a current chosen at first.
- (instancetype)initWithTitle:(NSString *)title names:(NSArray<NSString *> *)names
                      details:(nullable NSArray<NSString *> *)details current:(nullable NSString *)current;

/// The sheet over @a window; on OK, @a action sent to @a target (the sender
/// the picker, its chosenName the name).
- (void)beginSheetForWindow:(NSWindow *)window target:(id)target action:(SEL)action;

@property (nonatomic, copy, readonly, nullable) NSString *chosenName;
/// The filter as typed; the names shown (its rows).
@property (nonatomic, copy, readonly) NSArray<NSString *> *shownNames;

@property (weak) IBOutlet NSTextField *titleLabel;
@property (weak) IBOutlet NSTextField *filterField;
@property (weak) IBOutlet NSTableView *table;
@property (weak) IBOutlet NSTextField *countLabel;
@property (weak) IBOutlet NSButton *okButton;
- (IBAction)filterChanged:(nullable id)sender;
- (IBAction)ok:(nullable id)sender;
- (IBAction)cancel:(nullable id)sender;

@end

NS_ASSUME_NONNULL_END
