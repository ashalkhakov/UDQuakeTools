#import "UDDeclEditorViewController.h"

@class UDDeclFX;

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

/// + adds the default definition's action after the selection; - takes the
/// selected one off.
- (IBAction)addOrRemoveAction:(nullable id)sender;

@end

NS_ASSUME_NONNULL_END
