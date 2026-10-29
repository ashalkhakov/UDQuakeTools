#import "UDDeclEditorViewController.h"

@class UDDeclMaterial, UDParticlePreview, UDTransportController;

NS_ASSUME_NONNULL_BEGIN

/**
 * A material's editor, in the window's three panes (as the Core Data model
 * editor has an entity): in the centre the material lit, its time, and its
 * stages (chosen, added, taken off, dragged into another order); in the
 * inspector, a pane of the material's keywords and one of the selected
 * stage's, with its image as the renderer would load it. Edits put a keyword
 * in, change it or take it out; the rest of the text stays as it was. What
 * idMaterial::Parse says of the material is in the Issues tab, and an image
 * it would not find, as the image manager says it. Laid out in
 * UDMaterialEditorView.xib.
 */
@interface UDMaterialEditorViewController : UDDeclEditorViewController <NSTableViewDataSource, NSTableViewDelegate, UDInspecting>

@property (nonatomic, readonly, nullable) UDDeclMaterial *material;

@property (strong) IBOutlet NSArrayController *stagesController;
@property (weak) IBOutlet NSTableView *stagesTable;
@property (weak) IBOutlet NSImageView *previewView;
@property (weak) IBOutlet NSTextField *previewLabel;
/// The Preview tab: the material lit, as the engine draws it
/// (UDParticlePreview), its time, and why it is not lit, if it is not.
@property (weak) IBOutlet NSImageView *materialPreviewView;
@property (weak) IBOutlet NSTextField *lightingLabel;
/// The preview's time controls (UDTransportController's bar, in
/// transportView).
@property (weak) IBOutlet NSView *transportView;
@property (nonatomic, strong, readonly, nullable) UDTransportController *transport;
@property (nonatomic, strong, readonly, nullable) UDParticlePreview *materialPreview;
/// The inspector's panes, as Xcode's have a file's own and its selection's:
/// Material, the material's keywords (documentInspectorView), and Stage, the selected stage's
/// (inspectorView: inspectorTabs' "stage" page, or "none"), each scrolled.
@property (strong) IBOutlet NSView *documentInspectorView;
@property (strong) IBOutlet NSView *inspectorView;
@property (weak) IBOutlet NSTabView *inspectorTabs;
@property (weak) IBOutlet NSScrollView *materialScroll;
@property (weak) IBOutlet NSScrollView *stageScroll;

/// + adds a stage, last, as MaterialDoc::AddStage does ("Stage N"); - takes
/// the selected one off.
- (IBAction)addOrRemoveStage:(nullable id)sender;
/// Moves the selected stage up (segment 0) or down (1).
- (IBAction)moveStage:(nullable id)sender;
/// Adds a bump (tag 1), diffuse (2) or specular (3) map stage, last.
- (IBAction)addLightingStage:(nullable id)sender;
/// The stage at @a index to before row @a row (a drag's drop above it),
/// selected after; NO where that is where it is.
- (BOOL)moveStageAtIndex:(NSUInteger)index toRow:(NSUInteger)row;
/// The selected stage's text to the pasteboard; a stage's text from it,
/// after the selection.
- (IBAction)copy:(nullable id)sender;
- (IBAction)paste:(nullable id)sender;

/// The Stage pane shown (a click in the list).
- (IBAction)showSelectionInspector:(nullable id)sender;

@end

NS_ASSUME_NONNULL_END
