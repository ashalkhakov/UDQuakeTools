#import "UDDeclEditorViewController.h"

@class UDDeclAF;

NS_ASSUME_NONNULL_BEGIN

/**
 * An articulated figure's editor: its settings, its bodies and its
 * constraints, each list with the selected one's every keyword its parser
 * reads, edited in place. What idAF::Load would refuse is in the Issues
 * tab, in its words: no or a defaulted modelDef or model, no body on the
 * origin joint, a body on a joint the model lacks, a constraint on a body
 * the figure lacks. Laid out in UDAFEditorView.xib; the simulation preview
 * comes with the engine bridge.
 */
@interface UDAFEditorViewController : UDDeclEditorViewController

@property (nonatomic, readonly, nullable) UDDeclAF *figure;

@property (weak) IBOutlet NSTabView *tabView;
@property (strong) IBOutlet NSArrayController *bodiesController;
@property (weak) IBOutlet NSTableView *bodiesTable;
@property (strong) IBOutlet NSArrayController *constraintsController;
@property (weak) IBOutlet NSTableView *constraintsTable;

/// + adds a body by idDeclAF::NewBody, last; - takes the selected one off
/// by DeleteBody, the constraints on it with it.
- (IBAction)addOrRemoveBody:(nullable id)sender;
/// + adds a constraint by NewConstraint, last; - takes the selected one off.
- (IBAction)addOrRemoveConstraint:(nullable id)sender;

@end

NS_ASSUME_NONNULL_END
