#import "UDDeclEditorViewController.h"

@class UDDeclAF;

NS_ASSUME_NONNULL_BEGIN

/**
 * An articulated figure's editor, in the window's three panes: in the
 * centre its bodies and its constraints, a list each (chosen, added, taken
 * off); in the inspector, the chosen body's or constraint's every keyword
 * its parser reads, edited in place, or, nothing chosen, the figure's
 * settings. What idAF::Load would refuse is in the Issues tab, in its
 * words: no or a defaulted modelDef or model, no body on the origin joint,
 * a body on a joint the model lacks, a constraint on a body the figure
 * lacks. Laid out in UDAFEditorView.xib; the simulation preview comes with
 * the engine bridge, in the centre.
 */
@interface UDAFEditorViewController : UDDeclEditorViewController <UDInspecting>

@property (nonatomic, readonly, nullable) UDDeclAF *figure;

/// One of the two lists has a selection at a time.
@property (strong) IBOutlet NSArrayController *bodiesController;
@property (weak) IBOutlet NSTableView *bodiesTable;
@property (strong) IBOutlet NSArrayController *constraintsController;
@property (weak) IBOutlet NSTableView *constraintsTable;

/// The inspector's Properties: tabs (tabless) of the figure's settings
/// ("figure"), the chosen body's ("body") and constraint's ("constraint"),
/// each scrolled.
@property (strong) IBOutlet NSView *inspectorView;
@property (weak) IBOutlet NSTabView *inspectorTabs;
@property (weak) IBOutlet NSScrollView *figureScroll;
@property (weak) IBOutlet NSScrollView *bodyScroll;
@property (weak) IBOutlet NSScrollView *constraintScroll;

/// + adds a body by idDeclAF::NewBody, last; - takes the selected one off
/// by DeleteBody, the constraints on it with it.
- (IBAction)addOrRemoveBody:(nullable id)sender;
/// + adds a constraint by NewConstraint, last; - takes the selected one off.
- (IBAction)addOrRemoveConstraint:(nullable id)sender;

@end

NS_ASSUME_NONNULL_END
