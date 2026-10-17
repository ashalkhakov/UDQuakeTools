#import "UDDeclEditorViewController.h"

@class UDDeclSound;

NS_ASSUME_NONNULL_BEGIN

/**
 * A sound shader's editor: its description and parameters (empty is the
 * engine's default, which the field shows), its flags and speakers, and its
 * samples and leadins in lists edited in place. What it names that is not
 * there is in the Issues tab: a sample the engine would play its default
 * sound for, an alt sound no shader defines. Laid out in
 * UDSoundEditorView.xib.
 */
@interface UDSoundEditorViewController : UDDeclEditorViewController

@property (nonatomic, readonly, nullable) UDDeclSound *sound;

@property (strong) IBOutlet NSArrayController *samplesController;
@property (strong) IBOutlet NSArrayController *leadinsController;
@property (weak) IBOutlet NSTableView *samplesTable;
@property (weak) IBOutlet NSTableView *leadinsTable;

- (IBAction)addOrRemoveSample:(NSSegmentedControl *)sender;
- (IBAction)addOrRemoveLeadin:(NSSegmentedControl *)sender;

@end

NS_ASSUME_NONNULL_END
