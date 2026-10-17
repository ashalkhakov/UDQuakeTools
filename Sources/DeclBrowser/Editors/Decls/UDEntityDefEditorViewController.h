#import "UDDeclEditorViewController.h"

@class UDDeclEntityDef, UDInheritedKeyValue;

NS_ASSUME_NONNULL_BEGIN

/**
 * An entityDef's (and a mapDef's) editor, DialogEntityDefEditor's: what it
 * inherits, its own spawnArgs in a list edited in place, and what it
 * inherits and does not set, read-only, to override. The help for the
 * entity and for a selected key is the editor_* keys', as Radiant read
 * them. An inherited entityDef no file defines, and a key set twice, are in
 * the Issues tab. Laid out in UDEntityDefEditorView.xib.
 */
@interface UDEntityDefEditorViewController : UDDeclEditorViewController

@property (nonatomic, readonly, nullable) UDDeclEntityDef *entityDef;

@property (strong) IBOutlet NSArrayController *keyValuesController;
@property (strong) IBOutlet NSArrayController *inheritedController;
@property (weak) IBOutlet NSTableView *keyValuesTable;
@property (weak) IBOutlet NSTableView *inheritedTable;

/// What it inherits and does not set (UDInheritedKeyValue), its help, and
/// the selected key's: the XIB's bindings show them.
@property (nonatomic, copy, readonly) NSArray<UDInheritedKeyValue *> *inheritedKeyValues;
@property (nonatomic, copy, readonly, nullable) NSString *usage;
@property (nonatomic, copy, readonly, nullable) NSString *selectedKeyHelp;

/// + adds a pair after the selection, its key to be typed; - takes the
/// selected one off.
- (IBAction)addOrRemovePair:(nullable id)sender;
/// The selected inherited pair, set here: DialogEntityDefEditor's Add of a
/// key it inherits.
- (IBAction)overrideInherited:(nullable id)sender;

@end

NS_ASSUME_NONNULL_END
