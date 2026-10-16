#import "UDDeclEditorViewController.h"

@class UDDeclMaterial;

NS_ASSUME_NONNULL_BEGIN

/**
 * A material's editor: its keywords (Material) and its stages (Stages), each
 * stage's keywords and its image as the renderer would load it. Edits put a
 * keyword in, change it or take it out; the rest of the text stays as it
 * was. What idMaterial::Parse says of the material is in the Issues tab, and
 * an image it would not find, as the image manager says it. Laid out in
 * UDMaterialEditorView.xib; the 3D preview comes with the engine bridge.
 */
@interface UDMaterialEditorViewController : UDDeclEditorViewController <NSTableViewDataSource>

@property (nonatomic, readonly, nullable) UDDeclMaterial *material;

@property (weak) IBOutlet NSTabView *tabView;
@property (strong) IBOutlet NSArrayController *stagesController;
@property (weak) IBOutlet NSTableView *stagesTable;
@property (weak) IBOutlet NSImageView *previewView;
@property (weak) IBOutlet NSTextField *previewLabel;

/// + adds a stage, last, as MaterialDoc::AddStage does ("Stage N"); - takes
/// the selected one off.
- (IBAction)addOrRemoveStage:(nullable id)sender;
/// Moves the selected stage up (segment 0) or down (1).
- (IBAction)moveStage:(nullable id)sender;
/// Adds a bump (tag 1), diffuse (2) or specular (3) map stage, last.
- (IBAction)addLightingStage:(nullable id)sender;
/// The selected stage's text to the pasteboard; a stage's text from it,
/// after the selection.
- (IBAction)copy:(nullable id)sender;
- (IBAction)paste:(nullable id)sender;

@end

NS_ASSUME_NONNULL_END
