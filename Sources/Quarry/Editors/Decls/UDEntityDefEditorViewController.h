#import "UDDeclEditorViewController.h"

@class UDDeclEntityDef, UDInheritedKeyValue;

NS_ASSUME_NONNULL_BEGIN

/// The entry a spawn arg's value takes in the inspector.
typedef NS_ENUM(NSInteger, UDSpawnArgType) {
    UDSpawnArgText,
    UDSpawnArgNumber,
    UDSpawnArgInteger,
    UDSpawnArgVector,       // "x y z"
    UDSpawnArgBool,         // "1" or "0"
    UDSpawnArgColor,        // "r g b", 0 to 1
    UDSpawnArgReference,    // a name, picked
};

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

/// The inspector's Properties (not the engine's: DialogEntityDefEditor
/// edited the values as text): the selected pair's key, its type, and its
/// value in the entry the type takes, a page of valuePages each ("none",
/// "text", "reference", "number", "vector", "bool", "color").
@property (strong) IBOutlet NSView *inspectorView;
@property (weak) IBOutlet NSTabView *valuePages;
@property (weak) IBOutlet NSTextField *keyLabel;
@property (weak) IBOutlet NSTextField *kindLabel;
@property (weak) IBOutlet NSTextField *numberField;
@property (weak) IBOutlet NSTextField *vectorXField;
@property (weak) IBOutlet NSTextField *vectorYField;
@property (weak) IBOutlet NSTextField *vectorZField;
@property (weak) IBOutlet NSButton *boolCheckbox;
@property (weak) IBOutlet NSColorWell *colorWell;
/// A typed entry's edit, written as the value's text (one Undo).
- (IBAction)valueEdited:(nullable id)sender;

/// A pair's type: the editor_* key's that gives its help, else what the
/// key's name says (the retail defs' conventions: snd_, def_, model,
/// mtr_, skin, ...), else what its value looks like. @a kind and
/// @a declType: what a reference's picker lists.
+ (UDSpawnArgType)typeOfKey:(NSString *)key value:(nullable NSString *)value editorType:(nullable NSString *)editorType
                       kind:(nullable UDReferenceKind *)kind declType:(nullable int *)declType;
@property (nonatomic, readonly) UDSpawnArgType selectedType;

/// + adds a pair after the selection, its key to be typed; - takes the
/// selected one off.
- (IBAction)addOrRemovePair:(nullable id)sender;
/// The selected inherited pair, set here: DialogEntityDefEditor's Add of a
/// key it inherits.
- (IBAction)overrideInherited:(nullable id)sender;

@end

NS_ASSUME_NONNULL_END
