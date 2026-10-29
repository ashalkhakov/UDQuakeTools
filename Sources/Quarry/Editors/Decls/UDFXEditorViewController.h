#import "UDDeclEditorViewController.h"

@class UDDeclFX, UDFXTimelineView, UDParticlePreview, UDTransportController;

NS_ASSUME_NONNULL_BEGIN

/**
 * An FX decl's editor, in the window's three panes: in the centre its
 * particle systems playing, its actions over its time, and its actions in
 * a list (chosen, added, taken off, dragged into another order); in the
 * inspector, a pane of the FX's own keywords (the joint it binds to) and
 * one of the selected action's every keyword ParseSingleFXAction reads,
 * edited in place. What an action uses that the engine would not find is in the
 * Issues tab, as the engine has it: a material no decl or image is, a model
 * of a type it does not load, a particle, entityDef or sound shader no decl
 * defines, a light or model to use that no earlier action names. Laid out
 * in UDFXEditorView.xib.
 */
@interface UDFXEditorViewController : UDDeclEditorViewController <NSTableViewDataSource, UDInspecting>

@property (nonatomic, readonly, nullable) UDDeclFX *fx;

@property (strong) IBOutlet NSArrayController *actionsController;
@property (weak) IBOutlet NSTableView *actionsTable;
/// Its particle systems playing as the engine plays the FX, and its actions
/// over its time (UDParticlePreview, UDFXTimelineView).
@property (weak) IBOutlet NSImageView *previewView;
@property (weak) IBOutlet UDFXTimelineView *timelineView;
@property (nonatomic, strong, readonly, nullable) UDParticlePreview *preview;
/// The preview's time controls (UDTransportController's bar, in
/// transportView).
@property (weak) IBOutlet NSView *transportView;
@property (nonatomic, strong, readonly, nullable) UDTransportController *transport;

/// The inspector's panes, as Xcode's have a file's own and its selection's:
/// FX, the FX's keywords (documentInspectorView), and Action, the selected action's
/// (inspectorView: inspectorTabs' "action" page, or "none"), each scrolled.
@property (strong) IBOutlet NSView *documentInspectorView;
@property (strong) IBOutlet NSView *inspectorView;
@property (weak) IBOutlet NSTabView *inspectorTabs;
@property (weak) IBOutlet NSScrollView *effectScroll;
@property (weak) IBOutlet NSScrollView *actionScroll;

/// The action at @a index to before row @a row (a drag's drop above it),
/// selected after; NO where that is where it is.
- (BOOL)moveActionAtIndex:(NSUInteger)index toRow:(NSUInteger)row;

/// + adds the default definition's action after the selection; - takes the
/// selected one off.
- (IBAction)addOrRemoveAction:(nullable id)sender;

/// The Action pane shown (a click in the list).
- (IBAction)showSelectionInspector:(nullable id)sender;

@end

NS_ASSUME_NONNULL_END
