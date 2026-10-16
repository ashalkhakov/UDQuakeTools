#import "UDDeclEditorViewController.h"

@class UDDeclTable, UDTableGraphView;

NS_ASSUME_NONNULL_BEGIN

/**
 * A table decl's editor: Snap and Clamp, its values in a list (edited in
 * place; + adds one after the selection, - takes the selection off), and
 * the curve they make. Laid out in UDTableEditorView.xib.
 */
@interface UDTableEditorViewController : UDDeclEditorViewController <NSTableViewDataSource, NSTableViewDelegate>

@property (nonatomic, readonly, nullable) UDDeclTable *table;

@property (weak) IBOutlet NSTableView *valuesTable;
@property (weak) IBOutlet UDTableGraphView *graphView;

/// The values, as numbers.
@property (nonatomic, readonly) NSArray<NSNumber *> *values;

- (IBAction)addOrRemoveValue:(NSSegmentedControl *)sender;

@end

/// The curve a table's values make: linear between them, or steps when it
/// snaps, as idDeclTable::TableLookup reads them.
@interface UDTableGraphView : NSView
@property (nonatomic, copy) NSArray<NSNumber *> *values;
@property (nonatomic) BOOL snap;
@end

NS_ASSUME_NONNULL_END
