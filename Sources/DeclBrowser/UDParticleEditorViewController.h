#import "UDDeclEditorViewController.h"

@class UDDeclParticle;

NS_ASSUME_NONNULL_BEGIN

/**
 * A particle decl's editor, DialogParticleEditor's: its stages in a list,
 * and the selected stage's every parameter (with the dialog's sliders),
 * edited in place; the particle's depth hack. What a stage names that is
 * not there is in the Issues tab: a material the engine makes a default of,
 * a table no decl defines. Laid out in UDParticleEditorView.xib.
 */
@interface UDParticleEditorViewController : UDDeclEditorViewController <NSTableViewDataSource>

@property (nonatomic, readonly, nullable) UDDeclParticle *particle;

@property (strong) IBOutlet NSArrayController *stagesController;
@property (weak) IBOutlet NSTableView *stagesTable;

/// + adds a stage after the selection, the engine's default one (a copy of
/// the selected one with Option, as AddStage's Ctrl had it); - takes the
/// selected one off.
- (IBAction)addOrRemoveStage:(nullable id)sender;

@end

NS_ASSUME_NONNULL_END
