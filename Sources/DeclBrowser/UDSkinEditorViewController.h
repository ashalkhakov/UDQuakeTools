#import "UDDeclEditorViewController.h"

@class UDDeclSkin;

NS_ASSUME_NONNULL_BEGIN

/**
 * A skin decl's editor: its mappings, from a material ("*" for all) to
 * another, and the models it goes with, each in a list edited in place.
 * What it names that is not there is in the Issues tab: a material neither
 * a decl nor an image (the engine makes it a default material), a model not
 * found. Laid out in UDSkinEditorView.xib.
 */
@interface UDSkinEditorViewController : UDDeclEditorViewController <NSTableViewDataSource, NSTableViewDelegate>

@property (nonatomic, readonly, nullable) UDDeclSkin *skin;

@property (weak) IBOutlet NSTableView *mappingsTable;
@property (weak) IBOutlet NSTableView *modelsTable;

/// The mappings, each @[from, to]; the models.
@property (nonatomic, readonly) NSArray<NSArray<NSString *> *> *mappings;
@property (nonatomic, readonly) NSArray<NSString *> *models;

- (IBAction)addOrRemoveMapping:(NSSegmentedControl *)sender;
- (IBAction)addOrRemoveModel:(NSSegmentedControl *)sender;

@end

NS_ASSUME_NONNULL_END
