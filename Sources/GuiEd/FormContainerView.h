//
//  FormContainerView.h
//  Reusable dynamic form layout container for Cocoa/GNUstep
//  Works with XIBs: 
//   1. Place a Custom View in your XIB, set class = FormContainerView.
//   2. Drop labels (NSTextField non-editable) + controls directly inside it in IB (in order).
//   3. It will automatically rearrange them into aligned rows at runtime.
//   Programmatic addEntry: still supported for dynamic cases.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface FormContainerView : NSView

// Layout metrics (tweak for your design or platform preferences)
@property (nonatomic) CGFloat topMargin;
@property (nonatomic) CGFloat bottomMargin;
@property (nonatomic) CGFloat leftMargin;
@property (nonatomic) CGFloat rightMargin;
@property (nonatomic) CGFloat interlineSpacing;     // vertical gap between rows
@property (nonatomic) CGFloat labelControlGap;      // horizontal gap between label and control
@property (nonatomic) BOOL autoLabelWidth;          // YES = compute max label width across all rows
@property (nonatomic) CGFloat fixedLabelWidth;      // used when autoLabelWidth = NO
@property (nonatomic) NSTextAlignment labelAlignment; // NSTextAlignmentLeft / Right / Center
@property (nonatomic) BOOL chainsKeyViews;          // automatically chain nextKeyView for tabbing

// Add / manage entries. The control can be any NSView/NSControl (NSTextField, NSComboBox, NSButton, etc.)
- (void)addEntryWithLabel:(NSString *)labelText control:(NSView *)control;
- (void)insertEntryAtIndex:(NSUInteger)index label:(NSString *)labelText control:(NSView *)control;
- (void)removeEntryAtIndex:(NSUInteger)index;
- (void)removeAllEntries;

- (NSUInteger)numberOfEntries;
- (nullable NSView *)controlAtIndex:(NSUInteger)index;
- (nullable NSString *)labelTextAtIndex:(NSUInteger)index;

// Force layout (usually automatic after add/remove/resize)
- (void)layoutEntries;

// Approximate size needed to fit all content (useful with NSScrollView or Auto Layout)
- (NSSize)formContentSize;

// Convenience: focus the first control
- (void)focusFirstField;

@end

NS_ASSUME_NONNULL_END