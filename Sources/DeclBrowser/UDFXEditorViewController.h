#import "UDDeclEditorViewController.h"

@class UDDeclFX, UDFXTimelineView, UDParticlePreview;

NS_ASSUME_NONNULL_BEGIN

/**
 * An FX decl's editor: the joint it binds to, its actions in a list, and
 * the selected action's every keyword ParseSingleFXAction reads, edited in
 * place. What an action uses that the engine would not find is in the
 * Issues tab, as the engine has it: a material no decl or image is, a model
 * of a type it does not load, a particle, entityDef or sound shader no decl
 * defines, a light or model to use that no earlier action names. Laid out
 * in UDFXEditorView.xib.
 */
@interface UDFXEditorViewController : UDDeclEditorViewController

@property (nonatomic, readonly, nullable) UDDeclFX *fx;

@property (strong) IBOutlet NSArrayController *actionsController;
@property (weak) IBOutlet NSTableView *actionsTable;
/// Its particle systems playing as the engine plays the FX, and its actions
/// over its time (UDParticlePreview, UDFXTimelineView).
@property (weak) IBOutlet NSImageView *previewView;
@property (weak) IBOutlet UDFXTimelineView *timelineView;
@property (nonatomic, strong, readonly, nullable) UDParticlePreview *preview;

/// + adds the default definition's action after the selection; - takes the
/// selected one off.
- (IBAction)addOrRemoveAction:(nullable id)sender;
/// Plays the preview from the start again.
- (IBAction)restartPreview:(nullable id)sender;

@end

NS_ASSUME_NONNULL_END
