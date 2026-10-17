#import "UDDeclEditorViewController.h"

@class UDDeclParticle, UDParticlePreview, UDTransportController;

NS_ASSUME_NONNULL_BEGIN

/**
 * A particle decl's editor, DialogParticleEditor's, in the window's three
 * panes: in the centre the system playing and its stages in a list
 * (chosen, added, taken off, dragged into another order); in the
 * inspector, the selected stage's every parameter (with the dialog's
 * sliders), edited in place, and the particle's depth hack. What a stage
 * names that is not there is in the Issues tab: a material the engine makes
 * a default of, a table no decl defines. Laid out in
 * UDParticleEditorView.xib.
 */
@interface UDParticleEditorViewController : UDDeclEditorViewController <NSTableViewDataSource, UDInspecting>

@property (nonatomic, readonly, nullable) UDDeclParticle *particle;

@property (strong) IBOutlet NSArrayController *stagesController;
@property (weak) IBOutlet NSTableView *stagesTable;
/// The system playing, as the engine draws it (UDParticlePreview).
@property (weak) IBOutlet NSImageView *previewView;
@property (nonatomic, strong, readonly, nullable) UDParticlePreview *preview;
/// The preview's time controls (UDTransportController's bar, in
/// transportView).
@property (weak) IBOutlet NSView *transportView;
@property (nonatomic, strong, readonly, nullable) UDTransportController *transport;

/// The inspector's Properties: a tab of the particle's keywords and one of
/// the selected stage's (inspectorTabs, tabless), each scrolled.
@property (strong) IBOutlet NSView *inspectorView;
@property (weak) IBOutlet NSTabView *inspectorTabs;
@property (weak) IBOutlet NSScrollView *particleScroll;
@property (weak) IBOutlet NSScrollView *stageScroll;

/// The stage at @a index to before row @a row (a drag's drop above it),
/// selected after; NO where that is where it is.
- (BOOL)moveStageAtIndex:(NSUInteger)index toRow:(NSUInteger)row;

/// + adds a stage after the selection, the engine's default one (a copy of
/// the selected one with Option, as AddStage's Ctrl had it); - takes the
/// selected one off.
- (IBAction)addOrRemoveStage:(nullable id)sender;

@end

NS_ASSUME_NONNULL_END
