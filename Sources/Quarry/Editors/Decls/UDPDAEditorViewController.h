#import "UDDeclEditorViewController.h"

@class UDDeclBase, UDDeclPDA, UDDeclEmail, UDDeclVideo, UDDeclAudio;

@class UDWorkspace;

NS_ASSUME_NONNULL_BEGIN

@interface UDPDAEditorViewController : UDDeclEditorViewController

/** The managed PDA decl being edited (pulled from the workspace's decl editing context). */
@property (nonatomic, readonly, nullable) UDDeclPDA *pda;

@property (strong) IBOutlet NSArrayController *audioArrayController;
@property (strong) IBOutlet NSArrayController *videoArrayController;
@property (strong) IBOutlet NSArrayController *emailArrayController;

/// Its diagnostics: what the PDA references that no decl defines (an email,
/// audio log or video), as errors, checked as the PDA is opened and edited,
/// before it is saved. -revealDiagnostic: shows the list's tab, its row.

@property (weak) IBOutlet NSTabView *tabView;

- (IBAction)generateId:(NSSegmentedControl *)sender;
- (IBAction)addOrRemoveAudioLog:(NSSegmentedControl *)sender;
- (IBAction)addOrRemoveEmail:(NSSegmentedControl *)sender;
- (IBAction)addOrRemoveVideo:(NSSegmentedControl *)sender;
- (IBAction)audioLogEdit:(id)sender;
- (IBAction)emailEdit:(id)sender;
- (IBAction)videoEdit:(id)sender;

@end

/// A PDA's child's sheet (an audio log's, an email's, a video's): its
/// fields, and pickers for the ones that name something.
@interface UDPDAChildEditorViewController : NSObject
@property IBOutlet NSWindow *window;
@property (strong) IBOutlet NSObjectController *objectController;
/// Where the pickers' names come from.
@property (nonatomic, weak, nullable) UDWorkspace *workspace;
@property (nonatomic, strong, readonly, nullable) UDReferencePicker *referencePicker;
/// The picker of the field whose "…" has tag @a tag (subclasses say).
- (nullable UDReferenceField *)referenceFieldForTag:(NSInteger)tag;
- (IBAction)pickReference:(nullable id)sender;
@end

@interface UDPDAAudioEditorViewController : UDPDAChildEditorViewController

@property UDDeclAudio *editingAudio;

- (IBAction)ok:(id)sender;
- (IBAction)cancel:(id)sender;

@end

@interface UDPDAEmailEditorViewController : UDPDAChildEditorViewController

@property UDDeclEmail *editingEmail;

- (IBAction)ok:(id)sender;
- (IBAction)cancel:(id)sender;

@end

@interface UDPDAVideoEditorViewController : UDPDAChildEditorViewController

@property UDDeclVideo *editingVideo;

- (IBAction)ok:(id)sender;
- (IBAction)cancel:(id)sender;

@end

NS_ASSUME_NONNULL_END
