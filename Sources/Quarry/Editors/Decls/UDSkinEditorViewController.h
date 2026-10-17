#import "UDDeclEditorViewController.h"

@class UDDeclSkin;

NS_ASSUME_NONNULL_BEGIN

/**
 * A skin decl's editor: its mappings, from a material ("*" for all) to
 * another, and the models it goes with, each list an array controller over
 * the skin's, edited in place. What it names that is not there is in the
 * Issues tab: a material neither a decl nor an image (the engine makes it a
 * default material), a model not found. Laid out in UDSkinEditorView.xib.
 */
@interface UDSkinEditorViewController : UDDeclEditorViewController

@property (nonatomic, readonly, nullable) UDDeclSkin *skin;

@property (strong) IBOutlet NSArrayController *mappingsController;
@property (strong) IBOutlet NSArrayController *modelsController;
@property (weak) IBOutlet NSTableView *mappingsTable;
@property (weak) IBOutlet NSTableView *modelsTable;

- (IBAction)addOrRemoveMapping:(NSSegmentedControl *)sender;
- (IBAction)addOrRemoveModel:(NSSegmentedControl *)sender;

@end

NS_ASSUME_NONNULL_END
